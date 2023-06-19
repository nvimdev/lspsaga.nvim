local vim, api = vim, vim.api
local ui = require('lspsaga').config.ui
local win = {}

local function make_floating_popup_options(opts)
  vim.validate({
    opts = { opts, 't', true },
  })
  opts = opts or {}
  vim.validate({
    ['opts.offset_x'] = { opts.offset_x, 'n', true },
    ['opts.offset_y'] = { opts.offset_y, 'n', true },
  })

  local anchor = ''
  local row, col

  local lines_above = opts.relative == 'mouse' and vim.fn.getmousepos().line - 1
    or vim.fn.winline() - 1
  local lines_below = vim.fn.winheight(0) - lines_above

  if lines_above < lines_below then
    anchor = anchor .. 'N'
    opts.height = math.min(lines_below, opts.sheight)
    row = 1
  else
    anchor = anchor .. 'S'
    opts.height = math.min(lines_above, opts.height)
    row = 0
  end

  local wincol = opts.relative == 'mouse' and vim.fn.getmousepos().column or vim.fn.wincol()

  if wincol + opts.width + (opts.offset_x or 0) <= vim.o.columns then
    anchor = anchor .. 'W'
    col = 0
  else
    anchor = anchor .. 'E'
    col = 1
  end

  local title = (opts.border and opts.title) and opts.title or nil
  local title_pos

  if title then
    title_pos = opts.title_pos or 'center'
  end

  return {
    anchor = anchor,
    bufpos = opts.relative == 'win' and opts.bufpos or nil,
    col = col + (opts.offset_x or 0),
    height = opts.height,
    focusable = opts.focusable,
    relative = opts.relative or 'cursor',
    row = row + (opts.offset_y or 0),
    style = 'minimal',
    width = opts.width,
    border = opts.border or ui.border,
    zindex = opts.zindex or 50,
    title = title,
    title_pos = title_pos,
    noautocmd = opts.noautocmd or false,
  }
end

function win:new_float(float_opt)
  vim.validate({
    float_opt = { float_opt, 't', true },
  })

  local enter = float_opt.enter or false
  local bufnr = float_opt.bufnr or api.nvim_create_buf(false, false)
  float_opt = make_floating_popup_options(float_opt)

  local winid = api.nvim_open_win(bufnr, enter, float_opt)
  return bufnr, winid
end

function win.get_max_float_width(percent)
  percent = percent or 0.6
  return math.floor(vim.o.columns * percent)
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
