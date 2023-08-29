local api = vim.api
local config = require('lspsaga').config.symbol_in_winbar
local ui = require('lspsaga').config.ui
local util = require('lspsaga.util')
local symbol = require('lspsaga.symbol')
local kind = require('lspsaga.lspkind').kind

local function bar_prefix()
  return {
    prefix = '%#Saga',
    sep = '%#SagaWinbarSep#' .. config.separator .. '%*',
  }
end

local function path_in_bar(buf)
  local ft = vim.bo[buf].filetype
  local icon, hl
  if ui.devicon then
    icon, hl = util.icon_from_devicon(ft)
  end

  local bar = bar_prefix()
  local items = {}
  local folder = kind[302][2] .. '%*'

  for item in util.path_itera(buf) do
    item = #items == 0
        and '%#' .. (hl or 'SagaFileIcon') .. '#' .. (icon and icon .. ' ' or '') .. '%*' .. bar.prefix .. 'FileName#' .. item .. '%*'
      or bar.prefix .. 'Folder#' .. folder .. bar.prefix .. 'FolderName#' .. item .. '%*'
    items[#items + 1] = item

    if #items > config.folder_level then
      break
    end
  end

  local barstr = ''
  for i = #items, 1, -1 do
    barstr = barstr .. items[i] .. (i > 1 and bar.sep or '')
  end
  return barstr
end

--@private
local function binary_search(tbl, line)
  local left = 1
  local right = #tbl
  local mid = 0

  while true do
    mid = bit.rshift(left + right, 1)
    if not tbl[mid] then
      return
    end

    local range = tbl[mid].range or tbl[mid].location.range
    if not range then
      return
    end

    if line >= range.start.line and line <= range['end'].line then
      return mid
    elseif line < range.start.line then
      right = mid - 1
    else
      left = mid + 1
    end
    if left > right then
      return
    end
  end
end

local function stl_escape(str)
  return str:gsub('%%', '')
end

local function insert_elements(buf, node, elements)
  if config.hide_keyword and symbol:node_is_keyword(buf, node) then
    return
  end
  local type = kind[node.kind][1]
  local icon = kind[node.kind][2]
  local bar = bar_prefix()
  if node.name:find('%%') then
    node.name = stl_escape(node.name)
  end

  if config.color_mode then
    local node_context = bar.prefix .. type .. '#' .. icon .. node.name
    elements[#elements + 1] = node_context
  else
    local node_context = bar.prefix
      .. type
      .. '#'
      .. icon
      .. bar.prefix
      .. 'Word'
      .. '#'
      .. node.name
    elements[#elements + 1] = node_context
  end
end

--@private
local function find_in_node(buf, tbl, line, elements)
  local mid = binary_search(tbl, line)
  if not mid then
    return
  end

  local node = tbl[mid]

  insert_elements(buf, tbl[mid], elements)

  if node.children ~= nil and next(node.children) ~= nil then
    find_in_node(buf, node.children, line, elements)
  end
end

--@private
local function render_symbol_winbar(buf, symbols)
  if api.nvim_get_current_buf() ~= buf then
    return
  end

  -- don't show in float window.
  local cur_win = api.nvim_get_current_win()
  local winconf = api.nvim_win_get_config(cur_win)
  if #winconf.relative > 0 then
    return
  end

  local current_line = api.nvim_win_get_cursor(cur_win)[1]
  local winbar_str = config.show_file and path_in_bar(buf) or ''

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
    if #winbar_str == 0 then
      winbar_str = bar_prefix().prefix .. ' #'
    end
    api.nvim_set_option_value('winbar', winbar_str, { scope = 'local', win = cur_win })
  end

  return winbar_str
end

local function file_bar(buf)
  local winid = api.nvim_get_current_win()
  local winconf = api.nvim_win_get_config(winid)
  if #winconf.relative ~= 0 then
    return
  end
  if config.show_file then
    api.nvim_set_option_value('winbar', path_in_bar(buf), { scope = 'local', win = winid })
  else
    api.nvim_set_option_value(
      'winbar',
      bar_prefix().prefix .. ' #',
      { scope = 'local', win = winid }
    )
  end
end

local function ignored(bufname)
  for _, pattern in ipairs(util.as_table(config.ignore_patterns)) do
    if bufname:find(pattern) then
      return true
    end
  end
  return false
end

local function init_winbar(buf)
  if vim.o.diff or config.ignore_patterns and ignored(api.nvim_buf_get_name(buf)) then
    return
  end
  file_bar(buf)
  api.nvim_create_autocmd('User', {
    pattern = 'SagaSymbolUpdate',
    callback = function(opt)
      local curbuf = api.nvim_get_current_buf()
      if
        vim.bo[opt.buf].buftype == 'nofile'
        or curbuf ~= opt.data.bufnr
        or #opt.data.symbols == 0
      then
        return
      end

      render_symbol_winbar(opt.buf, opt.data.symbols)
    end,
    desc = 'Lspsaga get and show symbols',
  })

  api.nvim_create_autocmd({ 'CursorMoved' }, {
    group = api.nvim_create_augroup('SagaWinbar' .. buf, { clear = true }),
    buffer = buf,
    callback = function(args)
      local res = not util.nvim_ten() and symbol:get_buf_symbols(args.buf)
        or require('lspsaga.symbol.head'):get_buf_symbols(args.buf)
      if res and res.symbols then
        render_symbol_winbar(args.buf, res.symbols)
      end
    end,
    desc = 'Lspsaga symbols render and request',
  })
end

local function get_bar()
  local curbuf = api.nvim_get_current_buf()
  local res = not util.nvim_ten() and symbol:get_buf_symbols(curbuf)
    or require('lspsaga.symbol.head'):get_buf_symbols(curbuf)
  if res and res.symbols then
    return render_symbol_winbar(curbuf, res.symbols)
  end
end

return {
  init_winbar = init_winbar,
  get_bar = get_bar,
}
