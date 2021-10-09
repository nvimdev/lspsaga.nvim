-- lsp dianostic
local vim, api, lsp, util = vim, vim.api, vim.lsp, vim.lsp.util
local window = require "lspsaga.window"
local libs = require "lspsaga.libs"
local wrap = require "lspsaga.wrap"
local config = require("lspsaga").config_values
local if_nil = vim.F.if_nil
local hover = require "lspsaga.hover"
local M = {}

-- :h diagnostic-highlights
local diagnostic_highlights = {}
if vim.diagnostic then
  diagnostic_highlights = {
    [vim.diagnostic.severity.ERROR] = "DiagnosticFloatingError",
    [vim.diagnostic.severity.WARN] = "DiagnosticFloatingWarn",
    [vim.diagnostic.severity.INFO] = "DiagnosticFloatingInfo",
    [vim.diagnostic.severity.HINT] = "DiagnosticFloatingHint",
  }
end

local function _iter_diagnostic_move_pos(name, opts, pos)
  opts = opts or {}

  local enable_popup = if_nil(opts.enable_popup, true)
  local win_id = opts.win_id or vim.api.nvim_get_current_win()

  if not pos then
    print(string.format("%s: No more valid diagnostics to move to.", name))
    return
  end

  vim.api.nvim_win_set_cursor(win_id, { pos[1] + 1, pos[2] })

  if enable_popup then
    vim.schedule(function()
      M.show_line_diagnostics(opts.popup_opts, vim.api.nvim_win_get_buf(win_id))
    end)
  end
end

function M.lsp_jump_diagnostic_next(opts)
  return _iter_diagnostic_move_pos("DiagnosticNext", opts, vim.lsp.diagnostic.get_next_pos(opts))
end

function M.lsp_jump_diagnostic_prev(opts)
  return _iter_diagnostic_move_pos("DiagnosticPrevious", opts, vim.lsp.diagnostic.get_prev_pos(opts))
end

local function comp_severity_asc(diag1, diag2)
  return diag1["severity"] < diag2["severity"]
end

