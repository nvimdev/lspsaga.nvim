local api, fn = vim.api, vim.fn
local win = require('lspsaga.window')
local ui = require('lspsaga').config.ui
local M = {}

function M.left(height, width, bufnr, title)
  local curwin = api.nvim_get_current_win()
  local pos = api.nvim_win_get_cursor(curwin)
  local float_opt = {
    width = width,
    height = height,
    bufnr = bufnr,
    offset_x = -pos[2],
    focusable = true,
    title = title or nil,
  }
  if title then
    float_opt.title_pos = 'center'
  end

  local topline = fn.line('w0')
  local room = api.nvim_win_get_height(0) - fn.winline()
  if room <= height + 4 then
    fn.winrestview({ topline = topline + (height + 4 - room) })
  end

  local spaces = vim.o.columns - api.nvim_win_get_width(curwin)
  if spaces > 0 then
    float_opt.width = float_opt.width + math.floor(spaces * 0.4)
  end

  return win
    :new_float(float_opt, true)
    :bufopt({
      ['buftype'] = 'nofile',
      ['bufhidden'] = 'wipe',
    })
    :winopt({
      ['winhl'] = 'NormalFloat:SagaNormal,FloatBorder:SagaBorder',
    })
    :wininfo()
end

local function border_map()
  return {
    ['single'] = { '┴', '┬' },
    ['rounded'] = { '┴', '┬' },
    ['double'] = { '╩', '╦' },
    ['solid'] = { ' ', ' ' },
    ['shadow'] = { ' ', ' ' },
  }
end

function M.right(left_winid, opt)
  opt = opt or {}
  local win_conf = api.nvim_win_get_config(left_winid)
  local original = vim.deepcopy(win_conf)
  local row = win_conf.row[false]
  local wincol = fn.win_screenpos(win_conf.win)[2]
  local spaces = vim.o.columns - wincol - api.nvim_win_get_width(win_conf.win)
  local percent = opt.width or 0.7

  if spaces <= 0 then
    win_conf.col = win_conf.col[false] - win_conf.width - 1
    win_conf.width = math.floor((vim.o.columns - wincol) * percent)
  else
    win_conf.col = win_conf.col[false] + win_conf.width + 2
    win_conf.width = math.floor(spaces * percent)
  end

  if original.border then
    local map = border_map()
    if spaces <= 0 then
      original.border[1] = map[ui.border][2]
      original.border[7] = map[ui.border][1]
      win_conf.border[4] = ''
    else
      original.border[5] = map[ui.border][1]
      original.border[3] = map[ui.border][2]
      win_conf.border[8] = ''
      win_conf.border[7] = ''
    end
    api.nvim_win_set_config(left_winid, original)
  end

  win_conf.row = row
  win_conf.title = nil
  win_conf.title_pos = nil

  if opt.title then
    win_conf.title = opt.title
    win_conf.title_pos = 'center'
  end
  return win
    :new_float(win_conf, false, true)
    :winopt({
      ['winhl'] = 'NormalFloat:SagaNormal,FloatBorder:SagaBorder',
      ['signcolumn'] = 'no',
    })
    :wininfo()
end

return M
