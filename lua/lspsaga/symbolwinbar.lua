local lsp, api, fn = vim.lsp, vim.api, vim.fn
local config = require('lspsaga').config.symbol_in_winbar
local symbar = {}

local cache = {}
symbar.__index = symbar

function symbar.__newindex(t, k, v)
  rawset(t, k, v)
end

local function bar_prefix()
  return {
    prefix = '%#LspSagaWinbar',
    sep = '%#LspSagaWinbarSep#' .. config.separator .. '%*',
  }
end

local function get_kind_icon(type, index)
  local kind = require('lspsaga.highlight').get_kind()
  ---@diagnostic disable-next-line: need-check-nil
  return kind[type][index]
end

local function bar_file_name(buf)
  local libs = require('lspsaga.libs')
  local res = libs.get_path_info(buf, config.folder_level)
  if not res then
    return
  end
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

  local libs = require('lspsaga.libs')
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

function symbar.node_is_keyword(buf, node)
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

local function insert_elements(buf, node, elements)
  if config.hide_keyword and symbar.node_is_keyword(buf, node) then
    return
  end
  local type = get_kind_icon(node.kind, 1)
  local icon = get_kind_icon(node.kind, 2)
  local bar = bar_prefix()
  local node_context = bar.prefix .. type .. '#' .. icon .. node.name
  table.insert(elements, node_context)
end

--@private
local function find_in_node(buf, tbl, line, elements)
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
        insert_elements(buf, tbl[i], elements)
      end
    end
  end

  insert_elements(buf, tbl[mid], elements)

  if node.children ~= nil and next(node.children) ~= nil then
    find_in_node(buf, node.children, line, elements)
  end
end

--@private
local render_symbol_winbar = function(buf, symbols)
  buf = buf or api.nvim_get_current_buf()
  local all_wins = fn.win_findbuf(buf)
  local cur_win = api.nvim_get_current_win()
  if not vim.tbl_contains(all_wins, cur_win) then
    return
  end

  local ok, val = pcall(api.nvim_win_get_var, cur_win, 'disable_winbar')
  if ok and val then
    vim.wo[cur_win].winbar = ''
    return
  end
  local current_line = api.nvim_win_get_cursor(cur_win)[1]
  local winbar_str = config.show_file and bar_file_name(buf) or ''

  local winbar_elements = {}

  find_in_node(buf, symbols, current_line - 1, winbar_elements)

  local lens, over_idx = 0, 0
  local max_width = math.floor(api.nvim_win_get_width(cur_win) * 0.9)
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

  if config.enable and api.nvim_win_get_height(cur_win) - 1 > 1 then
    vim.wo[cur_win].winbar = winbar_str
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
    res.pending_request = cache[buf].pending_request
    return res
  end

  res.symbols = cache[buf].symbols
  res.pending_request = cache[buf].pending_request
  return res
end

function symbar:refresh_symbol_cache(buf, render_fn)
  self[buf].pending_request = true
  local function callback_fn(_, result, _)
    self[buf].pending_request = false
    if not result then
      return
    end

    if render_fn then
      render_fn(buf, result)
    end

    self[buf].symbols = result
  end
  do_symbol_request(buf, callback_fn)
end

function symbar:init_buf_symbols(buf, render_fn)
  if not self[buf] then
    self[buf] = {}
  end

  local res = get_buf_symbol(buf)
  if res.pending_request then
    return
  end

  if not res.symbols then
    self:refresh_symbol_cache(buf, render_fn)
  else
    render_fn(buf, res.symbols)
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

function symbar:register_events(buf)
  local augroup = api.nvim_create_augroup('LspsagaSymbol' .. tostring(buf), { clear = true })
  self[buf].group = augroup

  api.nvim_create_autocmd('CursorMoved', {
    group = augroup,
    buffer = buf,
    callback = function(opt)
      self:init_buf_symbols(opt.buf, render_symbol_winbar)
    end,
    desc = 'Lspsaga symbols',
  })

  api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, {
    group = augroup,
    buffer = buf,
    callback = function()
      if not config.enable then
        self:refresh_symbol_cache(buf, render_symbol_winbar)
      else
        self:refresh_symbol_cache(buf)
      end
    end,
    desc = 'Lspsaga update symbols',
  })

  api.nvim_buf_attach(buf, false, {
    on_detach = function()
      if self[buf] and self[buf].group then
        pcall(api.nvim_del_augroup_by_id, self[buf].group)
      end
      clean_buf_cache(buf)
    end,
  })
end

function symbar:symbol_autocmd()
  api.nvim_create_autocmd('LspAttach', {
    group = api.nvim_create_augroup('LspsagaSymbols', {}),
    callback = function(opt)
      local winid = api.nvim_get_current_win()
      local ok, val = pcall(api.nvim_win_get_var, winid, 'disable_winbar')
      if ok and val then
        return
      end
      if config.show_file then
        vim.wo[winid].winbar = bar_file_name(opt.buf)
      end

      self:init_buf_symbols(opt.buf, render_symbol_winbar)
      self:register_events(opt.buf)
    end,
    desc = 'Lspsaga get and show symbols',
  })
end

---Get buffer symbols
---@return  string | nil
function symbar:get_winbar()
  local buf = api.nvim_get_current_buf()
  if not self[buf] then
    self[buf] = {}
  end

  local res = get_buf_symbol(buf)
  if vim.tbl_isempty(res) or not res.symbols then
    self:refresh_symbol_cache(buf)
    return
  end

  if res.pending_request then
    return
  end

  self:register_events(buf)

  if res.symbols then
    return render_symbol_winbar(buf, res.symbols)
  end
end

return setmetatable(cache, symbar)
