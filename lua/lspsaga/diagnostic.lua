local config = require('lspsaga').config_values
local if_nil, lsp = vim.F.if_nil, vim.lsp
local window = require('lspsaga.window')
local wrap = require('lspsaga.wrap')
local libs = require('lspsaga.libs')
local hover = require('lspsaga.hover')
local api = vim.api
local insert = table.insert

local diag = {}
local diag_type = { 'Error', 'Warn', 'Info', 'Hint' }

local virt_ns = api.nvim_create_namespace('LspsagaDiagnostic')

local jump_diagnostic_header = function(entry)
  if type(config.diagnostic_header) == 'table' then
    local icon = config.diagnostic_header[entry.severity]
    return icon
  end

  if type(config.diagnostic_header) == 'function' then
    local header = config.diagnostic_header(entry)
    if type(header) ~= 'string' then
      vim.notify('diagnostic_header function must return a string')
      return ''
    end
    return header
  end
end

local function render_diagnostic_window(entry)
  print(vim.inspect(entry))
  local current_buffer = api.nvim_get_current_buf()
  local wrap_message = {}
  local max_width = window.get_max_float_width()

  local header = jump_diagnostic_header(entry)
  -- remove dot in source tail {lua-language-server}
  if entry.source and entry.source:find('%.$') then
    entry.source = entry.source:gsub('%.', '')
  end
  local source = config.show_diagnostic_source and entry.source or ''
  if #config.diagnostic_source_bracket == 2 and #source > 0 then
    source = config.diagnostic_source_bracket[1] .. source .. config.diagnostic_source_bracket[2]
  end
  wrap_message[1] = header .. ' ' .. diag_type[entry.severity]

  table.insert(wrap_message, source .. ' ' .. entry.message)

  wrap_message = wrap.wrap_contents(wrap_message, max_width, {
    fill = true,
    pad_left = 1,
  })

  local truncate_line = wrap.add_truncate_line(wrap_message)
  table.insert(wrap_message, 2, truncate_line)

  local hi_name = 'LspSagaDiagnostic' .. diag_type[entry.severity]
  local content_opts = {
    contents = wrap_message,
    filetype = 'plaintext',
    highlight = hi_name,
  }

  local opts = {
    relative = 'cursor',
    style = 'minimal',
    move_col = 3,
  }

  local bufnr, winid = window.create_win_with_border(content_opts, opts)
  local win_config = api.nvim_win_get_config(winid)
  -- print(vim.inspect(win_config))

  local above = win_config['row'][false] < vim.fn.winline()

  if win_config['anchor'] == 'NE' then
    opts.move_col = -1
  elseif win_config['anchor'] == 'NW' then
    opts.move_col = nil
  elseif win_config['anchor'] == 'SE' then
    opts.move_col = -2
  elseif win_config['anchor'] == 'SW' then
    opts.move_col = nil
  end

  local virt_bufnr, virt_winid = window.create_win_with_border({
    contents = libs.generate_empty_table(#wrap_message),
    border = 'none',
    winblend = 100,
  }, opts)

  local title_icon_length = #header + #diag_type[entry.severity] + 1
  api.nvim_buf_add_highlight(bufnr, -1, hi_name, 0, 0, title_icon_length)

  local truncate_line_hl = 'LspSaga' .. diag_type[entry.severity] .. 'TrunCateLine'
  api.nvim_buf_add_highlight(bufnr, -1, truncate_line_hl, 1, 0, -1)

  local get_pos_with_char = function()
    if win_config['anchor'] == 'NE' then
      return { 'right_align', '━', '┛' }
    end

    if win_config['anchor'] == 'NW' then
      return { 'overlay', '┗', '━' }
    end

    if win_config['anchor'] == 'SE' then
      return { 'right_align', '━', '┓' }
    end

    if win_config['anchor'] == 'SW' then
      return { 'overlay', '┏', '━' }
    end
  end

  local pos_char = get_pos_with_char()

  for i, _ in pairs(wrap_message) do
    local virt_tbl = {}
    if i > 2 then
      api.nvim_buf_add_highlight(bufnr, -1, hi_name, i - 1, 0, -1)
    end

    if not above then
      if i == #wrap_message then
        insert(virt_tbl, { pos_char[2], hi_name })
        insert(virt_tbl, { '━', hi_name })
        insert(virt_tbl, { pos_char[3], hi_name })
      else
        insert(virt_tbl, { '┃', hi_name })
      end
    else
      if i == 1 then
        insert(virt_tbl, { pos_char[2], hi_name })
        insert(virt_tbl, { '━', hi_name })
        insert(virt_tbl, { pos_char[3], hi_name })
      else
        insert(virt_tbl, { '┃', hi_name })
      end
    end

    api.nvim_buf_set_extmark(virt_bufnr, virt_ns, i - 1, 0, {
      id = i + 1,
      virt_text = virt_tbl,
      virt_text_pos = pos_char[1],
      virt_lines_above = false,
    })
  end

  if config.show_diagnostic_source then
    api.nvim_buf_add_highlight(bufnr, -1, 'LspSagaDiagnosticSource', 2, 0, #source)
  end

  local close_autocmds = { 'CursorMoved', 'CursorMovedI', 'InsertEnter' }
  -- magic to solved the window disappear when trigger CusroMoed
  -- see https://github.com/neovim/neovim/issues/12923
  vim.defer_fn(function()
    libs.close_preview_autocmd(current_buffer, { winid, virt_winid }, close_autocmds)
  end, 0)

  api.nvim_buf_set_var(current_buffer, 'saga_diagnostic_floatwin', { bufnr, winid })
end

local function move_cursor(entry)
  local current_winid = api.nvim_get_current_win()
  local current_bufnr = api.nvim_get_current_buf()

  -- if has hover window close first
  hover.close_hover_window()
  -- if current position has a diagnostic floatwin when jump to next close
  -- curren diagnostic floatwin ensure only have one diagnostic floatwin in
  -- current buffer
  local has_var, wininfo = pcall(api.nvim_buf_get_var, current_bufnr, 'saga_diagnostic_floatwin')
  if has_var and api.nvim_win_is_valid(wininfo[2]) then
    api.nvim_win_close(wininfo[2], true)
  end

  api.nvim_win_set_cursor(current_winid, { entry.lnum + 1, entry.col })
  render_diagnostic_window(entry)
end

function diag.goto_next(opts)
  local next = vim.diagnostic.get_next(opts)
  if next == nil then
    return
  end
  move_cursor(next)
end

function diag.goto_prev(opts)
  local prev = vim.diagnostic.get_prev(opts)
  if not prev then
    return false
  end
  move_cursor(prev)
end

local function comp_severity_asc(diag1, diag2)
  return diag1['severity'] < diag2['severity']
end

local function show_diagnostics(opts, get_diagnostics)
  local close_hover = opts.close_hover or false

  -- if we have a hover rendered, don't show diagnostics due to this usually
  -- being bound to CursorHold which triggers after hover show
  if not close_hover and hover.has_saga_hover() then
    return
  end

  if not libs.check_lsp_active() then
    return
  end
  local max_width = window.get_max_float_width()

  -- if there already has diagnostic float window did not show show lines
  -- diagnostic window
  local has_var, diag_float_winid = pcall(api.nvim_buf_get_var, 0, 'diagnostic_float_window')
  if has_var and diag_float_winid ~= nil then
    if
      api.nvim_win_is_valid(diag_float_winid[1]) and api.nvim_win_is_valid(diag_float_winid[2])
    then
      return
    end
  end

  local current_buf = api.nvim_get_current_buf()
  local current_win = api.nvim_get_current_win()

  local severity_sort = if_nil(opts.severity_sort, true)
  local show_header = if_nil(opts.show_header, true)
  local current_line = api.nvim_win_get_cursor(current_win)[1]

  local lines = {}
  local highlights = {}
  if show_header then
    lines[1] = 'Diagnostics in line ' .. current_line
    highlights[1] = { 0, 'LspSagaDiagnosticHeader' }
  end

  local diagnostics = get_diagnostics()
  if vim.tbl_isempty(diagnostics) then
    return
  end

  local sorted_diagnostics = severity_sort and table.sort(diagnostics, comp_severity_asc)
    or diagnostics

  local severities = vim.diagnostic.severity
  for i, diagnostic in ipairs(sorted_diagnostics) do
    local prefix = string.format('%d. ', i)

    local hiname = 'Diagnostic' .. severities[diagnostic.severity] or severities[1]
    local message_lines = vim.split(diagnostic.message, '\n', true)
    table.insert(lines, prefix .. message_lines[1])
    table.insert(highlights, { #prefix + 1, hiname })
    if #message_lines[1] + 4 > max_width then
      table.insert(highlights, { #prefix + 1, hiname })
    end
    for j = 2, #message_lines do
      table.insert(lines, '   ' .. message_lines[j])
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
    filetype = 'plaintext',
    highlight = 'LspSagaDiagnosticBorder',
  }

  local bufnr, winid = window.create_win_with_border(content_opts, {
    focusable = false,
  })
  for i, hi in ipairs(highlights) do
    local _, hiname = unpack(hi)
    -- Start highlight after the prefix
    if i == 1 then
      api.nvim_buf_add_highlight(bufnr, -1, hiname, 0, 0, -1)
    else
      api.nvim_buf_add_highlight(bufnr, -1, hiname, i, 0, -1)
    end
  end
  api.nvim_buf_add_highlight(bufnr, -1, 'LspSagaDiagnosticTruncateLine', 1, 0, -1)
  local close_events = { 'CursorMoved', 'CursorMovedI', 'InsertEnter' }

  libs.close_preview_autocmd(current_buf, winid, close_events)
  api.nvim_win_set_var(current_win, 'show_line_diag_winids', winid)
  return winid
end

function diag.show_line_diagnostics(opts, bufnr, line_nr, client_id)
  local ok, diag_winid = pcall(api.nvim_win_get_var, 0, 'show_line_diag_winids')
  if ok and api.nvim_win_is_valid(diag_winid) then
    api.nvim_set_current_win(diag_winid)
    return
  end

  opts = opts or {}

  local get_line_diagnostics = function()
    bufnr = bufnr or api.nvim_get_current_buf()
    line_nr = line_nr or (vim.api.nvim_win_get_cursor(0)[1] - 1)

    return lsp.diagnostic.get_line_diagnostics(bufnr, line_nr, opts, client_id)
  end

  return show_diagnostics(opts, get_line_diagnostics)
end

local function get_diagnostic_start(diagnostic_entry)
  return diagnostic_entry['lnum'], diagnostic_entry['col']
end

local function get_diagnostic_end(diagnostic_entry)
  return diagnostic_entry['end_lnum'], diagnostic_entry['end_col']
end

local function in_range(cursor_line, cursor_char)
  return function(diagnostic)
    local start_line, start_char = get_diagnostic_start(diagnostic)
    local end_line, end_char = get_diagnostic_end(diagnostic)

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

function diag.show_cursor_diagnostics(opts, bufnr, client_id)
  opts = opts or {}

  local get_cursor_diagnostics = function()
    bufnr = bufnr or 0

    local line_nr = vim.api.nvim_win_get_cursor(0)[1] - 1
    local column_nr = vim.api.nvim_win_get_cursor(0)[2]

    return vim.tbl_filter(in_range(line_nr, column_nr), vim.diagnostic.get(bufnr, client_id))
  end

  return show_diagnostics(opts, get_cursor_diagnostics)
end

return diag
