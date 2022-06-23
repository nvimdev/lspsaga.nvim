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

  local icon = config.diagnostic_header_icon[entry.severity]
  wrap_message[1] = icon .. ' ' .. diag_type[entry.severity]
  table.insert(wrap_message,entry.message)
  wrap_message = wrap.wrap_contents(wrap_message,max_width,{
      fill = true, pad_left = 3
    })

  local truncate_line = wrap.add_truncate_line(wrap_message)
  table.insert(wrap_message,2,truncate_line)

  local hi_name = 'LspSagaDiagnostic' .. diag_type[entry.severity]
  local content_opts = {
      contents = wrap_message,
      filetype = 'plaintext',
      highlight = hi_name
  }

  local bufnr,winid = window.create_win_with_border(content_opts)

  api.nvim_buf_add_highlight(bufnr,-1,hi_name,0,0,#icon)
  api.nvim_buf_add_highlight(bufnr,-1,hi_name,0,#icon,-1)

  local truncate_line_hl = 'LspSaga'..diag_type[entry.severity] ..'TrunCateLine'
  api.nvim_buf_add_highlight(bufnr,-1,truncate_line_hl,1,0,-1)

  for i,_ in pairs(wrap_message) do
    if i > 2 then
      api.nvim_buf_add_highlight(bufnr,-1,hi_name,i-1,0,-1)
    end
  end

  local close_autocmds = {"CursorMoved", "CursorMovedI","InsertEnter"}
  -- magic to solved the window disappear when trigger CusroMoed
  -- see https://github.com/neovim/neovim/issues/12923
  vim.defer_fn(function()
    libs.close_preview_autocmd(current_buffer,winid,close_autocmds)
  end,0)

  api.nvim_buf_set_var(current_buffer,'saga_diagnostic_floatwin',{bufnr,winid})
end

local function move_cursor(entry)
  local current_winid = api.nvim_get_current_win()
  local current_bufnr = api.nvim_get_current_buf()

  -- if has hover window close first
  hover.close_hover_window()
  -- if current position has a diagnostic floatwin when jump to next close
  -- curren diagnostic floatwin ensure only have one diagnostic floatwin in
  -- current buffer
  local has_var,wininfo = pcall(api.nvim_buf_get_var,current_bufnr,'saga_diagnostic_floatwin')
  if has_var and api.nvim_win_is_valid(wininfo[2]) then
    api.nvim_win_close(wininfo[2],true)
  end

  api.nvim_win_set_cursor(current_winid,{entry.lnum+1,entry.col})
  render_diagnostic_window(entry)
end

function diag.goto_next()
  local next = vim.diagnostic.get_next()
  if next == nil then return end
  move_cursor(next)
end

function diag.goto_prev()
  local prev = vim.diagnostic.get_prev()
  if not prev then
    return false
  end
  move_cursor(prev)
end

return diag
