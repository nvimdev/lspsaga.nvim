local api = vim.api
local action = {}

-- direction must 1 or -1
function action.smart_scroll_with_saga(direction)
  local hover = require "lspsaga.hover"
  local finder = require "lspsaga.provider"
  local signature = require "lspsaga.signaturehelp"
  local implement = require "lspsaga.implement"

  if hover.has_saga_hover() then
    hover.scroll_in_hover(direction)
  elseif finder.has_saga_def_preview() then
    finder.scroll_in_def_preview(direction)
  elseif signature.has_saga_signature() then
    signature.scroll_in_signature(direction)
  elseif implement.has_implement_win() then
    implement.scroll_in_implement(direction)
  else
    local map = direction == 1 and "<C-f>" or "<C-b>"
    local key = api.nvim_replace_termcodes(map, true, false, true)
    api.nvim_feedkeys(key, "n", true)
  end
end

function action.scroll_in_win(win, direction, current_win_lnum, last_lnum, height)
  current_win_lnum = current_win_lnum
  if direction == 1 then
    current_win_lnum = current_win_lnum + height
    if current_win_lnum >= last_lnum then
      current_win_lnum = last_lnum - 1
    end
  elseif direction == -1 then
    if current_win_lnum <= last_lnum and current_win_lnum > 0 then
      current_win_lnum = current_win_lnum - height
    end
    if current_win_lnum < 0 then
      current_win_lnum = 1
    end
  end
  if current_win_lnum <= 0 then
    current_win_lnum = 1
  end
  api.nvim_win_set_cursor(win, { current_win_lnum, 0 })
  return current_win_lnum
end

return action
