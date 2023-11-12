local vim, api = vim, vim.api
local validate = vim.validate
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

  local border = opts.border or ui.border

  local title = (border and border ~= 'none' and opts.title) and opts.title or nil
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
    border = border,
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
  if type(name) == 'table' then
    for key, val in pairs(name) do
      api.nvim_set_option_value(key, val, { buf = self.bufnr })
    end
  else
    api.nvim_set_option_value(name, value, { buf = self.bufnr })
  end
  return self
end

function obj:winopt(name, value)
  if type(name) == 'table' then
    for key, val in pairs(name) do
      api.nvim_set_option_value(key, val, { scope = 'local', win = self.winid })
    end
  else
    api.nvim_set_option_value(name, value, { scope = 'local', win = self.winid })
  end
  return self
end

function obj:winhl(normal, border)
  api.nvim_set_option_value('winhl', 'NormalFloat:' .. normal .. ',FloatBorder:' .. border, {
    scope = 'local',
    win = self.winid,
  })
  return self
end

function obj:wininfo()
  return self.bufnr, self.winid
end

function obj:setlines(lines, row, erow)
  row = row or 0
  erow = erow or -1
  lines = vim.tbl_map(function(line)
    return line:gsub('[\n\r]+', '')
  end, lines)
  api.nvim_buf_set_lines(self.bufnr, row, erow, false, lines)
  return self
end

--float window only
function obj:winsetconf(config)
  validate({
    config = { config, 't' },
  })
  api.nvim_win_set_config(self.winid, config)
  return self
end

--normal window only
function obj:setwidth(width)
  api.nvim_win_set_width(self.winid, width)
  return self
end

--normal window only
function obj:setheight(height)
  api.nvim_win_set_height(self.winid, height)
  return self
end

function win:new_float(float_opt, enter, force)
  vim.validate({
    float_opt = { float_opt, 't', true },
  })
  enter = enter or false

  self.bufnr = float_opt.bufnr or api.nvim_create_buf(false, false)
  float_opt.bufnr = nil
  float_opt = not force and make_floating_popup_options(float_opt)
    or vim.tbl_extend('force', default(), float_opt)

  self.winid = api.nvim_open_win(self.bufnr, enter, float_opt)
  return setmetatable(win, obj)
end

function win:new_normal(direct, bufnr, sp_global)
  local user_val = vim.opt.splitbelow
  sp_global = sp_global or false
  vim.opt.splitbelow = true
  local c = ('%s new'):format(direct)
  if sp_global then
    c = 'botright ' .. c
  end
  vim.cmd(c)
  vim.opt.splitbelow = user_val
  self.bufnr = bufnr or api.nvim_create_buf(false, false)
  self.winid = api.nvim_get_current_win()
  api.nvim_win_set_buf(self.winid, self.bufnr)
  return setmetatable(win, obj)
end

function win:from_exist(bufnr, winid)
  self.bufnr = bufnr
  self.winid = winid
  return setmetatable(win, obj)
end

function win:minimal_restore()
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
    ['winhl'] = vim.opt.winhl,
  }

  local restore = function()
    for opt, val in pairs(minimal_opts) do
      if type(val) ~= 'function' then
        vim.opt[opt] = val
      end
    end
  end
  return restore
end

return win
