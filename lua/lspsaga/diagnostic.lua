-- lsp dianostic
local vim = vim
local api = vim.api
local lsp = vim.lsp
local window = require 'lspsaga.window'
local wrap = require 'lspsaga.wrap'
local M = {}

-- lsp severity icon
-- 1:Error 2:Warning 3:Information 4:Hint
local severity_icon = {
  "  Error",
  "  Warn",
  "  Infor",
  "  Hint"
}

local function get_line(diagnostic_entry)
  return diagnostic_entry["range"]["start"]["line"]
end

local function get_character(diagnostic_entry)
  return diagnostic_entry["range"]["start"]["character"]
end

local function compare_positions(line_a, line_b, character_a, character_b)
  if line_a < line_b then
      return true
  elseif line_b < line_a then
      return false
  elseif character_a < character_b then
      return true
  else
      return false
  end
end

local function compare_diagnostics_entries(entry_a, entry_b)
  local line_a = get_line(entry_a)
  local line_b = get_line(entry_b)
  local character_a = get_character(entry_a)
  local character_b = get_character(entry_b)
  return compare_positions(line_a, line_b, character_a, character_b)
end

local function get_sorted_diagnostics()
  local active_clients = lsp.get_active_clients()

  local buffer_number = api.nvim_get_current_buf()
  -- If no client id there will be get all diagnostics
  local diagnostics = lsp.diagnostic.get(buffer_number)

  if diagnostics ~= nil then
      table.sort(diagnostics, compare_diagnostics_entries)
      return diagnostics
  else
      return {}
  end
end

local function get_above_entry()
  local diagnostics = get_sorted_diagnostics()
  local cursor = api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]
  local cursor_character = cursor[2] - 1

  for i = #diagnostics, 1, -1 do
    local entry = diagnostics[i]
    local entry_line = get_line(entry)
    local entry_character = get_character(entry)

    if not compare_positions(cursor_line - 1, entry_line, cursor_character - 1, entry_character) then
        return entry
    end
  end

  return nil
end

local function get_below_entry()
  local diagnostics = get_sorted_diagnostics()
  local cursor = api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1] - 1
  local cursor_character = cursor[2]

  for _, entry in ipairs(diagnostics) do
      local entry_line = get_line(entry)
      local entry_character = get_character(entry)

      if compare_positions(cursor_line, entry_line, cursor_character, entry_character) then
          return entry
      end
  end

  return nil
end

-- TODO: when https://github.com/neovim/neovim/issues/12923 sovled
-- rewrite this function
function M.close_preview()
  local ok,prev_win = pcall(api.nvim_buf_get_var,0,"diagnostic_float_window")
  if prev_win == nil then return end
  if ok and prev_win[1] ~= nil and api.nvim_win_is_valid(prev_win[1]) then
    local current_position = vim.fn.getpos('.')
    local has_lineinfo,lines = pcall(api.nvim_buf_get_var,0,"diagnostic_prev_position")
    if has_lineinfo then
      if lines[1] ~= current_position[2] or lines[2] ~= current_position[3]-1 then
        api.nvim_win_close(prev_win[1],true)
        api.nvim_win_close(prev_win[2],true)
        api.nvim_buf_set_var(0,"diagnostic_float_window",nil)
        api.nvim_buf_set_var(0,"diagnostic_prev_position",nil)
        -- restore the hilight
        api.nvim_command("hi! link LspFloatWinBorder LspFloatWinBorder")
        api.nvim_command("hi! link DiagnosticTruncateLine DiagnosticTruncateLine")
      end
    end
  end
end

local function jump_to_entry(entry)
  local has_value,prev_fw = pcall(api.nvim_buf_get_var,0,"diagnostic_float_window")
  if has_value and prev_fw ~=nil and api.nvim_win_is_valid(prev_fw[1]) then
    api.nvim_win_close(prev_fw[1],true)
    api.nvim_win_close(prev_fw[2],true)
  end

  local diagnostic_message = {}
  local entry_line = get_line(entry) + 1
  local entry_character = get_character(entry)
  local hiname ={"DiagnosticError","DiagnosticWarning","DiagnosticInformation","DiagnosticHint"}

  -- add server source in diagnostic float window
  local server_source = entry.source
  local header = severity_icon[entry.severity] ..' '..'['.. server_source..']'
  table.insert(diagnostic_message,header)

  local wrap_message = wrap.wrap_line(entry.message,50)
  local truncate_line = wrap.add_truncate_line(wrap_message)
  table.insert(diagnostic_message,truncate_line)
  for _,v in pairs(wrap_message) do
    table.insert(diagnostic_message,v)
  end

  -- set curosr
  api.nvim_win_set_cursor(0, {entry_line, entry_character})
  local fb,fw,_,bw = window.create_float_window(diagnostic_message,'markdown',1,false,false)

  -- use a variable to control diagnostic floatwidnow
  api.nvim_buf_set_var(0,"diagnostic_float_window",{fw,bw})
  api.nvim_buf_set_var(0,"diagnostic_prev_position",{entry_line,entry_character})
  lsp.util.close_preview_autocmd({"CursorMovedI", "BufHidden", "BufLeave"}, fw)
  lsp.util.close_preview_autocmd({"CursorMovedI", "BufHidden", "BufLeave"}, bw)
  api.nvim_command("autocmd CursorMoved <buffer> lua require('lspsaga.diagnostic').close_preview()")

  --add highlight
  api.nvim_buf_add_highlight(fb,-1,hiname[entry.severity],0,0,-1)
  api.nvim_buf_add_highlight(fb,-1,"DiagnosticTruncateLine",1,0,-1)
  -- match current diagnostic syntax
  api.nvim_command("hi! link LspFloatWinBorder ".. hiname[entry.severity])
  api.nvim_command("hi! link DiagnosticTruncateLine "..hiname[entry.severity])
end


local function jump_one_times(get_entry_function)
  for _ = 1, 1, -1 do
    local entry = get_entry_function()

    if entry == nil then
        break
    else
        jump_to_entry(entry)
    end
  end
end

function M.lsp_jump_diagnostic_prev()
  jump_one_times(get_above_entry)
end

function M.lsp_jump_diagnostic_next()
  jump_one_times(get_below_entry)
end

function M.lsp_diagnostic_sign(opts)
  local group = {
    err_group = {
      highlight = 'LspDiagnosticsSignError',
      sign =opts.error_sign
    },
    warn_group = {
      highlight = 'LspDiagnosticsSignWarning',
      sign =opts.warn_sign
    },
    hint_group = {
      highlight = 'LspDiagnosticsSignHint',
      sign =opts.hint_sign
    },
    infor_group = {
      highlight = 'LspDiagnosticsSignInformation',
      sign =opts.infor_sign
    },
  }

  for _,g in pairs(group) do
    vim.fn.sign_define(
    g.highlight,
    {text=g.sign,texthl=g.highlight,linehl='',numhl=''}
    )
  end
end

return M
