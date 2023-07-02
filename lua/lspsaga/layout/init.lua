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

function M:left(height, width, bufnr)
  local fn = self.layout == 'float' and float.left or normal.left
  self.left_bufnr, self.left_winid = fn(height, width, bufnr)
  self.current = LEFT
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

function M:right()
  local fn = self.layout == 'float' and float.right or normal.right
  self.right_bufnr, self.right_winid = fn(self.left_winid)
  self.current = RIGHT
  return self
end

function M:done(fn)
  vim.validate({
    fn = { fn, { 'f', 'nil' } },
  })
  if fn then
    fn(self.left_bufnr, self.left_winid, self.right_bufnr, self.right_winid)
  end
  return self.left_bufnr, self.left_winid, self.right_bufnr, self.right_winid
end

return M
