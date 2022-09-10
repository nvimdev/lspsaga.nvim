local vim, api = vim, vim.api
local M = {}
local config = require('lspsaga').config_values

local function get_border_style(style, highlight)
  highlight = highlight or 'FloatBorder'
  local border_style = {
    ['none'] = 'none',
    ['single'] = 'single',
    ['double'] = 'double',
    ['rounded'] = 'rounded',
    ['bold'] = {
      { '┏', highlight },
      { '─', highlight },
      { '┓', highlight },
      { '│', highlight },
      { '┛', highlight },
      { '─', highlight },
      { '┗', highlight },
      { '│', highlight },
    },
    ['plus'] = {
      { '+', highlight },
      { '─', highlight },
      { '+', highlight },
      { '│', highlight },
      { '+', highlight },
      { '─', highlight },
      { '+', highlight },
      { '│', highlight },
    },
  }

  return border_style[style]
end

local function make_floating_popup_options(width, height, opts)
  vim.validate({
    opts = { opts, 't', true },
  })
  opts = opts or {}
  vim.validate({
    ['opts.offset_x'] = { opts.offset_x, 'n', true },
    ['opts.offset_y'] = { opts.offset_y, 'n', true },
  })
  local new_option = {}

  new_option.style = 'minimal'
  new_option.width = width
  new_option.height = height
  new_option.focusable = true
  if opts.focusable then
    new_option.focusable = opts.focusable
  end

  if opts.noautocmd then
    new_option.noautocmd = opts.noautocmd
  end

  if opts.relative ~= nil then
    new_option.relative = opts.relative
  else
    new_option.relative = 'cursor'
  end

  if opts.anchor ~= nil then
    new_option.anchor = opts.anchor
  end

  if opts.row == nil and opts.col == nil then
    local lines_above = vim.fn.winline() - 1
    local lines_below = vim.fn.winheight(0) - lines_above
    new_option.anchor = ''

    local pum_pos = vim.fn.pum_getpos()
    local pum_vis = not vim.tbl_isempty(pum_pos) -- pumvisible() can be true and pum_pos() returns {}
    if pum_vis and vim.fn.line('.') >= pum_pos.row or not pum_vis and lines_above < lines_below then
      new_option.anchor = 'N'
      new_option.row = 1
    else
      new_option.anchor = 'S'
      new_option.row = 0
    end

    if vim.fn.wincol() + width <= api.nvim_get_option('columns') then
      new_option.anchor = new_option.anchor .. 'W'
      new_option.col = 0
      if opts.move_col then
        new_option.col = new_option.col + opts.move_col
      end
    else
      new_option.anchor = new_option.anchor .. 'E'
      new_option.col = 1
      if opts.move_col then
        new_option.col = new_option.col - opts.move_col + 1
      end
    end
  else
    new_option.row = opts.row
    new_option.col = opts.col
  end

  return new_option
end

local function generate_win_opts(contents, opts)
  opts = opts or {}
  local win_width, win_height
  -- _make_floating_popup_size doesn't allow the window size to be larger than
  -- the current window. For the finder preview window, this means it won't let the
  -- preview window be wider than the finder window. To work around this, the
  -- no_size_override option can be set to indicate that the size shouldn't be changed
  -- from what was given.
  if opts.no_size_override and opts.width and opts.height then
    win_width, win_height = opts.width, opts.height
  else
    win_width, win_height = vim.lsp.util._make_floating_popup_size(contents, opts)
  end

  opts = make_floating_popup_options(win_width, win_height, opts)
  return opts
end

local function get_shadow_config()
  local opts = {
    relative = 'editor',
    style = 'minimal',
    width = vim.o.columns,
    height = vim.o.lines,
    row = 0,
    col = 0,
  }
  return opts
end

local function open_shadow_win()
  local opts = get_shadow_config()
  local shadow_winhl = 'Normal:SagaShadow,NormalNC:SagaShadow,EndOfBuffer:SagaShadow'
  local shadow_bufnr = api.nvim_create_buf(false, true)
  local shadow_winid = api.nvim_open_win(shadow_bufnr, true, opts)
  api.nvim_win_set_option(shadow_winid, 'winhl', shadow_winhl)
  api.nvim_win_set_option(shadow_winid, 'winblend', 70)
  return shadow_bufnr, shadow_winid
