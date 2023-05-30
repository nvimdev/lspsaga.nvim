local api, fn = vim.api, vim.fn
local config = require('lspsaga').config.implement
local ui = require('lspsaga').config.ui
local ns = api.nvim_create_namespace('SagaImp')

local defined = false
local name = 'SagaImpIcon'

if not defined then
  fn.sign_define(name, { text = ui.imp_sign, texthl = name })
  defined = true
end

local function render_sign(bufnr, row)
  if not config.sign then
    return
  end
  fn.sign_place(row + 1, name, name, bufnr, { lnum = row + 1, priority = config.priority })
end

local function find_client(buf)
  for _, client in ipairs(vim.lsp.get_active_clients({ bufnr = buf })) do
    if client.supports_method('textDocument/implementation') then
      return client
    end
  end
end

local function try_render(bufnr, range)
  local client = find_client(bufnr)
  if not client then
    return
  end

  local params = {
    position = {
      character = range.character,
      line = range.line,
    },
    textDocument = {
      uri = vim.uri_from_bufnr(bufnr),
    },
  }

  client.request('textDocument/implementation', params, function(err, result)
    if err or not result or vim.tbl_isempty(result) then
      return
    end
    if config.sign then
      render_sign(bufnr, range.line)
    end

    if config.virtual_text then
      api.nvim_buf_set_extmark(bufnr, ns, range.line, 0, {
        virt_lines = { { { ' ' .. #result .. ' implements', 'Comment' } } },
        virt_lines_above = true,
      })
    end
  end, bufnr)
end

local function render(bufnr, symbols)
  for _, item in ipairs(symbols) do
    if item.kind == 11 then
      try_render(bufnr, item.selectionRange.start)
    end
    if item.children then
      render(bufnr, item.children)
    end
  end
end

local function start()
  api.nvim_create_autocmd('User', {
    pattern = 'SagaSymbolUpdate',
    callback = function(opt)
      local symbols = opt.data.symbols
      pcall(fn.sign_unplace, name, { bufnr = opt.buf })
      local top = fn.line('w0')
      local bot = fn.line('w$')
      api.nvim_buf_clear_namespace(opt.buf, ns, top, bot)
      print('here', api.nvim_get_current_line())
      if not symbols or next(symbols) == nil then
        return
      end
      render(opt.buf, symbols)
    end,
  })
end

return {
  start = start,
}
