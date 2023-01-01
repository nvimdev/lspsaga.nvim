local lsp, api = vim.lsp, vim.api
local config = require('lspsaga').config.symbol_in_winbar
local libs = require('lspsaga.libs')

local symbar = {}

local cache = {}
function cache.__index(_, k, _)
  return cache[k]
end

function cache.__newindex(_, k, v)
  cache[k] = v
end

local bar_prefix = function()
  return {
    prefix = '%#LspSagaWinbar',
    sep = '%#LspSagaWinbarSep#' .. config.separator .. '%*',
  }
end

local function get_kind_icon(type, index)
  local kind = require('lspsaga.lspkind')
  return kind[type][index]
end

local function get_path_info(buf)
  local fname = api.nvim_buf_get_name(buf)
  local tbl = vim.split(fname, libs.path_sep, { trimempty = true })
  if config.folder_level == 0 then
    return {}
  end
  if config.folder_level == 1 then
    return { tbl[#tbl] }
  end
  local index = config.folder_level > #tbl and #tbl or config.folder_level
  return { unpack(tbl, #tbl - index + 1, #tbl) }
end

local function get_file_name(buf)
  local res = get_path_info(buf)
  local data = libs.icon_from_devicon(vim.bo[buf].filetype)
  if #res == 0 then
    return ''
  end
  local str = ''
  local f_icon = data and data[1] and data[1] .. ' ' or ''
  local f_hl = data and data[2] and data[2] or ''
  local bar = bar_prefix()
  for i, v in pairs(res) do
    local tmp
    if i == #res then
      tmp = '%#' .. f_hl .. '#' .. f_icon .. '%*' .. bar.prefix .. 'File#' .. v .. '%*'
    else
      tmp = bar.prefix
        .. 'Folder#'
        .. get_kind_icon(302, 2)
        .. '%*'
        .. bar.prefix
        .. 'FolderLevel'
        .. i
        .. '#'
        .. v
        .. '%*'
        .. bar.sep
    end
    str = str .. tmp
  end
  return str
end

---@private
local do_symbol_request = function(buf, callback)
  buf = buf or api.nvim_get_current_buf()
  local params = { textDocument = lsp.util.make_text_document_params() }

  local client = libs.get_client_by_cap('documentSymbolProvider')
  if client == nil then
    return
  end
  cache[buf].pending_request = true
  client.request('textDocument/documentSymbol', params, callback, buf)
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

local function insert_elements(node, elements)
  local type = get_kind_icon(node.kind, 1)
  local icon = get_kind_icon(node.kind, 2)
  local bar = bar_prefix()
  local node_context = bar.prefix .. type .. '#' .. icon .. node.name
  table.insert(elements, node_context)
end

--@private
local function find_in_node(tbl, line, elements)
  local mid = binary_search(tbl, line)
  if mid == nil then
    return
  end

  local node = tbl[mid]

  local range = get_node_range(tbl[mid]) or {}

  if mid > 1 then
    for i = 1, mid - 1 do
      local prev_range = get_node_range(tbl[i]) or {}
      if -- not sure there should be 6 or other kind can be used in here
        tbl[i].kind == 6
        and range.start.line > prev_range.start.line
        and range['end'].line <= prev_range['end'].line
      then
        insert_elements(tbl[i], elements)
      end
    end
  end

  insert_elements(tbl[mid], elements)

  if node.children ~= nil and next(node.children) ~= nil then
    find_in_node(node.children, line, elements)
  end
end

--@private
local render_symbol_winbar = function(buf, symbols)
  buf = buf or api.nvim_get_current_buf()
  symbols = symbols or cache[buf].symbols
  local current_win = api.nvim_get_current_win()
  local current_line = api.nvim_win_get_cursor(current_win)[1]
  local winbar_str = config.show_file and get_file_name(buf) or ''

  local winbar_elements = {}

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

  local bar = bar_prefix()
  local str = table.concat(winbar_elements, bar.sep)

  if config.show_file and next(winbar_elements) ~= nil then
    str = bar.sep .. str
  end

  winbar_str = winbar_str .. str
  if not config.in_custom and api.nvim_win_get_height(current_win) - 1 > 1 then
    vim.wo[current_win].winbar = winbar_str
  end
  return winbar_str
end

--- Get buffer symbols from cache
---@private
local function get_buf_symbol(buf)
  buf = buf or api.nvim_get_current_buf()
  local res = {}

  if not cache[buf] then
    return res
  end

  if cache[buf].pending_request then
    res.symbols = {}
    res.pending_request = cache[buf].pending_request
  end

  local symbols = vim.tbl_get(cache, 'buf', 'symbols')
  if symbols and not cache[buf].pending_request then
    res.symbols = symbols
    res.pending_request = cache[buf].pending_request
  end
  return res
end

function symbar:refresh_symbol_cache(buf, render_fn, reg_buf_events)
  local _callback = function(_, result)
    self.pending_request = false
    if not result then
      return
    end

    if render_fn then
      render_fn(buf, result)
    end

    if not self[buf].group and reg_buf_events then
      reg_buf_events()
    end

    self[buf].symbols = result

    api.nvim_exec_autocmds('User', {
      pattern = 'LSUpdateSymbol',
      modeline = false,
    })
  end
  do_symbol_request(buf, _callback)
end

function symbar:init_buf_symbols(buf, render_fn, reg_buf_events)
  local res = get_buf_symbol(buf)
  if res.pending_request then
    return
  end

  if vim.tbl_isempty(res) then
    self:refresh_symbol_cache(buf, render_fn, reg_buf_events)
    return
  end
  render_fn(buf, res.symbols)
  if not self[buf].group then
    reg_buf_events()
  end
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

function symbar:symbol_events(buf)
  if not self[buf] then
    self[buf] = {}
  end

  local register_buf_events = function()
    local augroup = api.nvim_create_augroup('LspsagaSymbol' .. tostring(buf), { clear = true })
    self[buf].group = augroup

    api.nvim_create_autocmd('CursorMoved', {
      group = augroup,
      buffer = buf,
      callback = function(opt)
        render_symbol_winbar(opt.buf)
      end,
      desc = 'Lspsaga symbols',
    })

    api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, {
      group = augroup,
      buffer = buf,
      callback = function()
        if not config.in_custom then
          self:refresh_symbol_cache(buf, render_symbol_winbar)
        else
          self:refresh_symbol_cache(buf)
        end
      end,
      desc = 'Lspsaga update symbols',
    })

    api.nvim_buf_attach(buf, false, {
      on_detach = function(opt)
        pcall(api.nvim_del_augroup_by_id, self[buf].group)
        clean_buf_cache(opt.buf)
      end,
    })
  end

  self:init_buf_symbols(buf, render_symbol_winbar, register_buf_events)
end

function symbar.config_symbol_autocmd()
  api.nvim_create_autocmd('LspAttach', {
    group = api.nvim_create_augroup('LspsagaSymbols', {}),
    callback = function(opt)
      symbar:symbol_events(opt.buf)
    end,
    desc = 'Lspsaga get and show symbols',
  })
end

---Get buffer symbols
---@return  table with key symbols and pending_request
function symbar.get_buf_symbols(buf)
  buf = buf or api.nvim_get_current_buf()
  return get_buf_symbol(buf)
end

return setmetatable(symbar, cache)
