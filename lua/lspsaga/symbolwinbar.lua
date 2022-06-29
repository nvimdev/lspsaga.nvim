local lsp,api = vim.lsp,vim.api
local config = require('lspsaga').config_values
local saga_group = require('lspsaga').saga_augroup
local libs = require('lspsaga.libs')
local symbar = {
  document_cache = {}
}
local kind = require('lspsaga.lspkind')
local ns_prefix = '%#LspSagaWinbar'
local winbar_sep = '%#LspSagaWinbarSep#'..config.winbar_separator .. '%*'
local method = 'textDocument/documentSymbol'
local rainbow = {
  red = '',orange = '',yellow = '',green = '',cyan = '',blue= '',purple =''
}

function symbar:get_file_name()
  local f = vim.fn.expand('%:t')
	local ok,devicons = pcall(require,'nvim-web-devicons')
  local icon,color = '',''
  if ok then
    icon,color = devicons.get_icon_color(f,vim.bo.filetype)
  end
  api.nvim_set_hl(0,'LspSagaWinbarFIcon',{fg=color})
  return ns_prefix..'FIcon#'..icon..' ' ..'%*'.. ns_prefix ..'File#'.. f .. '%*'
end

function symbar:cache_document_highlight()
  if self.cache_state then return end

  local current_buf = api.nvim_get_current_buf()
  local clients = vim.lsp.buf_get_clients()
  local params = { textDocument = lsp.util.make_text_document_params() }
  lsp.buf_request_all(current_buf,method,params,function(results)
    local result
    for client_id,_ in pairs(results) do
      if clients[client_id].server_capabilities.documentHighlightProvider then
        result = results[client_id].result
        break
      end
    end

    if result == nil then
      vim.notify('All servers of this buffer does not spport '..method)
      return
    end

    for _,res in pairs(result) do
      table.insert(self.document_cache,res)
    end
    self.cache_state = true
  end)
end

function symbar.render_symbol_winbar()
  local current_win = api.nvim_get_current_win()
  local current_line = api.nvim_win_get_cursor(current_win)[1]
end

function symbar.document_highlight()
  if not libs.check_lsp_active() then
    return
  end
  symbar:cache_document_highlight()
end

function symbar.config_document_autocmd()
  api.nvim_create_autocmd({'CursorHold','CursorHoldI'},{
    group = saga_group,
    buffer = 0,
    callback = symbar.document_highlight,
    desc = 'Lspsaga Document Highlight'
  })

  api.nvim_create_autocmd('CursorMoved',{
    group = saga_group,
    buffer = 0,
    callback = function()
      if not libs.check_lsp_active() then
        return
      end
      vim.lsp.buf.clear_references()
    end,
    desc = 'Lspsaga Clear All References'
  })
end

return symbar
