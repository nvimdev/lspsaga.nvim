local lsp, api, fn = vim.lsp, vim.api, vim.fn
local config = require('lspsaga').config_values.symbol_in_winbar
local libs = require('lspsaga.libs')
local symbar = {
  symbol_cache = {},
}
local kind = require('lspsaga.lspkind')
local ns_prefix = '%#LspSagaWinbar'
local winbar_sep = '%#LspSagaWinbarSep#' .. config.separator .. '%*'
local method = 'textDocument/documentSymbol'
local cap = 'documentSymbolProvider'

function symbar:get_file_name(file_formatter)
  local file_name = string.gsub(vim.fn.expand(file_formatter or '%:t'), '%%', '')
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

---@private
local do_symbol_request = function(callback)
  local current_buf = api.nvim_get_current_buf()
  local params = { textDocument = lsp.util.make_text_document_params() }

  local client = libs.get_client_by_cap(cap)
  if client == nil then
    return
  end
  symbar.pending_request = true
  client.request(method, params, callback, current_buf)
end

local function get_node_range(node)
  if node.localtion then
    return node.localtion.range
  end

  if node.range then
    return node.range
  end
  return nil
end

--@private
local function binary_search(tbl, line)
  local left = 1
  local right = #tbl
  local mid = 0

  while true do
    mid = bit.rshift(left + right, 1)

    if mid == 0 then
      return nil
    end

    local range = get_node_range(tbl[mid])
    if not range then
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

local function insert_elements(node, click, elements)
  local type = kind[node.kind][1]
  local icon = kind[node.kind][2]
  local node_context = ns_prefix .. type .. '#' .. click .. icon .. node.name
  table.insert(elements, node_context)
end

--@private
local function find_in_node(tbl, line, elements)
  local mid = binary_search(tbl, line)
  if mid == nil then
    return
  end

  local node = tbl[mid]

  local click = ''
  if config.click_support then
    click_node_cnt = click_node_cnt + 1
    click_node[click_node_cnt] = node
    if type(config.click_support) == 'function' then
      click = '%' .. tostring(click_node_cnt) .. '@v:lua.___lspsaga_winbar_click@'
    else
      vim.notify('[LspSaga] symbol_in_winbar.click_support is not a function', vim.log.levels.WARN)
    end
  end

  local range = get_node_range(tbl[mid]) or {}

  if mid > 1 then
    for i = 1, mid - 1 do
      local prev_range = get_node_range(tbl[i]) or {}
      if -- not sure there should be 6 or other kind can be used in here
        tbl[i].kind == 6
        and range.start.line > prev_range.start.line
        and range['end'].line <= prev_range['end'].line
      then
        insert_elements(tbl[i], click, elements)
      end
    end
  end

  insert_elements(tbl[mid], click, elements)

  if node.children ~= nil and next(node.children) ~= nil then
    find_in_node(node.children, line, elements)
  end
end

--@private
local render_symbol_winbar = function()
  local current_win = api.nvim_get_current_win()
  local current_buf = api.nvim_get_current_buf()
  local current_line = api.nvim_win_get_cursor(current_win)[1]

  local winbar_val = config.show_file
      and not config.in_custom
      and symbar:get_file_name(config.file_formatter)
    or ''

  if not symbar.symbol_cache[current_buf] and next(symbar.symbol_cache) == nil then
    return
  end
  local symbols = symbar.symbol_cache[current_buf]

  if not symbols then
    return
  end

  local winbar_elements = {}

  if config.click_support ~= false then
    click_node_cnt = 0
  end
  find_in_node(symbols, current_line - 1, winbar_elements)

  local lens, over_idx = 0, 0
  local max_width = math.floor(api.nvim_win_get_width(current_win) * 0.9)
  for i, item in pairs(winbar_elements) do
    local s = vim.split(item, '#')
    lens = lens + api.nvim_strwidth(s[3]) + api.nvim_strwidth(config.separator)
    if lens > max_width then
      over_idx = i
      lens = 0
    end
  end

  if over_idx > 0 then
    winbar_elements = { unpack(winbar_elements, over_idx) }
    table.insert(winbar_elements, 1, '...')
  end

  local str = table.concat(winbar_elements, winbar_sep)

  if config.show_file and next(winbar_elements) ~= nil then
    str = winbar_sep .. str
  end

  winbar_val = winbar_val .. str
  if not config.in_custom and api.nvim_win_get_height(current_win) - 1 > 1 then
    vim.wo[current_win].winbar = winbar_val
  end
  return winbar_val
end

function symbar:get_buf_symbol(...)
  if self.pending_request then
    return
  end
  local current_buf = api.nvim_get_current_buf()

  local arg = { ... }
  local fn
  if next(arg) ~= nil then
    fn = unpack(arg)
  end

  local _callback = function(_, result)
    self.pending_request = false
    if not result then
      return
    end

    self.symbol_cache[current_buf] = result

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

function symbar:clear_cache()
  local current_buf = api.nvim_get_current_buf()
  if self.symbol_cache[current_buf] then
    self.symbol_cache = libs.removeElementByKey(self.symbol_cache, current_buf)
  end
end

local symbol_buf_ids = {}

function symbar:symbol_events()
  if not libs.check_lsp_active(false) then
    return
  end

  local current_buf = api.nvim_get_current_buf()
  self.pending_request = false

  self:get_buf_symbol(render_symbol_winbar)

  local symbol_group =
    api.nvim_create_augroup('LspsagaSymbol' .. tostring(current_buf), { clear = true })
  symbol_buf_ids[current_buf] = symbol_group

  api.nvim_create_autocmd('CursorMoved', {
    group = symbol_group,
    buffer = current_buf,
    callback = function()
      render_symbol_winbar()
    end,
    desc = 'Lspsaga symbols',
  })

  api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, {
    group = symbol_group,
    buffer = current_buf,
    callback = function()
      if config.in_custom then
        self:get_buf_symbol()
        return
      end
      self:get_buf_symbol(render_symbol_winbar)
    end,
    desc = 'Lspsaga update symbols',
  })

  api.nvim_buf_attach(current_buf, false, {
    on_detach = function()
      if symbol_buf_ids[current_buf] then
        self:clear_cache()
        pcall(api.nvim_del_augroup_by_id, symbol_buf_ids[current_buf])
        rawset(symbol_buf_ids, current_buf, nil)
      end
    end,
  })
end

function symbar.config_symbol_autocmd()
  api.nvim_create_autocmd('LspAttach', {
    group = api.nvim_create_augroup('LspsagaSymbols', {}),
    callback = function()
      symbar:symbol_events()
    end,
    desc = 'Lspsaga get and show symbols',
  })
end

-- work with custom winbar
function symbar.get_symbol_node()
  return render_symbol_winbar()
end

return symbar
