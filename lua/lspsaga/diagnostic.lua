-- lsp dianostic
local vim,api,lsp,util = vim,vim.api,vim.lsp,vim.lsp.util
local window = require 'lspsaga.window'
local libs = require('lspsaga.libs')
local wrap = require 'lspsaga.wrap'
local config = require('lspsaga').config_values
local if_nil = vim.F.if_nil
local M = {}

-- lsp severity icon
-- 1:Error 2:Warning 3:Information 4:Hint
local severity_icon = {
  config.error_header,
  config.warn_header,
  config.infor_header,
  config.hint_header,
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
--   local active_clients = lsp.get_active_clients()
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
        window.nvim_close_valid_window(prev_win)
        api.nvim_buf_set_var(0,"diagnostic_float_window",nil)
        api.nvim_buf_set_var(0,"diagnostic_prev_position",nil)
        api.nvim_command("hi! link DiagnosticTruncateLine DiagnosticTruncateLine")
      end
    end
  end
end

local function jump_to_entry(entry)
  local has_value,prev_fw = pcall(api.nvim_buf_get_var,0,"diagnostic_float_window")
  if has_value and prev_fw ~= nil then
    if api.nvim_win_is_valid(prev_fw[1]) and api.nvim_win_is_valid(prev_fw[2]) then
      api.nvim_win_close(prev_fw[1], true)
      api.nvim_win_close(prev_fw[2], true)
    end
  end

  local has_var,line_diag_winids = pcall(api.nvim_win_get_var,0,"show_line_diag_winids")
  if has_var and line_diag_winids ~= nil then
    window.nvim_close_valid_window(line_diag_winids)
  end

  local entry_line = get_line(entry) + 1
  local entry_character = get_character(entry)
  local hiname ={"LspDiagErrorBorder","LspDiagWarnBorder","LspDiagInforBorder","LspDiagHintBorder"}

  -- add server source in diagnostic float window
  local server_source = entry.source or ''
  local header = severity_icon[entry.severity] ..' '..'['.. server_source..']'
  if entry.message:find('\n') then
    entry.message = entry.message:gsub("[\n\r]", " ")
  end

  local max_width = config.max_diag_msg_width
  if vim.fn.winwidth(0) < 85 then
    max_width = 45
  end

  if config.debug then
    print(vim.inspect(entry.message))
  end

  local wrap_message = wrap.wrap_text(entry.message,max_width)

  local truncate_line = ''
  if #header > config.max_diag_msg_width then
    truncate_line = wrap.add_truncate_line({header})
  else
    truncate_line = wrap.add_truncate_line(wrap_message)
  end
  table.insert(wrap_message,1,header)
  table.insert(wrap_message,2,truncate_line)

  -- set curosr
  local border_opts = {
    border = config.border_style,
    highlight = hiname[entry.severity]
  }

  local content_opts = {
    contents = wrap_message,
    filetype = 'markdown',
  }

  api.nvim_win_set_cursor(0, {entry_line, entry_character})
  local fb,fw,_,bw = window.create_float_window(content_opts,border_opts)

  -- use a variable to control diagnostic floatwidnow
  api.nvim_buf_set_var(0,"diagnostic_float_window",{fw,bw})
  api.nvim_buf_set_var(0,"diagnostic_prev_position",{entry_line,entry_character})
  lsp.util.close_preview_autocmd({"CursorMovedI", "BufHidden", "BufLeave"}, fw)
  lsp.util.close_preview_autocmd({"CursorMovedI", "BufHidden", "BufLeave"}, bw)
  api.nvim_command("autocmd CursorMoved <buffer> lua require('lspsaga.diagnostic').close_preview()")

  --add highlight
  api.nvim_buf_add_highlight(fb,-1,hiname[entry.severity],0,0,-1)
  api.nvim_buf_add_highlight(fb,-1,"DiagnosticTruncateLine",1,0,-1)
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

function M.show_line_diagnostics(opts, bufnr, line_nr, client_id)
  local active,msg = libs.check_lsp_active()
  if not active then print(msg) return end

  -- if there already has diagnostic float window did not show show lines
  -- diagnostic window
  local has_var, diag_float_winid = pcall(api.nvim_buf_get_var,0,"diagnostic_float_window")
  if has_var and diag_float_winid ~= nil then
    if api.nvim_win_is_valid(diag_float_winid[1]) and api.nvim_win_is_valid(diag_float_winid[2]) then
      return
    end
  end

  opts = opts or {}
  opts.severity_sort = if_nil(opts.severity_sort, true)

  local show_header = if_nil(opts.show_header, true)

  bufnr = bufnr or 0
  line_nr = line_nr or (vim.api.nvim_win_get_cursor(0)[1] - 1)

  local lines = {}
  local highlights = {}
  if show_header then
    table.insert(lines, "Diagnostics:")
    table.insert(highlights, {0, "Bold"})
  end

  local line_diagnostics = lsp.diagnostic.get_line_diagnostics(bufnr, line_nr, opts, client_id)
  if vim.tbl_isempty(line_diagnostics) then return end

  for i, diagnostic in ipairs(line_diagnostics) do
    local prefix = string.format("%d. ", i)
    local hiname = lsp.diagnostic._get_floating_severity_highlight_name(diagnostic.severity)
    assert(hiname, 'unknown severity: ' .. tostring(diagnostic.severity))

    local message_lines = vim.split(diagnostic.message, '\n', true)
    table.insert(lines, prefix..message_lines[1])
    table.insert(highlights, {#prefix + 1, hiname})
    if #message_lines[1] + 4 > config.max_diag_msg_width then
      table.insert(highlights,{#prefix + 1, hiname})
    end
    for j = 2, #message_lines do
      table.insert(lines, '   '..message_lines[j])
      table.insert(highlights, {0, hiname})
    end
  end
  local border_opts = {
    border = config.border_style,
    highlight = 'LspLinesDiagBorder'
  }

  local wrap_message = wrap.wrap_contents(lines,config.max_diag_msg_width,{
    fill = true, pad_left = 3
  })
  local truncate_line = wrap.add_truncate_line(lines)
  table.insert(wrap_message,2,truncate_line)

  local content_opts = {
    contents = wrap_message,
    filetype = 'plaintext',
  }

  local cb,cw,bb,bw = window.create_float_window(content_opts,border_opts,opts)
  for i, hi in ipairs(highlights) do
    local _, hiname = unpack(hi)
    -- Start highlight after the prefix
    api.nvim_buf_add_highlight(cb, -1, hiname, i, 3, -1)
  end
  api.nvim_buf_add_highlight(cb,-1,'LineDiagTuncateLine',1,0,-1)
  util.close_preview_autocmd({"CursorMoved", "CursorMovedI", "BufHidden", "BufLeave"}, bw)
  util.close_preview_autocmd({"CursorMoved", "CursorMovedI", "BufHidden", "BufLeave"}, cw)
  api.nvim_win_set_var(0,"show_line_diag_winids",{cw,bw})
  return cb,cw,bb,bw
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
