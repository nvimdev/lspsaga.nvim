local lsp,api = vim.lsp,vim.api
local config = require('lspsaga').config_values
local symbar = {}
local kind = require('lspsaga.lspkind')
local ns_prefix = '%#LspSagaWinbar'
local symbol_cache = {}
local winbar_sep = '%#LspSagaWinbarSep#'..config.winbar_separator .. '%*'
local method = 'textDocument/documentSymbol'

local function get_file_name()
  local f = vim.fn.expand('%:t')
	local ok,devicons = pcall(require,'nvim-web-devicons')
  local icon,color = '',''
  if ok then
    icon,color = devicons.get_icon_color(f,vim.bo.filetype)
  end
  api.nvim_set_hl(0,'LspSagaWinbarFIcon',{fg=color})
  return ns_prefix..'FIcon#'..icon..' ' ..'%*'.. ns_prefix ..'File#'.. f .. '%*'
end

function symbar:word_symbol_kind()
  local current_buf = api.nvim_get_current_buf()
  local current_word = vim.fn.expand('<cword>')
  local current_win = api.nvim_get_current_win()
  local current_line = api.nvim_win_get_cursor(current_win)[1]
  local params = { textDocument = lsp.util.make_text_document_params() }
  lsp.buf_request_all(current_buf,method,params,function(results)
    local result
    local clients = vim.lsp.buf_get_clients()
    for client_id,_ in pairs(results) do
      if clients[client_id].supports_method(method) then
        result = results[client_id].result
        break
      end
    end

    if result == nil then
      vim.notify('servers all of this buffer does not spport '..method)
      return
    end

    local index,range = 0,{}
    for i,res in pairs(result) do
      table.insert(symbol_cache,res)
    end
  end)
end

function symbar.render_symbol_winbar()
end

return symbar
