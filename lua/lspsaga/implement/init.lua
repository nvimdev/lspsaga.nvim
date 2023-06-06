local api, fn = vim.api, vim.fn
local config = require('lspsaga').config.implement
local symbol = require('lspsaga.symbol')
local ui = require('lspsaga').config.ui
local ns = api.nvim_create_namespace('SagaImp')
local defined = false
local name = 'SagaImpIcon'
local buffers_cache = {}
---@diagnostic disable-next-line: deprecated
local uv = fn.has('nvim-0.10') == 1 and vim.uv or vim.loop

if not defined then
  fn.sign_define(name, { text = ui.imp_sign, texthl = name })
  defined = true
end

local function render_sign(bufnr, row, data)
  if not config.sign then
    return
  end
  fn.sign_place(row + 1, name, name, bufnr, { lnum = row + 1, priority = config.priority })
  data.sign_id = row + 1
end

local function find_client(buf)
  for _, client in ipairs(vim.lsp.get_active_clients({ bufnr = buf })) do
    if client.supports_method('textDocument/implementation') then
      return client
    end
  end
end

local function try_render(client, bufnr, pos, data)
  local params = {
    position = {
      character = pos.character,
      line = pos.line,
    },
    textDocument = {
      uri = vim.uri_from_bufnr(bufnr),
    },
  }

  local timer = uv.new_timer()
  timer:start(100, 10, function()
    if next(client.messages.progress) == nil and not timer:is_closing() then
      timer:stop()
      timer:close()
      vim.schedule(function()
        client.request('textDocument/implementation', params, function(err, result)
          if err then
            return
          end

          if not result then
            result = {}
          end

          if data.res_count then
            if data.res_count == #result then
              return
            else
              pcall(fn.sign_unplace, name, { buffer = bufnr, id = data.sign_id })
              api.nvim_buf_del_extmark(bufnr, ns, data.virt_id)
            end
          end

          if config.sign and #result > 0 then
            render_sign(bufnr, pos.line, data)
          end

          if not config.virtual_text then
            return
          end
          local word = #result > 1 and 'implementations' or 'implementation'
          local indent
          if vim.bo[bufnr].expandtab then
            local level = vim.fn.indent(pos.line + 1) / vim.bo[bufnr].sw
            indent = (' '):rep(level * vim.bo[bufnr].sw)
          else
            local level = vim.fn.indent(pos.line + 1) / vim.bo[bufnr].tabstop
            indent = ('\t'):rep(level)
          end

          local id = api.nvim_buf_set_extmark(bufnr, ns, pos.line, 0, {
            virt_lines = { { { indent .. #result .. ' ' .. word, 'Comment' } } },
            virt_lines_above = true,
            hl_mode = 'combine',
          })
          data.virt_id = id
          data.res_count = #result
        end, bufnr)
      end)
    end
  end)
end

local function dbp()
  print(vim.inspect(buffers_cache))
end

local function langmap(bufnr)
  local tbl = {
    ['rust'] = {
      kinds = { 10, 11 },
      children = true,
    },
  }
  return tbl[vim.bo[bufnr].filetype] or { kinds = { 11 }, children = false }
end

local function range_compare(r1, r2)
  for k, v in pairs(r1.start) do
    if r2.start[k] ~= v then
      return true
    end
  end

  for k, v in pairs(r1['end']) do
    if r2['end'][k] ~= v then
      return true
    end
  end
end

local function is_rename(data, range, word)
  for before, item in pairs(data) do
    if
      item.range.start.line == range.start.line
      and item.range.start.character == range.start.character
      and word ~= before
    then
      return before
    end
  end
end

local function clean(buf)
  local bufkey = tostring(buf)
  for k, data in pairs(buffers_cache[bufkey] or {}) do
    pcall(api.nvim_buf_del_extmark, buf, ns, data.virt_id)
    pcall(fn.sign_unplace, name, { buffer = buf, id = data.sign_id })
    buffers_cache[bufkey][k] = nil
  end
end

local function render(client, bufnr, symbols, need_clean)
  local langdata = langmap(bufnr)
  local bufkey = tostring(bufnr)
  local new = {}

  local function parse_symbol(nodes)
    for _, item in ipairs(nodes) do
      if vim.tbl_contains(langdata.kinds, item.kind) then
        local srow = item.selectionRange.start.line
        local scol = item.selectionRange.start.character
        local erow = item.selectionRange['end'].line
        local ecol = item.selectionRange['end'].character

        local word = api.nvim_buf_get_text(bufnr, srow, scol, erow, ecol, {})[1]
        new[#new + 1] = word
        local before = is_rename(buffers_cache[bufkey], item.range, word)
        if before then
          buffers_cache[bufkey][before].range = item.range
          buffers_cache[bufkey][word] = vim.deepcopy(buffers_cache[bufkey][before])
          buffers_cache[bufkey][before] = nil
        elseif buffers_cache[bufkey][word] then
          if range_compare(buffers_cache[bufkey][word].range, item.range) then
            buffers_cache[bufkey][word].range = item.range
          end
        else
          buffers_cache[bufkey][word] = {
            range = item.range,
          }
        end

        try_render(client, bufnr, item.selectionRange.start, buffers_cache[bufkey][word])
      end
      if item.children and langdata.children then
        parse_symbol(item.children)
      end
    end
  end

  parse_symbol(symbols)
  if not need_clean then
    return
  end

  if #new == 0 then
    clean(bufnr)
    return
  end

  local non_exists = vim.tbl_filter(function(item)
    return not vim.tbl_contains(new, item)
  end, vim.tbl_keys(buffers_cache[bufkey]) or {})

  if #non_exists == 0 then
    return
  end

  for _, word in ipairs(non_exists) do
    local data = buffers_cache[bufkey][word]
    pcall(api.nvim_buf_del_extmark, bufnr, ns, data.virt_id)
    pcall(fn.sign_unplace, name, { buffer = bufnr, id = data.sign_id })
    buffers_cache[bufkey][word] = nil
  end
end

local function start()
  api.nvim_create_autocmd('User', {
    pattern = 'SagaSymbolUpdate',
    callback = function(opt)
      local client = find_client(opt.buf)
      if not client then
        return
      end
      local bufkey = tostring(opt.buf)
      if buffers_cache[bufkey] then
        return
      end

      buffers_cache[bufkey] = {}
      if next(opt.data.symbols) == nil then
        clean(opt.buf)
        return
      end
      render(client, opt.buf, opt.data.symbols, false)

      if vim.opt.updatetime > 100 then
        vim.notify('[lspsaga] for better experience config update time to 100')
      end

      api.nvim_create_autocmd('CursorHold', {
        buffer = opt.buf,
        callback = function()
          local timer = uv.new_timer()
          timer:start(config.timeout, config.interval, function()
            local res = symbol:get_buf_symbols(opt.buf)
            if vim.tbl_isempty(res) then
              return
            end

            if not res.pending_request and not timer:is_closing() then
              timer:stop()
              timer:close()
              if vim.tbl_isempty(res.symbols) or not res.symbols then
                return
              end
              vim.schedule(function()
                render(client, opt.buf, res.symbols, true)
              end)
            end
          end)
        end,
        desc = '[Lspsaga] Implement show',
      })
    end,
  })
end

return {
  start = start,
  dbp = dbp,
}
