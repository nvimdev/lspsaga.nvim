local api = vim.api
local action = {}

function action.scroll_in_win(win,direction,current_win_lnum,last_lnum,height)
  if direction == 1 then
    current_win_lnum = current_win_lnum + height
    if current_win_lnum >= last_lnum then
      current_win_lnum = last_lnum -1
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
  api.nvim_win_set_cursor(win,{current_win_lnum,0})
end

return action