local function show_diagnostics(opts, get_diagnostics)
  local close_hover = opts.close_hover or false

  -- if we have a hover rendered, don't show diagnostics due to this usually
  -- being bound to CursorHold which triggers after hover show
  if not close_hover and hover.has_saga_hover() then
    return
  end

  local active, _ = libs.check_lsp_active()
  if not active then
    return
  end
  local max_width = window.get_max_float_width()

  -- if there already has diagnostic float window did not show show lines
  -- diagnostic window
  local has_var, diag_float_winid = pcall(api.nvim_buf_get_var, 0, "diagnostic_float_window")
  if has_var and diag_float_winid ~= nil then
    if api.nvim_win_is_valid(diag_float_winid[1]) and api.nvim_win_is_valid(diag_float_winid[2]) then
      return
    end
  end

  local severity_sort = if_nil(opts.severity_sort, true)
  local show_header = if_nil(opts.show_header, true)

  local lines = {}
  local highlights = {}
  if show_header then
    lines[1] = config.dianostic_header_icon .. "Diagnostics:"
    highlights[1] = { 0, "LspSagaDiagnosticHeader" }
  end

  local diagnostics = get_diagnostics()
  if vim.tbl_isempty(diagnostics) then
    return
  end

  local sorted_diagnostics = severity_sort and table.sort(diagnostics, comp_severity_asc) or diagnostics

  for i, diagnostic in ipairs(sorted_diagnostics) do
    local prefix = string.format("%d. ", i)
    local hiname = diagnostic_highlights[diagnostic.severity]
      or lsp.diagnostic._get_floating_severity_highlight_name(diagnostic.severity)
    assert(hiname, "unknown severity: " .. tostring(diagnostic.severity))

    local message_lines = vim.split(diagnostic.message, "\n", true)
    table.insert(lines, prefix .. message_lines[1])
    table.insert(highlights, { #prefix + 1, hiname })
    if #message_lines[1] + 4 > max_width then
      table.insert(highlights, { #prefix + 1, hiname })
    end
    for j = 2, #message_lines do
      table.insert(lines, "   " .. message_lines[j])
      table.insert(highlights, { 0, hiname })
    end
  end

  local wrap_message = wrap.wrap_contents(lines, max_width, {
    fill = true,
    pad_left = 3,
  })
  local truncate_line = wrap.add_truncate_line(wrap_message)
  table.insert(wrap_message, 2, truncate_line)

  local content_opts = {
    contents = wrap_message,
    filetype = "plaintext",
    highlight = "LspSagaDiagnosticBorder",
  }

  local bufnr, winid = window.create_win_with_border(content_opts, opts)
  for i, hi in ipairs(highlights) do
    local _, hiname = unpack(hi)
    -- Start highlight after the prefix
    if i == 1 then
      api.nvim_buf_add_highlight(bufnr, -1, hiname, 0, 0, -1)
    else
      api.nvim_buf_add_highlight(bufnr, -1, hiname, i, 3, -1)
    end
  end
  api.nvim_buf_add_highlight(bufnr, -1, "LspSagaDiagnosticTruncateLine", 1, 0, -1)
  util.close_preview_autocmd({ "CursorMoved", "CursorMovedI", "BufHidden", "BufLeave" }, winid)
  api.nvim_win_set_var(0, "show_line_diag_winids", winid)
  return winid
end

local function get_diagnostic_start(diagnostic_entry)
  local start_pos = diagnostic_entry["range"]["start"]
  return start_pos["line"], start_pos["character"]
end

local function get_diagnostic_end(diagnostic_entry)
  local end_pos = diagnostic_entry["range"]["end"]
  return end_pos["line"], end_pos["character"]
end

local function in_range(cursor_line, cursor_char)
  return function(diagnostic)
    start_line, start_char = get_diagnostic_start(diagnostic)
    end_line, end_char = get_diagnostic_end(diagnostic)

    local one_line_diag = start_line == end_line

    if one_line_diag and start_line == cursor_line then
      if cursor_char >= start_char and cursor_char < end_char then
        return true
      end

      -- multi line diagnostic
    else
      if cursor_line == start_line and cursor_char >= start_char then
        return true
      elseif cursor_line == end_line and cursor_char < end_char then
        return true
      elseif cursor_line > start_line and cursor_line < end_line then
        return true
      end
    end

    return false
  end
end

function M.show_cursor_diagnostics(opts, bufnr, client_id)
  opts = opts or {}

  local get_cursor_diagnostics = function()
    bufnr = bufnr or 0

    line_nr = vim.api.nvim_win_get_cursor(0)[1] - 1
    column_nr = vim.api.nvim_win_get_cursor(0)[2]

    return vim.tbl_filter(in_range(line_nr, column_nr), lsp.diagnostic.get(bufnr, client_id))
  end

  return show_diagnostics(opts, get_cursor_diagnostics)
end

function M.show_line_diagnostics(opts, bufnr, line_nr, client_id)
  opts = opts or {}

  local get_line_diagnostics = function()
    bufnr = bufnr or 0
    line_nr = line_nr or (vim.api.nvim_win_get_cursor(0)[1] - 1)

    return lsp.diagnostic.get_line_diagnostics(bufnr, line_nr, opts, client_id)
  end

  return show_diagnostics(opts, get_line_diagnostics)
end

function M.lsp_diagnostic_sign(opts)
  local group = {
    err_group = {
      highlight = "LspDiagnosticsSignError",
      sign = opts.error_sign,
    },
    warn_group = {
      highlight = "LspDiagnosticsSignWarning",
      sign = opts.warn_sign,
    },
    hint_group = {
      highlight = "LspDiagnosticsSignHint",
      sign = opts.hint_sign,
    },
    infor_group = {
      highlight = "LspDiagnosticsSignInformation",
      sign = opts.infor_sign,
    },
  }

  for _, g in pairs(group) do
    vim.fn.sign_define(g.highlight, { text = g.sign, texthl = g.highlight, linehl = "", numhl = "" })
  end
end

return M
