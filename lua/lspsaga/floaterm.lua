local api = vim.api
local window = require "lspsaga.window"

local function open_float_terminal(command, border_style)
  local cmd = command or ""
  border_style = border_style or 0

  -- get dimensions
  local width = api.nvim_get_option "columns"
  local height = api.nvim_get_option "lines"

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
    filetype = "Floaterm",
    enter = true,
  }

  local cb, cw, ow
  if border_style == 0 then
    cb, cw, _, ow = window.open_shadow_float_win(content_opts, opts)
  else
    local border_opts = {
      border = border_style,
    }
    cb, cw, _, ow = window.create_win_with_border(content_opts, opts)
  end
  api.nvim_command("terminal " .. cmd)
  api.nvim_command "setlocal nobuflisted"
  api.nvim_command "startinsert!"
  api.nvim_buf_set_var(cb, "float_terminal_win", { cw, ow })
end

local function close_float_terminal()
  local has_var, float_terminal_win = pcall(api.nvim_buf_get_var, 0, "float_terminal_win")
  if not has_var then
    return
  end
  if
    float_terminal_win[1] ~= nil
    and api.nvim_win_is_valid(float_terminal_win[1])
    and float_terminal_win[2] ~= nil
    and api.nvim_win_is_valid(float_terminal_win[2])
  then
    api.nvim_win_close(float_terminal_win[1], true)
    api.nvim_win_close(float_terminal_win[2], true)
  end
end

return {
  open_float_terminal = open_float_terminal,
  close_float_terminal = close_float_terminal,
}
