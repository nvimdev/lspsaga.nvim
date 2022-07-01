local api = vim.api
local window = require 'lspsaga.window'
local M = {}

function M.open_float_terminal(command,border_style)
  local cmd = command or os.getenv("SHELL")
  border_style = border_style or 0

  -- get dimensions
  local width = api.nvim_get_option("columns")
  local height = api.nvim_get_option("lines")

  -- calculate our floating window size
  local win_height = math.ceil(height * 0.8)
  local win_width = math.ceil(width * 0.8)

  -- and its starting position
  local row = math.ceil((height - win_height) * 0.4)
  local col = math.ceil((width - win_width) * 0.5)

  -- set some options
  local opts = {
    style = "minimal",
    relative = "editor",
    width = win_width,
    height = win_height,
    row = row,
    col = col,
  }

  local content_opts = {
    contents = {},
    filetype = 'Floaterm',
    enter = true
  }

  local cb,cw,_,ow = window.open_shadow_float_win(content_opts,opts)
  vim.fn.termopen(cmd, {on_exit = function(...) M.close_float_terminal() end})
  api.nvim_command('setlocal nobuflisted')
  api.nvim_command('startinsert!')
  api.nvim_buf_set_var(cb,'float_terminal_win',{cw,ow})
end

function M.close_float_terminal()
  local has_var,float_terminal_win = pcall(api.nvim_buf_get_var,0,'float_terminal_win')
  if not has_var then return end
  window.nvim_close_valid_window(float_terminal_win)
end

return  M
