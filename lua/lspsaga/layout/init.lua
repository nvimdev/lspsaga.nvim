local api = vim.api
local float = require('lspsaga.layout.float')
local normal = require('lspsaga.layout.normal')
local M = {}

function M:arg_layout(args)
  local layout
  for _, item in ipairs(args) do
    if item:find('normal') then
      layout = 'normal'
    elseif item:find('float') then
      layout = 'float'
    elseif item:find('drowpdown') then
      layout = 'dropdown'
    end
  end
  return layout
end

function M:new(layout)
  self.layout = layout
  return self
end

local LEFT = 1
local RIGHT = 2

function M:left(height, width, bufnr, title, sp_global)
  local fn = self.layout == 'float' and float.left or normal.left
  self.left_bufnr, self.left_winid = fn(height, width, bufnr, title, sp_global)
  self.current = LEFT
  return self
end

function M:bufopt(name, value)
  local bufnr = self.current == LEFT and self.left_bufnr or self.right_bufnr
  if type(name) == 'table' then
    for key, val in pairs(name) do
      api.nvim_set_option_value(key, val, { buf = bufnr })
    end
  else
    api.nvim_set_option_value(name, value, { buf = bufnr })
  end
  return self
end

function M:winopt(name, value)
  local winid = self.current == LEFT and self.left_winid or self.right_winid
  if type(name) == 'table' then
    for key, val in pairs(name) do
      api.nvim_set_option_value(key, val, { win = winid, scope = 'local' })
    end
  else
    api.nvim_set_option_value(name, value, { win = winid, scope = 'local' })
  end
  return self
end

function M:setlines(lines)
  vim.validate({
    lines = { lines, 't' },
  })
  local bufnr = self.current == LEFT and self.left_bufnr or self.right_bufnr
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return self
end

function M:right(opt)
  local fn = self.layout == 'float' and float.right or normal.right
  self.right_bufnr, self.right_winid = fn(self.left_winid, opt)
  if not self.right_winid then
    print('[LSPSAGA] no enough room to show floating window')
  end
  self.current = RIGHT
  return self
end

function M:dropdown(height)
  --up
  self.right_winid = api.nvim_get_current_win()
  --down
  self.left_bufnr, self.left_winid = require('lspsaga.layout.normal').left(height, nil, _, true)
  return self
end

function M:done(fn)
  vim.validate({
    fn = { fn, { 'f' }, true },
  })
  if fn then
    fn(self.left_bufnr, self.left_winid, self.right_bufnr, self.right_winid)
  end
  return self.left_bufnr, self.left_winid, self.right_bufnr, self.right_winid
end

function M:close()
  for i, id in ipairs({ self.left_winid, self.right_winid }) do
    if i == 1 and api.nvim_win_is_valid(id) then
      api.nvim_win_close(id, true)
    elseif i == 2 and self.layout ~= 'dropdown' and api.nvim_win_is_valid(id) then
      api.nvim_win_close(id, true)
    end
  end
  self.left_winid = nil
  self.right_winid = nil
end

return M
