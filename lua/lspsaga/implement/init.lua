local api, fn, uv, lsp = vim.api, vim.fn, vim.loop, vim.lsp
local config = require('lspsaga').config.implement
local ui = require('lspsaga').config.ui
local ns = api.nvim_create_namespace('SagaImp')
local defined = false
local name = 'SagaImpIcon'
local buffers_cache = {}

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
              print('here')
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
          local id = api.nvim_buf_set_extmark(bufnr, ns, pos.line, 0, {
            virt_lines = { { { #result .. ' ' .. word, 'Comment' } } },
            virt_lines_above = true,
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
    ['rust'] = { 10, 23, 11 },
  }
  return tbl[vim.bo[bufnr].filetype] or { 11 }
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

local function render(client, bufnr, symbols)
  local kinds = langmap(bufnr)
  --TODO: Does there will have perofrmance issue when file is big enough ?
  --Use binary search and line('w0') to render screen visiable area first ?
  for _, item in ipairs(symbols) do
    if vim.tbl_contains(kinds, item.kind) then
      local bufkey = tostring(bufnr)
      local srow = item.selectionRange.start.line
      local scol = item.selectionRange.start.character
      local erow = item.selectionRange['end'].line
      local ecol = item.selectionRange['end'].character

      local word = api.nvim_buf_get_text(bufnr, srow, scol, erow, ecol, {})[1]
      if not buffers_cache[bufkey] then
        buffers_cache[bufkey] = {}
      end

      -- need update before data
      if buffers_cache[bufkey][word] then
        if range_compare(buffers_cache[bufkey][word].range, item.range) then
          buffers_cache[bufkey][word].range = item.range
        end
      else
        buffers_cache[bufkey][word] = {
          range = item.range,
        }
      end
      print(vim.inspect(buffers_cache[bufkey][word]), vim.inspect(item.range))

      try_render(client, bufnr, item.selectionRange.start, buffers_cache[bufkey][word])
    end
    if item.children then
      render(client, bufnr, item.children)
    end
  end
end

local function symbol_request(client, buf)
  local params = { textDocument = lsp.util.make_text_document_params() }
  client.request('textDocument/documentSymbol', params, function(_, result)
    if api.nvim_get_current_buf() ~= buf or not result or next(result) == nil then
      return
    end
    render(client, buf, result)
  end)
end

local function start()
  api.nvim_create_autocmd('LspAttach', {
    callback = function(opt)
      local client = find_client(opt.buf)
      if not client then
        return
      end
      symbol_request(client, opt.buf)
      api.nvim_buf_attach(opt.buf, false, {
        on_lines = function(_, b, _, first_line, last_line, last_in_range)
          if not buffers_cache[tostring(b)] then
            return
          end
          local changed = { first_line, last_line, last_in_range }
          for _, data in pairs(buffers_cache[tostring(b)]) do
            local range = data.range
            if
              vim.tbl_contains(changed, range.start.line)
              or (first_line >= range.start.line and first_line <= range['end'].line)
            then
              symbol_request(client, b)
              break
            end
          end
        end,
      })
    end,
  })
end

return {
  start = start,
  dbp = dbp,
}