end

-- content_opts a table with filed
-- contents table type
-- filetype string type
-- enter boolean into window or not
-- highlight border highlight string type
function M.create_win_with_border(content_opts, opts)
  vim.validate({
    content_opts = { content_opts, 't' },
    contents = { content_opts.content, 't', true },
    opts = { opts, 't', true },
  })

  local contents, filetype = content_opts.contents, content_opts.filetype
  local enter = content_opts.enter or false
  local highlight = content_opts.highlight or 'LspFloatWinBorder'
  opts = opts or {}
  opts = generate_win_opts(contents, opts)
  opts.border = content_opts.border or get_border_style(config.border_style, highlight)

  -- create contents buffer
  local bufnr = content_opts.bufnr or api.nvim_create_buf(false, true)
  -- buffer settings for contents buffer
  -- Clean up input: trim empty lines from the end, pad
  local content = vim.lsp.util._trim(contents)

  if filetype then
    api.nvim_buf_set_option(bufnr, 'filetype', filetype)
  end

  content = vim.tbl_flatten(vim.tbl_map(function(line)
    if string.find(line, '\n') then
      return vim.split(line, '\n')
    end
    return line
  end, content))

  if not vim.tbl_isempty(content) then
    api.nvim_buf_set_lines(bufnr, 0, -1, true, content)
  end

  if api.nvim_buf_is_valid(bufnr) then
    api.nvim_buf_set_option(bufnr, 'modifiable', false)
    api.nvim_buf_set_option(bufnr, 'bufhidden', 'wipe')
  end

  local winid = api.nvim_open_win(bufnr, enter, opts)
  api.nvim_win_set_option(winid, 'winhl', 'Normal:LspFloatWinNormal,FloatBorder:' .. highlight)
  api.nvim_win_set_option(winid, 'winblend', content_opts.winblend or config.saga_winblend)

  -- disable winbar in some saga's floatwindow
  if config.symbol_in_winbar.enable or config.symbol_in_winbar.in_custom then
    api.nvim_win_set_option(winid, 'winbar', '')
  end

  return bufnr, winid
end

function M.open_shadow_float_win(content_opts, opts)
  local shadow_bufnr, shadow_winid = open_shadow_win()
  local contents_bufnr, contents_winid = M.create_win_with_border(content_opts, opts)
  return contents_bufnr, contents_winid, shadow_bufnr, shadow_winid
end

function M.get_max_float_width()
  -- current window width
  local WIN_WIDTH = vim.fn.winwidth(0)
  local max_width = math.floor(WIN_WIDTH * 0.7)
  return max_width
end

function M.get_max_content_length(contents)
  vim.validate({
    contents = { contents, 't' },
  })

  local max = 0

  if next(contents) == nil then
    return max
  end
  if #contents == 1 then
    return #contents[1]
  end

  for _, v in pairs(contents) do
    if #v > max then
      max = #v
    end
  end
  return max
end

function M.nvim_close_valid_window(winid)
  if winid == nil then
    return
  end

  local close_win = function(win_id)
    if not winid or win_id == 0 then
      return
    end
    if vim.api.nvim_win_is_valid(win_id) then
      api.nvim_win_close(win_id, true)
    end
  end

  local _switch = {
    ['table'] = function()
      for _, id in ipairs(winid) do
        close_win(id)
      end
    end,
    ['number'] = function()
      close_win(winid)
    end,
  }

  local _switch_metatable = {
    __index = function(_, t)
      error(string.format('Wrong type %s of winid', t))
    end,
  }

  setmetatable(_switch, _switch_metatable)

  _switch[type(winid)]()
end

function M.nvim_win_try_close()
  local has_var, line_diag_winids = pcall(api.nvim_win_get_var, 0, 'show_line_diag_winids')
  if has_var and line_diag_winids ~= nil then
    M.nvim_close_valid_window(line_diag_winids)
  end
end

return M
