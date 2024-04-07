local api, fn = vim.api, vim.fn
local win = require('lspsaga.window')
local ui = require('lspsaga').config.ui
local is_ten = require('lspsaga.util').is_ten
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
  local row = is_ten and win_conf.row or win_conf.row[false]
  local wincol = fn.win_screenpos(win_conf.win)[2]
  local right_spaces = vim.o.columns
    - wincol
    - original.width
    - (is_ten and original.col or original.col[false])
  local left_spaces = wincol + (is_ten and original.col or original.col[false])
  local percent = opt.width or 0.7

  local right = math.ceil(right_spaces * percent)
  local left = math.ceil(left_spaces * percent)
  local in_right = false
  local WIDTH = api.nvim_win_get_width(original.win)
  local extra = WIDTH < original.width and WIDTH - original.width or 0
  if (vim.o.columns - WIDTH - wincol) > 0 and left > 45 then
    extra = 0
  end

  win_conf.width = nil
  if right > 45 then
    win_conf.col = (is_ten and win_conf.col or win_conf.col[false]) + original.width + 2
    win_conf.width = right
    in_right = true
  elseif left > 45 then
    win_conf.width = math.floor(left * percent)
    win_conf.col = (is_ten and original.col or original.col[false]) - win_conf.width + extra - 1
  -- back to right
  elseif right > 20 then
    win_conf.col = (is_ten and win_conf.col or win_conf.col[false]) + original.width + 2
    win_conf.width = right
    in_right = true
  end

  if original.border then
    local map
    if type(ui.border) == 'string' then
      map = border_map()[ui.border]
    elseif type(ui.border_sep) == 'table' then
      map = ui.border_sep
    else
      map = border_map()['solid']
    end
    if not in_right then
      original.border[1] = map[2]
      original.border[7] = map[1]
      win_conf.border[4] = ''
    else
      original.border[5] = map[1]
      original.border[3] = map[2]
      win_conf.border[8] = ''
      win_conf.border[7] = ''
    end
    api.nvim_win_set_config(left_winid, original)
  end

  win_conf.row = row
  win_conf.title = nil
  win_conf.title_pos = nil

  if opt.title then
    win_conf.title = #opt.title > win_conf.width
        and opt.title:sub(#opt.title - win_conf.width - 5, #opt.title)
      or opt.title
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
