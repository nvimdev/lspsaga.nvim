local vim, api = vim, vim.api
local window = require('lspsaga.window')

local M = {}
M.__index = M
function M.new()
  local t = {
    win_to_grid = {},
    grid_to_win = {},
    base_win = {}
  }
  return setmetatable(t,M)
end

function M:add_win(content_opts,opts)
  local buf,win
  opts.layout = self
  if not opts.reference then
    buf, win = window.create_win_with_border(content_opts,opts) 
    table.insert(self.base_win, win)
    self.win_to_grid[win] = { #self.base_win*1000, #self.base_win*1000 }
    self.grid_to_win[self.win_to_grid[win]] = win
  else
    local reference = opts.reference
    local reference_grid_id = self.win_to_grid[reference]
    if not reference_grid_id then
      error('error, no reference_grid_id',vim.log.levels.ERROR)
    end
    if vim.tbl_contains({'above','down'},opts.direction) then
      buf,win = window.create_win_vertical(content_opts,opts)
      self.win_to_grid[win] = vim.deepcopy(self.win_to_grid[reference])
      if opts.direction == 'down' then
        self.win_to_grid[win][1] = self.win_to_grid[win][1] + 1
      else
        self.win_to_grid[win][1] = self.win_to_grid[win][1] - 1
      end
    else
      buf,win = window.create_win_horizontal(content_opts,opts)
      self.win_to_grid[win] = vim.deepcopy(self.win_to_grid[reference])
      if opts.direction == 'right' then
        self.win_to_grid[win][2] = self.win_to_grid[win][2] + 1
      else
        self.win_to_grid[win][2] = self.win_to_grid[win][2] - 1
      end
    end
    self.grid_to_win[self.win_to_grid[win]] = win
  end
  return buf,win
end

local remove_if_exist = function(win,lst)
  local found
  for i,w in ipairs(lst) do
    if w==win then
      found = i
      break
    end
  end
  if found then
    for j = found+1,#lst do
      lst[j-1] = lst[j]
    end
    return vim.list_slice(lst,1,#lst-1)
  else
    return lst
  end
end

function M:remove_win(win)
  win = type(win)=='table' and win or {win}
  for _, w in ipairs(win) do
    if not w or not vim.tbl_contains(vim.tbl_keys(self.win_to_grid),w) then
      goto skip
    end
    self.base_win = remove_if_exist(w, self.base_win)
    if self.win_to_grid[w] then
      self.grid_to_win[self.win_to_grid[w]] = nil
      self.win_to_grid[w] = nil
    end
    window.nvim_close_valid_window(w)
    ::skip::
  end
end

function M:ensure_layout()
  for _, w in ipairs(vim.tbl_keys(self.win_to_grid)) do
    if not vim.api.nvim_win_is_valid(w) then
      self:remove_win(w)
    end
  end
end


function M:rearange_all_win()
  -- TODO: resize and re-position all wins based on M.wins and reference
  -- local winid
  -- local new_config = {
  --   col = {
  --     [false] = 60,
  --   },
  --   row = {
  --     [false] = 10,
  --   }
  -- }
  -- local curr_config = vim.api.nvim_win_get_config(winid)
  -- new_config = vim.tbl_deep_extend('force',curr_config,new_config)
  -- vim.api.nvim_win_set_config(winid,new_config)
end

return M
