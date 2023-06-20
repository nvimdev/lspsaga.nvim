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
    opts.height = math.min(lines_below, opts.height)
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

local function default()
  return {
    style = 'minimal',
    border = ui.border,
    noautocmd = false,
  }
end

local obj = {}
obj.__index = obj

function obj:bufopt(name, value)
  api.nvim_set_option_value(name, value, { buf = self.bufnr })
  return self
end

function obj:winopt(name, value)
  api.nvim_set_option_value(name, value, { scope = 'local', win = self.winid })
  return self
end

function obj:wininfo()
  return self.bufnr, self.winid
end

function obj:setlines(lines)
  api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
  return self
end

function win:new_float(float_opt, force)
  vim.validate({
    float_opt = { float_opt, 't', true },
  })

  local enter = float_opt.enter or false
  self.bufnr = float_opt.bufnr or api.nvim_create_buf(false, false)
  float_opt = not force and make_floating_popup_options(float_opt)
    or vim.tbl_extend('force', default(), float_opt)

  self.winid = api.nvim_open_win(self.bufnr, enter, float_opt)
  return setmetatable(win, obj)
end

function obj:restore_option()
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

return win
