-- lsp diagnostic
local window = require "lspsaga.window"
local libs = require "lspsaga.libs"
local wrap = require "lspsaga.wrap"
local config = require("lspsaga").config_values
local if_nil = vim.F.if_nil
local hover = require "lspsaga.hover"
local fmt = string.format
local M = {}

M.highlights = {
  [vim.diagnostic.severity.ERROR] = "DiagnosticFloatingError",
  [vim.diagnostic.severity.WARN] = "DiagnosticFloatingWarn",
  [vim.diagnostic.severity.INFO] = "DiagnosticFloatingInfo",
  [vim.diagnostic.severity.HINT] = "DiagnosticFloatingHint",
}

---TODO(refactor): move to popup.lua
local show_diagnostics = function(opts, get_diagnostics)
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

  -- if there already has diagnostic float window did not show show lines diagnostic window
  local has_var, diag_float_winid = pcall(vim.api.nvim_buf_get_var, 0, "diagnostic_float_window")
  if has_var and diag_float_winid ~= nil then
    if vim.api.nvim_win_is_valid(diag_float_winid[1]) and vim.api.nvim_win_is_valid(diag_float_winid[2]) then
      return
    end
  end

  local severity_sort = if_nil(opts.severity_sort, true)
  local show_header = if_nil(opts.show_header, true)

  local lines = {}
  local highlights = {}
  if show_header then
    lines[1] = config.diagnostic_header_icon .. "Diagnostics:"
    highlights[1] = { 0, "LspSagaDiagnosticHeader" }
  end

  local diagnostics = get_diagnostics()

  if vim.tbl_isempty(diagnostics) then
    return
  elseif severity_sort then
    table.sort(diagnostics, function(a, b)
      return a["severity"] < b["severity"]
    end)
  end

  for i, diagnostic in ipairs(diagnostics) do
    local prefix = string.format(config.diagnostic_prefix_format, i)
    local hiname = M.highlights[diagnostic.severity]
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

  local wrap_message = wrap.wrap_contents(lines, max_width, { fill = true, pad_left = 3 })
  if show_header then
    local truncate_line = wrap.add_truncate_line(wrap_message)
    table.insert(wrap_message, 2, truncate_line)
  end

  local content_opts = { contents = wrap_message, filetype = "plaintext", highlight = "LspSagaDiagnosticBorder" }
  local bufnr, winid = window.create_win_with_border(content_opts, opts)

  for i, hi in ipairs(highlights) do
    local _, hiname = unpack(hi)
    -- Start highlight after the prefix
    if i == 1 then
      vim.api.nvim_buf_add_highlight(bufnr, -1, hiname, 0, 0, -1)
    else
      vim.api.nvim_buf_add_highlight(bufnr, -1, hiname, i, 3, -1)
    end
  end

  vim.api.nvim_buf_add_highlight(bufnr, -1, "LspSagaDiagnosticTruncateLine", 1, 0, -1)
  vim.lsp.util.close_preview_autocmd({ "CursorMoved", "CursorMovedI", "BufHidden", "BufLeave" }, winid)
  vim.api.nvim_win_set_var(0, "show_line_diag_winids", winid)

  return winid
end

M.show_cursor_diagnostics = function(opts, bufnr)
  return show_diagnostics(opts or {}, function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local lnum, cnum = cursor[1] - 1, cursor[2]

    return vim.tbl_filter(
      function(diagnostic)
        local start_line, start_char = diagnostic['lnum'], diagnostic["col"]
        local end_line, end_char = diagnostic["end_lnum"], diagnostic["end_col"]
        local one_line_diag = start_line == end_line

        if one_line_diag and start_line == lnum then
          if cnum >= start_char and cnum < end_char then
            return true
          end
          -- multi line diagnostic
        else
          if lnum == start_line and cnum >= start_char then
            return true
          elseif lnum == end_line and cnum < end_char then
            return true
          elseif lnum > start_line and lnum < end_line then
            return true
          end
        end

        return false
      end,
      vim.diagnostic.get(bufnr, {
        lnum = lnum,
      })
    )
  end)
end

M.show_line_diagnostics = function(opts, lnum, bufnr)
  return show_diagnostics(opts or {}, function()
    return vim.diagnostic.get(bufnr, { lnum = lnum or (vim.api.nvim_win_get_cursor(0)[1] - 1) })
  end)
end

M.navigate = function(direction)
  return function(opts)
    opts = opts or {}
    local pos = vim.diagnostic[fmt("get_%s_pos", direction)](opts)
    if not pos then
      --- TODO: move to notify.lua, notify.diagnostics.no_more_diagnostics(direction:gsub("^%l", string.upper)))
      return print(fmt("Diagnostic%s: No more valid diagnostics to move to.", direction:gsub("^%l", string.upper)))
    end

    local win_id = opts.win_id or vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_cursor(win_id, { pos[1] + 1, pos[2] })

    vim.schedule(function()
      M.show_line_diagnostics(opts.popup_opts, nil, vim.api.nvim_win_get_buf(win_id))
    end)
  end
end

--- TODO: at some point just use builtin function to preview diagnostics
--- Missing borders and formating of title
-- vim.diagnostic.show_position_diagnostics {
--   focusable = false,
--   close_event = { "CursorMoved", "CursorMovedI", "BufHidden", "BufLeave" },
--   source = false,
--   show_header = true,
--   border = "rounded",
--   format = function(info)
--     local lines = {}
--     if config.diagnostic_show_source then
--       lines[#lines + 1] = info.source:gsub("%.", ":")
--     end
--     lines[#lines + 1] = info.message
--     if config.diagnostic_show_code then
--       lines[#lines + 1] = fmt("(%s)", info.user_data.lsp.code)
--     end
--     return table.concat(lines, " ")
--   end,
-- }

return M
