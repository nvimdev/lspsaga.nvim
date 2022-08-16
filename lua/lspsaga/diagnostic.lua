local config = require('lspsaga').config_values
local if_nil, lsp = vim.F.if_nil, vim.lsp
local window = require('lspsaga.window')
local wrap = require('lspsaga.wrap')
local libs = require('lspsaga.libs')
local hover = require('lspsaga.hover')
local api = vim.api
local insert = table.insert
local space = ' '

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

function diag:render_diagnostic_window(entry, option)
  option = option or {}
  -- print(vim.inspect(entry))
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

  local msgs = wrap.diagnostic_msg(source .. ' ' .. entry.message, max_width)
  for _, v in pairs(msgs) do
    table.insert(wrap_message, v)
  end

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

  self.bufnr, self.winid = window.create_win_with_border(content_opts, opts)
  local win_config = api.nvim_win_get_config(self.winid)

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

  self.virt_bufnr, self.virt_winid = window.create_win_with_border({
    contents = libs.generate_empty_table(#wrap_message),
    border = 'none',
  }, opts)

  local title_icon_length = #header + #diag_type[entry.severity] + 1
  api.nvim_buf_add_highlight(self.bufnr, -1, hi_name, 0, 0, title_icon_length)

  local truncate_line_hl = 'LspSaga' .. diag_type[entry.severity] .. 'TrunCateLine'
  api.nvim_buf_add_highlight(self.bufnr, -1, truncate_line_hl, 1, 0, -1)

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
      api.nvim_buf_add_highlight(self.bufnr, -1, hi_name, i - 1, 0, -1)
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

    api.nvim_buf_set_extmark(self.virt_bufnr, virt_ns, i - 1, 0, {
      id = i + 1,
      virt_text = virt_tbl,
      virt_text_pos = pos_char[1],
      virt_lines_above = false,
    })
  end

  if config.show_diagnostic_source then
    api.nvim_buf_add_highlight(self.bufnr, -1, 'LspSagaDiagnosticSource', 2, 0, #source)
  end

  local close_autocmds = { 'CursorMoved', 'CursorMovedI', 'InsertEnter' }
  -- magic to solved the window disappear when trigger CusroMoed
  -- see https://github.com/neovim/neovim/issues/12923
  vim.defer_fn(function()
    libs.close_preview_autocmd(current_buffer, { self.winid, self.virt_winid }, close_autocmds)
  end, 0)
end

function diag:move_cursor(entry)
  local current_winid = api.nvim_get_current_win()

  -- if has hover window close first
  hover.close_hover_window()
  -- if current position has a diagnostic floatwin when jump to next close
  -- curren diagnostic floatwin ensure only have one diagnostic floatwin in
  -- current buffer
  window.nvim_close_valid_window({ self.winid, self.virt_winid })

  api.nvim_win_set_cursor(current_winid, { entry.lnum + 1, entry.col })
  self:render_diagnostic_window(entry)
end

function diag.goto_next(opts)
  local next = vim.diagnostic.get_next(opts)
  if next == nil then
    return
  end
  diag:move_cursor(next)
end

function diag.goto_prev(opts)
  local prev = vim.diagnostic.get_prev(opts)
  if not prev then
    return false
  end
  diag:move_cursor(prev)
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

  local show_diagnostic_ns = api.nvim_create_namespace('LspsagaShowDiagnostic')
  if opts.show_virtual then
    api.nvim_buf_set_extmark(0, show_diagnostic_ns, current_line - 1, 0, {
      virt_lines = { { { '-------------------------------------------', 'DiagnosticError' } } },
      virt_lines_above = true,
    })
  end

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

    if config.show_diagnostic_source then
      message_lines[1] = prefix .. message_lines[1] .. space .. '[' .. diagnostic.source .. ']'
    end
    local start_col = diagnostic.range.start.character
    local end_col = diagnostic.range['end'].character
    local col_scope = 'col:' .. start_col .. '-' .. end_col
    message_lines[1] = message_lines[1] .. space .. col_scope

    local wrap_text = wrap.wrap_text(message_lines[1], max_width)
    for j = 1, #wrap_text do
      local tmp = { j, hiname }
      if j ~= 1 then
        wrap_text[j] = space .. space .. wrap_text[j]
      end
      if j == #wrap_text then
        table.insert(tmp, #wrap_text[j] - #col_scope)
      end
      table.insert(highlights, tmp)
    end
    libs.merge_table(lines, wrap_text)
  end

  local truncate_line = wrap.add_truncate_line(lines)
  table.insert(lines, 2, truncate_line)

  local content_opts = {
    contents = lines,
    highlight = 'LspSagaDiagnosticBorder',
  }

  local bufnr, winid = window.create_win_with_border(content_opts, {
    focusable = false,
  })

  for i, hi in ipairs(highlights) do
    local _, hiname, col_in_line = unpack(hi)
    -- Start highlight after the prefix
    if i == 1 then
      api.nvim_buf_add_highlight(bufnr, -1, hiname, 0, 0, -1)
    else
      api.nvim_buf_add_highlight(bufnr, -1, hiname, i, 0, -1)
    end

    if col_in_line then
      api.nvim_buf_add_highlight(bufnr, -1, 'ColInLineDiagnostic', i, col_in_line, -1)
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

  opts.show_virtual = true
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
