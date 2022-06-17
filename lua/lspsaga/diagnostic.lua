local config = require('lspsaga').config_values
local window = require('lspsaga.window')
local wrap = require('lspsaga.wrap')
local libs = require('lspsaga.libs')
local hover = require('lspsaga.hover')
local api = vim.api

local diag = {}
local diag_type = {'Error','Warn','Info','Hint'}

local function render_diagnostic_window(entry)
  local current_buffer = api.nvim_get_current_buf()
  local wrap_message  = {}
  local max_width = window.get_max_float_width()

  wrap_message[1] = config.diagnostic_header_icon ..diag_type[entry.severity]
  table.insert(wrap_message,entry.message)

  wrap_message = wrap.wrap_contents(wrap_message,max_width,{
      fill = true, pad_left = 3
    })

  local truncate_line = wrap.add_truncate_line(wrap_message)
  table.insert(wrap_message,2,truncate_line)
  local content_opts = {
      contents = wrap_message,
      filetype = 'plaintext',
      highlight = 'DiagnosticError'
    }

  local _,winid = window.create_win_with_border(content_opts)
  local close_autocmds = {"CursorMoved", "CursorMovedI","InsertEnter"}

  -- magic to solved the window disappear when trigger CusroMoed
  -- see https://github.com/neovim/neovim/issues/12923
  vim.defer_fn(function()
    libs.close_preview_autocmd(current_buffer,winid,close_autocmds)
  end,0)
end

function diag.goto_next()
  -- if has hover window close first
  hover.close_hover_window()

  local next = vim.diagnostic.get_next()
  if next == nil then return end

  local current_winid = api.nvim_get_current_win()
  api.nvim_win_set_cursor(current_winid,{next.lnum+1,next.col})
  render_diagnostic_window(next)
end

function diag.goto_prev()
  local prev = vim.diagnostic.get_prev()
  if not prev then
    return false
  end

end

return diag

