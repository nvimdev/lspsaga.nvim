local lsp,api = vim.lsp,vim.api
local config = require('lspsaga').config_values
local show_file = config.winbar_show_file
local saga_group = require('lspsaga').saga_augroup
local libs = require('lspsaga.libs')
local symbar = {
  symbol_cache = {}
}
local kind = require('lspsaga.lspkind')
local ns_prefix = '%#LspSagaWinbar'
local winbar_sep = '%#LspSagaWinbarSep#'..config.winbar_separator .. '%*'
local method = 'textDocument/documentSymbol'

function symbar:get_file_name()
  local f = vim.fn.expand('%:t')
	local ok,devicons = pcall(require,'nvim-web-devicons')
  local f_icon = ''
  local color = ''
  if ok then
    f_icon,color = devicons.get_icon_color(f,vim.bo.filetype)
  end
  api.nvim_set_hl(0,'LspSagaWinbarFIcon',{fg=color})
  return ns_prefix..'FIcon#'..f_icon..' ' ..'%*'.. ns_prefix ..'File#'.. f .. '%*'
end

--@private
local do_symbol_request = function(callback)
  local current_buf = api.nvim_get_current_buf()
  local params = { textDocument = lsp.util.make_text_document_params() }
  lsp.buf_request_all(current_buf,method,params,callback)
end

--@private
local function find_in_node(tbl,line,elements)
  local type,icon = '',''
  for _,node in pairs(tbl) do
    if line >= node.range.start.line and line <= node.range['end'].line then
      type = kind[node.kind][1]
      icon = kind[node.kind][2]
      table.insert(elements,ns_prefix .. type .. '#' .. icon .. node.name)

      if node.children ~= nil then
        find_in_node(node.children,line,elements)
      else
        break
      end
    end
  end
end

--@private
local render_symbol_winbar = function()
  local current_win = api.nvim_get_current_win()
  local current_buf = api.nvim_get_current_buf()
  local current_line = api.nvim_win_get_cursor(current_win)[1]

  local winbar_val = show_file and symbar:get_file_name() or ''

  local symbols = symbar.symbol_cache[current_buf][2]
  print(current_buf,symbols)

  local winbar_elements = {}
  find_in_node(symbols,current_line - 1,winbar_elements)
  local str = table.concat(winbar_elements,winbar_sep)

  if show_file and #winbar_elements > 0 then
    str = winbar_sep .. str
  end

  winbar_val = winbar_val .. str
  api.nvim_win_set_option(current_win,'winbar',winbar_val)
end

function symbar:get_buf_symbol(force,...)
  if not libs.check_lsp_active() then
    return
  end

  force = force or false
  local current_buf = api.nvim_get_current_buf()
  if self.symbol_cache[current_buf] and self.symbol_cache[current_buf][1] and not force then
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

  local arg = {...}
  local fn
  if #arg > 0 then
    fn = unpack(arg)
  end

  local _callback = function(results)
    if libs.result_isempty(results) then
      return
    end

    self.symbol_cache[current_buf] = {true,results[client_id].result}

    if fn ~= nil then
      fn()
    end
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

  api.nvim_create_autocmd({'LspAttach','CursorHold','CursorHoldI'},{
    group = saga_group,
    callback = function()
      if not libs.check_lsp_active() then
        return
      end
      local current_buf = api.nvim_get_current_buf()
      local cache = symbar.symbol_cache
      if cache[current_buf] == nil or next(cache[current_buf]) == nil then
        symbar:get_buf_symbol(true,render_symbol_winbar)
      else
        render_symbol_winbar()
      end
    end,
    desc = 'Lspsaga Document Highlight'
  })

  -- make sure when open file we see the winbar not wait get responses
  -- from server
  if config.winbar_show_file and config.symbol_in_winbar then
    api.nvim_create_autocmd('BufWinEnter',{
      group = saga_group,
      pattern = '*',
      callback = function()
        if vim.bo.filetype == 'help' then return end
        local winbar_str = symbar:get_file_name()
        api.nvim_win_set_option(0,'winbar',winbar_str)
      end,
      desc = 'Lspsaga Add filename into winbar'
    })
  end

  api.nvim_create_autocmd({'TextChanged','InsertLeave'},{
    group = saga_group,
    callback = function()
      if not libs.check_lsp_active() then
        return
      end
      symbar:get_buf_symbol(true,render_symbol_winbar)
    end
  })

  api.nvim_create_autocmd('CursorMoved',{
    group = saga_group,
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
