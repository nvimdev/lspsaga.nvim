local api, fn = vim.api, vim.fn
local win = require('lspsaga.window')
local ui = require('lspsaga').config.ui
local M = {}

function M.left(height, width, bufnr)
  local curwin = api.nvim_get_current_win()
  local pos = api.nvim_win_get_cursor(curwin)
  local float_opt = {
    width = width,
    height = height,
    bufnr = bufnr,
    offset_x = -pos[2],
    focusable = true,
  }
  local topline = fn.line('w0')
  local room = fn.line('w$') - pos[1]
  if room <= height then
    fn.winrestview({ topline = topline + (height - room) })
  end
  return win
    :new_float(float_opt, true)
    :bufopt({
      ['buftype'] = 'nofile',
      ['bufhidden'] = 'wipe',
    })
    :winopt({
      ['winhl'] = 'NormalFloat:SagaNormal,Border:SagaBorder',
    })
    :wininfo()
end

local function border_map()
  return {
    ['single'] = { '┴', '┬' },
    ['rounded'] = { '┴', '┬' },
    ['double'] = { '╩', '╦' },
    ['solid'] = { '', '' },
    ['shadow'] = { '', '' },
  }
end

function M.right(left_winid)
  local win_conf = api.nvim_win_get_config(left_winid)
  local original = vim.deepcopy(win_conf)
  local map = border_map()
  original.border[5] = map[ui.border][1]
  original.border[3] = map[ui.border][2]
  api.nvim_win_set_config(left_winid, original)

  local WIDTH = api.nvim_win_get_width(win_conf.win)
  local col = win_conf.col[false] + win_conf.width
  local row = win_conf.row[false]
  win_conf.width = WIDTH - win_conf.width - 15
  win_conf.border[8] = ''
  win_conf.border[7] = ''
  win_conf.row = row
  win_conf.col = col + 2
  return win
    :new_float(win_conf, false, true)
    :winopt({
      ['winhl'] = 'NormalFloat:SagaNormal,Border:SagaBorder',
      ['signcolumn'] = 'no',
    })
    :wininfo()
end

return M
