local api, fn = vim.api, vim.fn
---@diagnostic disable-next-line: deprecated
local uv = vim.version().minor >= 10 and vim.uv or vim.loop
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

local function try_render(client_id, bufnr, pos, data)
  local params = {
    position = {
      character = pos.character,
      line = pos.line,
    },
    textDocument = {
      uri = vim.uri_from_bufnr(bufnr),
    },
  }

  local client = vim.lsp.get_client_by_id(client_id)
  if not client then
    return
  end
  ---@diagnostic disable-next-line: invisible
  client.request('textDocument/implementation', params, function(err, result)
    if err or api.nvim_get_current_buf() ~= bufnr then
      return
    end

    if not result then
      result = {}
    end

    if data.res_count then
      if data.res_count == #result then
        return
      end
      pcall(fn.sign_unplace, name, { buffer = bufnr, id = data.sign_id })
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

    if not data.virt_id then
      data.virt_id = uv.hrtime()
    end

    api.nvim_buf_set_extmark(bufnr, ns, pos.line, 0, {
      id = data.virt_id,
      virt_lines = { { { indent .. #result .. ' ' .. word, 'Comment' } } },
      virt_lines_above = true,
      hl_mode = 'combine',
    })
    data.res_count = #result
  end, bufnr)
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

local function clean_data(t, bufnr)
  for _, word in ipairs(t) do
    local data = buffers_cache[bufnr][word]
    pcall(api.nvim_buf_del_extmark, bufnr, ns, data.virt_id)
    pcall(fn.sign_unplace, name, { buffer = bufnr, id = data.sign_id })
    buffers_cache[bufnr][word] = nil
  end
end

local function render(client_id, bufnr, symbols)
  if not api.nvim_buf_is_valid(bufnr) then
    return
  end
  local langdata = langmap(bufnr)
  local hit = buffers_cache[bufnr] and {} or nil

  if not buffers_cache[bufnr] then
    buffers_cache[bufnr] = {}
  end

  local function parse_symbol(nodes)
    for _, item in ipairs(nodes) do
      if vim.tbl_contains(langdata.kinds, item.kind) then
        local range = item.selectionRange or item.range
        local srow = range.start.line
        local scol = range.start.character
        local erow = range['end'].line
        local ecol = range['end'].character
        local ok, res = pcall(api.nvim_buf_get_text, bufnr, srow, scol, erow, ecol, {})
        if not ok then
          return
        end
        local word = res[1]
        if not buffers_cache[bufnr][word] then
          buffers_cache[bufnr][word] = {
            range = item.range,
          }
        else
          if not range_compare(buffers_cache[bufnr][word].range, item.range) then
            buffers_cache[bufnr][word].range = item.range
          end
        end

        if hit then
          hit[#hit + 1] = word
        end

        try_render(client_id, bufnr, item.selectionRange.start, buffers_cache[bufnr][word])
      end
      if item.children and langdata.children then
        parse_symbol(item.children)
      end
    end
  end

  parse_symbol(symbols)

  if hit then
    local nonexist = {}
    if #hit == 0 then
      nonexist = vim.tbl_keys(buffers_cache[bufnr])
    else
      nonexist = vim.tbl_filter(function(word)
        return not vim.tbl_contains(hit, word)
      end, vim.tbl_keys(buffers_cache[bufnr]))
    end

    clean_data(nonexist, bufnr)
  end
end

local function lang_list()
  local t = { 'java', 'cs', 'typescript', 'go', 'swift', 'cpp' }
  return vim.list_extend(t, config.lang)
end

local function start()
  api.nvim_create_autocmd('User', {
    pattern = 'SagaSymbolUpdate',
    callback = function(args)
      if
        api.nvim_get_current_buf() ~= args.data.bufnr
        or not vim.tbl_contains(lang_list(), vim.bo[args.data.bufnr].filetype)
      then
        return
      end

      if api.nvim_get_mode().mode ~= 'n' or api.nvim_get_current_buf() ~= args.data.bufnr then
        return
      end

      if #args.data.symbols > 0 then
        render(args.data.client_id, args.data.bufnr, args.data.symbols)
      elseif buffers_cache[args.data.bufnr] then
        clean_data(vim.tbl_keys(buffers_cache[args.data.bufnr]), args.data.bufnr)
      end
    end,
    desc = '[Lspsaga] Implement show',
  })
end

return {
  start = start,
}
