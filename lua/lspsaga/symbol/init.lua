local lsp, api = vim.lsp, vim.api
local libs = require('lspsaga.libs')
local symbol = {}

local cache = {}
symbol.__index = symbol

function symbol.__newindex(t, k, v)
  rawset(t, k, v)
end

local function clean_buf_cache(buf)
  buf = buf or api.nvim_get_current_buf()
  if buf and cache[buf] then
    for k, _ in pairs(cache[buf]) do
      cache[buf][k] = nil
    end
    cache[buf] = nil
  end
end

function symbol:do_request(buf, callback)
  local params = { textDocument = lsp.util.make_text_document_params() }

  local client = libs.get_client_by_cap('documentSymbolProvider')
  if not client then
    vim.notify('[lspsaga.nvim] no servers support documentsymbl request in this buffer')
    return
  end
  if not self[buf] then
    self[buf] = {}
  end

  self[buf].pending_request = true
  client.request('textDocument/documentSymbol', params, function(_, result, ctx)
    if api.nvim_get_current_buf() ~= buf then
      return
    end

    self[ctx.bufnr].pending_request = false
    if not result then
      return
    end

    if callback then
      callback(buf, result)
    end

    self[ctx.bufnr].symbols = result

    api.nvim_buf_attach(buf, false, {
      on_detach = function()
        clean_buf_cache(buf)
      end,
    })
  end, buf)
end

function symbol:get_buf_symbols(buf)
  buf = buf or api.nvim_get_current_buf()
  local res = {}

  if not self[buf] then
    return res
  end

  if self[buf].pending_request then
    res.pending_request = self[buf].pending_request
    return res
  end

  res.symbols = self[buf].symbols
  res.pending_request = self[buf].pending_request
  return res
end

function symbol:node_is_keyword(buf, node)
  if not node.selectionRange then
    return false
  end
  local captures = vim.treesitter.get_captures_at_pos(
    buf,
    node.selectionRange.start.line,
    node.selectionRange.start.character
  )
  for _, v in pairs(captures) do
    if v.capture == 'keyword' or v.capture == 'conditional' or v.capture == 'repeat' then
      return true
    end
  end
  return false
end

function symbol:winbar()
  require('lspsaga.symbol.winbar').symbol_autocmd()
end

function symbol:outline()
  require('lspsaga.symbol.outline'):outline()
end

return setmetatable(cache, symbol)
