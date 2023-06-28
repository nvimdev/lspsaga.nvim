local win = require('lspsaga.window')
local float = require('lspsaga.layout.float')
local normal = require('lspsaga.layout.normal')
local M = {}

function M:new(layout)
  self.layout = layout
  return self
end

function M:left(height, width, bufnr)
  local fn = self.layout == 'float' and float.left or normal.left
  self.left_bufnr, self.left_winid = fn(height, width, bufnr)
  return self
end

function M:right()
  local fn = self.layout == 'float' and float.right or normal.right
  self.right_bufnr, self.right_winid = fn(self.left_winid)
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
