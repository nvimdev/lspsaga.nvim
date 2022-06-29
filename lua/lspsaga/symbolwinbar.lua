local lsp,api = vim.lsp,vim.api
local config = require('lspsaga').config_values
local saga_group = require('lspsaga').saga_augroup
local libs = require('lspsaga.libs')
local symbar = {
  symbol_cache = {}
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

local do_symbol_request = function(callback)
  local current_buf = api.nvim_get_current_buf()
  local params = { textDocument = lsp.util.make_text_document_params() }
  lsp.buf_request_all(current_buf,method,params,callback)

end

function symbar:get_buf_symbol(force,...)
  if not libs.check_lsp_active() then
    return
  end

  local clients = vim.lsp.buf_get_clients()
  local client_id
  for id,conf in pairs(clients) do
    if conf.server_capabilities.documentHighlightProvider then
      client_id = id
      break
    end
  end

  if client_id == nil then
    vim.nofity('All servers of this buffer does not support '..method)
    return
  end

  local current_buf = api.nvim_get_current_buf()
  if self.symbol_cache[current_buf] and self.symbol_cache[current_buf][1] and not force then
    return
  end

  local _callback = function(results)
    if libs.result_isempty(results) then
      return
    end
    local result
    result = results[client_id].results
    self.symbol_cache[current_buf] = {true,result}
    self.cache_state = true
  end

  do_symbol_request(_callback)
end

--@private
local function removeElementByKey(tbl,key)
  local tmp ={}

  for i in pairs(tbl) do
    table.insert(tmp,i)
  end

  local newTbl = {}
  local i = 1
  while i <= #tmp do
      local val = tmp [i]
      if val == key then
        table.remove(tmp,i)
       else
        newTbl[val] = tbl[val]
        i = i + 1
       end
   end
  return newTbl
end

function symbar:clear_cache()
  local current_buf = api.nvim_get_current_buf()
  if self.symbol_cache[current_buf] then
    self.symbol_cache = removeElementByKey(self.symbol_cache,current_buf)
  end
end

function symbar.config_symbol_autocmd()
  api.nvim_create_autocmd('BufDelete',{
    pattern = '*',
    callback = function()
      symbar:clear_cache()
    end,
    desc = 'Lspsaga clear document symbol cache'
  })

  api.nvim_create_autocmd({'CursorHold','CursorHoldI'},{
    group = saga_group,
    buffer = 0,
    callback = function()
      if next(symbar.symbol_cache) == nil then
        symbar:get_buf_symbol()
      end
    end,
    desc = 'Lspsaga Document Highlight'
  })
-- 
--   api.nvim_create_autocmd('CursorMoved',{
--     group = saga_group,
--     buffer = 0,
--     callback = function()
--       if not libs.check_lsp_active() then
--         return
--       end
--       vim.lsp.buf.clear_references()
--     end,
--     desc = 'Lspsaga Clear All References'
--   })
end

return symbar
