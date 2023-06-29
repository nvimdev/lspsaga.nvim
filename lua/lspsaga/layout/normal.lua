local api = vim.api
local win = require('lspsaga.window')
local M = {}

function M.left(height, width, bufnr)
  M.width = width
  return win
    :new_normal('sp', bufnr)
    :bufopt({
      ['buftype'] = 'nofile',
    })
    :winopt({
      ['number'] = false,
      ['relativenumber'] = false,
      ['stc'] = '',
      ['cursorline'] = false,
      ['winfixwidth'] = true,
    })
    :setheight(height)
    :wininfo()
end

function M.right(left_winid)
  vim.cmd.vsplit('new')
  api.nvim_win_set_width(left_winid, M.width)
  local rbuf, rwinid = api.nvim_get_current_buf(), api.nvim_get_current_win()
  api.nvim_set_current_win(left_winid)
  return rbuf, rwinid
end

return M
