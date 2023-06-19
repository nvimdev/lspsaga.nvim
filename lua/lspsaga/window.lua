local vim, api, lsp = vim, vim.api, vim.lsp
local M = {}

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

  new_option.style = opts.style or 'minimal'
  new_option.width = width
  new_option.height = height

  if opts.focusable ~= nil then
    new_option.focusable = opts.focusable
  end

  new_option.noautocmd = opts.noautocmd or true

  new_option.relative = opts.relative and opts.relative or 'cursor'
  new_option.anchor = opts.anchor or nil
  if new_option.relative == 'win' then
    new_option.bufpos = opts.bufpos or nil
    new_option.win = opts.win or nil
  end

  if opts.title then
    new_option.title = opts.title
    new_option.title_pos = opts.title_pos or 'center'
  end

  new_option.zindex = opts.zindex or nil

  if not opts.row and not opts.col and not opts.bufpos then
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

    if vim.fn.wincol() + width <= vim.o.columns then
      new_option.anchor = new_option.anchor .. 'W'
      new_option.col = 0
    else
      new_option.anchor = new_option.anchor .. 'E'
      new_option.col = 1
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
  if opts.no_size_override and opts.width and opts.height then
    win_width, win_height = opts.width, opts.height
  else
    win_width, win_height = lsp.util._make_floating_popup_size(contents, opts)
  end

  opts = make_floating_popup_options(win_width, win_height, opts)
  return opts
end

function M.create_win_with_border(content_opts, float_opt)
  local config = require('lspsaga').config
  vim.validate({
    content_opts = { content_opts, 't' },
    contents = { content_opts.content, 't', true },
    float_opt = { float_opt, 't', true },
  })

  local contents, filetype = content_opts.contents, content_opts.filetype
  local enter = content_opts.enter or false
  float_opt = float_opt or {}
  float_opt = generate_win_opts(contents, float_opt)

  local highlight = content_opts.highlight or {}

  local normal = highlight.normal or 'LspNormal'
  local border_hl = highlight.border or 'LspBorder'

  if content_opts.noborder then
    float_opt.border = 'none'
  else
    float_opt.border = content_opts.border_side
        and M.combine_border(config.ui.border, content_opts.border_side, border_hl)
      or config.ui.border
  end

  -- create contents buffer
  local bufnr = content_opts.bufnr or api.nvim_create_buf(false, false)
  -- buffer settings for contents buffer
  -- Clean up input: trim empty lines from the end, pad
  ---@diagnostic disable-next-line: missing-parameter
  local content = lsp.util._trim(contents)

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

  if not content_opts.bufnr then
    api.nvim_set_option_value('modifiable', false, { buf = bufnr })
    api.nvim_set_option_value('bufhidden', content_opts.bufhidden or 'wipe', { buf = bufnr })
    api.nvim_set_option_value('buftype', content_opts.buftype or 'nofile', { buf = bufnr })
  end

  local winid = api.nvim_open_win(bufnr, enter, float_opt)
  api.nvim_set_option_value(
    'winblend',
    content_opts.winblend or config.ui.winblend,
    { scope = 'local', win = winid }
  )
  api.nvim_set_option_value('wrap', content_opts.wrap or false, { scope = 'local', win = winid })

  api.nvim_set_option_value(
    'winhl',
    'Normal:' .. normal .. ',FloatBorder:' .. border_hl,
    { scope = 'local', win = winid }
  )

  api.nvim_set_option_value('winbar', '', { scope = 'local', win = winid })
  return bufnr, winid
end

function M.get_max_float_width(percent)
  percent = percent or 0.6
  return math.floor(vim.o.columns * percent)
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

function M.win_height_increase(content, percent)
  local increase = 0
  local max_width = M.get_max_float_width(percent)
  local max_len = M.get_max_content_length(content)
  local new = {}
  for _, v in pairs(content) do
    if v:find('\n.') then
      vim.list_extend(new, vim.split(v, '\n'))
    else
      new[#new + 1] = v
    end
  end
  if max_len > max_width then
    vim.tbl_map(function(s)
      local cols = vim.fn.strdisplaywidth(s)
      if cols > max_width then
        increase = increase + math.floor(cols / max_width)
      end
    end, new)
  end
  return increase
end

function M.restore_option()
  local minimal_opts = {
    ['number'] = vim.opt.number,
    ['relativenumber'] = vim.opt.relativenumber,
    ['cursorline'] = vim.opt.cursorline,
    ['cursorcolumn'] = vim.opt.cursorcolumn,
    ['foldcolumn'] = vim.opt.foldcolumn,
    ['spell'] = vim.opt.spell,
    ['list'] = vim.opt.list,
    ['signcolumn'] = vim.opt.signcolumn,
    ['colorcolumn'] = vim.opt.colorcolumn,
    ['fillchars'] = vim.opt.fillchars,
    ['statuscolumn'] = vim.opt.statuscolumn,
  }

  function minimal_opts.restore()
    for opt, val in pairs(minimal_opts) do
      if type(val) ~= 'function' then
        vim.opt[opt] = val
      end
    end
  end

  return minimal_opts
end

return M
