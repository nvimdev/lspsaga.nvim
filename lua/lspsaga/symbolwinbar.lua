local lsp, api = vim.lsp, vim.api
local config = require('lspsaga').config_values.symbol_in_winbar
local saga_group = require('lspsaga').saga_augroup
local libs = require('lspsaga.libs')
local symbar = {
  symbol_cache = {},
}
local kind = require('lspsaga.lspkind')
local ns_prefix = '%#LspSagaWinbar'
local winbar_sep = '%#LspSagaWinbarSep#' .. config.separator .. '%*'
local method = 'textDocument/documentSymbol'

function symbar:get_file_name()
  local file_name = string.gsub(vim.fn.expand('%:t'), '%%', '')
  local ok, devicons = pcall(require, 'nvim-web-devicons')
  local f_icon = ''
  local f_hl = ''
  if ok then
    f_icon, f_hl = devicons.get_icon_by_filetype(vim.bo.filetype)
  end
  -- if filetype doesn't match devicon will set f_icon to nil so add a patch
  f_icon = f_icon == nil and '' or (f_icon .. ' ')
  f_hl = f_hl == nil and '' or f_hl
  return '%#' .. f_hl .. '#' .. f_icon .. '%*' .. ns_prefix .. 'File#' .. file_name .. '%*'
end

--@private
local do_symbol_request = function(callback)
  local current_buf = api.nvim_get_current_buf()
  local params = { textDocument = lsp.util.make_text_document_params() }
  lsp.buf_request_all(current_buf, method, params, callback)
end

--@private
local function binary_search(tbl, line)
  local left = 1
  local right = #tbl
  local mid = 0

  while true do
    mid = bit.rshift(left + right, 1)
    local range

    if tbl[mid].location ~= nil then
      range = tbl[mid].location.range
    elseif tbl[mid].range ~= nil then
      range = tbl[mid].range
    else
      return nil
    end

    if line >= range.start.line and line <= range['end'].line then
      return mid
    elseif line < range.start.line then
      right = mid - 1
      if left > right then
        return nil
      end
    else
      left = mid + 1
      if left > right then
        return nil
      end
    end
  end
end

local click_node = {}
local click_node_cnt = 0
-- @v:lua@ in the tabline only supports global functions, so this is
-- the only way to add click handlers without autoloaded vimscript functions
function _G.___lspsaga_winbar_click(id, clicks, button, modifiers)
  config.click_support(click_node[id], clicks, button, modifiers)
end

--@private
local function find_in_node(tbl, line, elements)
  local mid = binary_search(tbl, line)
  if mid == nil then
    return
  end

  local node = tbl[mid]
  local type, icon = '', ''

  type = kind[node.kind][1]
  icon = kind[node.kind][2]

  local click = ''
  if config.click_support ~= false then
    click_node_cnt = click_node_cnt + 1
    click_node[click_node_cnt] = node
    click = '%' .. tostring(click_node_cnt) .. '@v:lua.___lspsaga_winbar_click@'
  end

  local node_context = ns_prefix .. type .. '#' .. click .. icon .. node.name
  table.insert(elements, node_context)

  if node.children ~= nil and next(node.children) ~= nil then
    find_in_node(node.children, line, elements)
  end
end

--@private
local render_symbol_winbar = function()
  local current_win = api.nvim_get_current_win()
  local current_buf = api.nvim_get_current_buf()
  local current_line = api.nvim_win_get_cursor(current_win)[1]

  local winbar_val = config.show_file and not config.in_custom and symbar:get_file_name() or ''

  local symbols = {}
  if symbar.symbol_cache[current_buf] == nil then
    return
  end
  symbols = symbar.symbol_cache[current_buf][2]

  local winbar_elements = {}

  if config.click_support ~= false then
    click_node_cnt = 0
  end
  find_in_node(symbols, current_line - 1, winbar_elements)
  local str = table.concat(winbar_elements, winbar_sep)

  if config.show_file and next(winbar_elements) ~= nil then
    str = winbar_sep .. str
  end

  winbar_val = winbar_val .. str
  if not config.in_custom then
    vim.wo.winbar = winbar_val
  end
  return winbar_val
end

function symbar:get_buf_symbol(force, ...)
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
  for id, conf in pairs(clients) do
    if conf.server_capabilities.documentHighlightProvider then
      client_id = id
      break
    end
  end

  if client_id == nil then
    vim.notify('All servers of this buffer does not support ' .. method)
    return
  end

  local arg = { ... }
  local fn
  if next(arg) ~= nil then
    fn = unpack(arg)
  end

  local _callback = function(results)
    if libs.result_isempty(results) then
      return
    end

    self.symbol_cache[current_buf] = { true, results[client_id].result }

    if fn ~= nil then
      fn()
    end

    if config.in_custom then
      api.nvim_exec_autocmds('User', {
        pattern = 'LspsagaUpdateSymbol',
        modeline = false,
      })
    end
  end

  do_symbol_request(_callback)
end

--@private
local function removeElementByKey(tbl, key)
  local tmp = {}

  for i in pairs(tbl) do
    table.insert(tmp, i)
  end

  local newTbl = {}
  local i = 1
  while i <= #tmp do
    local val = tmp[i]
    if val == key then
      table.remove(tmp, i)
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
    self.symbol_cache = removeElementByKey(self.symbol_cache, current_buf)
  end
end

local function symbol_events()
  local current_buf = api.nvim_get_current_buf()
  local cache = symbar.symbol_cache

  local update_symbols = function(force)
    force = force or true
    if cache[current_buf] == nil or next(cache[current_buf]) == nil or force then
      symbar:get_buf_symbol(force, render_symbol_winbar)
    else
      render_symbol_winbar()
    end
  end

  update_symbols(true)

  api.nvim_create_autocmd('CursorMoved', {
    group = saga_group,
    buffer = current_buf,
    callback = update_symbols,
    desc = 'Lspsaga symbols',
  })

  api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, {
    group = saga_group,
    buffer = current_buf,
    callback = function()
      if config.in_custom then
        symbar:get_buf_symbol(true)
      else
        symbar:get_buf_symbol(true, render_symbol_winbar)
      end
    end,
    desc = 'Lspsaga update symbols',
  })

  api.nvim_create_autocmd('BufDelete', {
    group = saga_group,
    buffer = current_buf,
    callback = function()
      symbar:clear_cache()
    end,
    desc = 'Lspsaga clear document symbol cache',
  })
end

function symbar.config_symbol_autocmd()
  api.nvim_create_autocmd('LspAttach', {
    group = saga_group,
    callback = symbol_events,
    desc = 'Lspsaga get and show symbols',
  })
end

-- work with custom winbar
function symbar.get_symbol_node()
  return render_symbol_winbar()
end

return symbar
