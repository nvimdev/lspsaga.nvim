local api, fn = vim.api, vim.fn
local win = require('lspsaga.window')
local M = {}

function M:new(layout)
  self.layout = layout
  return self
end

function M:left(height, width, bufnr)
  if self.layout == 'float' then
    local curwin = api.nvim_get_current_win()
    local pos = api.nvim_win_get_cursor(curwin)
    local float_opt = {
      width = width,
      height = height,
      bufnr = bufnr,
      offset_x = -pos[2],
    }
    local topline = fn.line('w0')
    if topline - pos[1] < height then
      fn.winrestview({ topline = topline + height - pos[1] })
    end
    self.left_bufnr, self.left_winid = win:new_float(float_opt, true):wininfo()
  else
    self.left_bufnr, self.left_winid =
      win:new_normal('sp', bufnr):setheight(height):setwidth(width):wininfo()
  end
  return self.left_bufnr, self.left_winid
end

function M:right() end

return M
