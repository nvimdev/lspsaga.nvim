local config = require('lspsaga').config
local diag_conf, ui = config.diagnostic, config.ui
local api, if_nil, lsp, fn, keymap = vim.api, vim.F.if_nil, vim.lsp, vim.fn, vim.keymap.set
local libs = require('lspsaga.libs')
local insert = table.insert

local diag = {}

local ctx = {}
function ctx.__newindex(_, k, v)
  ctx[k] = v
end

--- clean ctx table data
--- notice just make ctx to empty not free memory before gc
---@private
local function clean_ctx()
  if diag_conf.show_code_action and ctx.act then
    ctx.act:clear_tmp_data()
  end
  for k, _ in pairs(ctx) do
    ctx[k] = nil
  end
end

local virt_ns = api.nvim_create_namespace('LspsagaDiagnostic')

local function get_action_obj()
  return require('lspsaga.codeaction')
end

---@private
local function get_diag_type(severity)
  local type = { 'Error', 'Warn', 'Hint', 'Info' }
  return type[severity]
end

function diag:code_action_cb()
  if not ctx.bufnr and not api.nvim_buf_is_loaded(ctx.bufnr) then
    return
  end

  local contents = {
    '',
    ctx.theme.left .. ui.code_action .. 'Fix ' .. ctx.theme.right,
  }

  for index, client_with_actions in pairs(ctx.act.action_tuples) do
    local action_title = ''
    if #client_with_actions ~= 2 then
      vim.notify('There has something wrong in aciton_tuples')
      return
    end
    if client_with_actions[2].title then
      action_title = '[' .. index .. ']' .. ' ' .. client_with_actions[2].title
    end
    table.insert(contents, action_title)
  end

  local start_line = api.nvim_buf_line_count(ctx.bufnr) + 1
  local win_conf = api.nvim_win_get_config(ctx.winid)
  api.nvim_win_set_config(ctx.winid, { height = win_conf.height + #contents })

  api.nvim_buf_set_option(ctx.bufnr, 'modifiable', true)
  api.nvim_buf_set_lines(ctx.bufnr, -1, -1, false, contents)
  api.nvim_buf_set_option(ctx.bufnr, 'modifiable', false)

  api.nvim_buf_add_highlight(ctx.bufnr, 0, 'DiagnosticActionTitle', start_line, 4, 11)
  api.nvim_buf_add_highlight(ctx.bufnr, 0, 'DiagnosticTitleSymbol', start_line, 0, 4)
  api.nvim_buf_add_highlight(ctx.bufnr, 0, 'DiagnosticTitleSymbol', start_line, 11, -1)

  for i = 2, #contents do
    api.nvim_buf_set_extmark(ctx.bufnr, virt_ns, start_line + i - 2, 0, {
      end_col = 2,
      conceal = '◉',
    })
    api.nvim_buf_add_highlight(ctx.bufnr, 0, 'CodeActionText', start_line + i - 1, 0, -1)
  end

  api.nvim_create_autocmd('CursorMoved', {
    buffer = ctx.bufnr,
    callback = function()
      ctx.preview_winid = ctx.act:action_preview(ctx.winid, ctx.main_buf)
    end,
    desc = 'Lspsaga show code action preview in diagnostic window',
  })
end

function diag:do_code_action()
  local line = api.nvim_get_current_line()
  local num = line:match('%[([1-9])%]')
  if not num then
    return
  end
  ctx.act:do_code_action(num)
end

function diag:apply_map()
  keymap('n', diag_conf.keys.exec_action, function()
    self:do_code_action()
    ctx.window.nvim_close_valid_window({ ctx.winid, ctx.virt_winid, ctx.preview_winid })
  end, { buffer = ctx.bufnr })

  keymap('n', diag_conf.keys.quit, function()
    for _, id in pairs({ ctx.winid, ctx.virt_winid, ctx.preview_winid }) do
      if api.nvim_win_is_valid(id) then
        api.nvim_win_close(id, true)
      end
    end
  end, { buffer = ctx.bufnr })
end

function diag:render_diagnostic_window(entry, option)
  option = option or {}
  local content = {
    ctx.theme.left .. '  Msg ' .. ctx.theme.right,
  }
  ctx.window = require('lspsaga.window')
  local max_width = ctx.window.get_max_float_width()
  ctx.main_buf = api.nvim_get_current_buf()
  local cur_word = fn.expand('<cword>')

  local source = ' '

  if entry.source then
    source = source .. entry.source
  end

  if entry.code then
    source = source .. '(' .. entry.code .. ')'
  end

  local wrap = require('lspsaga.wrap')
  local msgs = wrap.wrap_text(entry.message, max_width)
  for _, v in pairs(msgs) do
    table.insert(content, v)
  end
  content[#content] = content[#content] .. source

  if diag_conf.show_code_action then
    ctx.act:send_code_action_request(ctx.main_buf, {
      range = {
        start = { entry.lnum + 1, entry.col },
        ['end'] = { entry.lnum + 1, entry.col },
      },
    }, function()
      self:code_action_cb()
    end)
  end

  local diag_type = get_diag_type(entry.severity)
  local hi_name = 'Diagnostic' .. diag_type
  local content_opts = {
    contents = content,
    filetype = 'markdown',
    highlight = {
      border = hi_name .. 'border',
      normal = 'DiagnosticNormal',
    },
  }

  local max_len = ctx.window.get_max_content_length(content)
  if max_len < max_width then
    max_width = max_len
  end

  local opts = {
    relative = 'cursor',
    style = 'minimal',
    move_col = 3,
    width = max_width,
    height = #content,
    no_size_override = true,
  }

  local colors = api.nvim_get_hl_by_name('Diagnostic' .. diag_type, true)
  if fn.has('nvim-0.9') == 1 then
    opts.title = {
      { ' ' .. cur_word, 'Diagnostic' .. diag_type .. 'Title' },
    }
    api.nvim_set_hl(
      0,
      'Diagnostic' .. diag_type .. 'Title',
      { fg = colors.foreground, background = ui.normal }
    )
  end

  ctx.bufnr, ctx.winid = ctx.window.create_win_with_border(content_opts, opts)
  vim.wo[ctx.winid].conceallevel = 2
  vim.wo[ctx.winid].concealcursor = 'niv'

  local win_config = api.nvim_win_get_config(ctx.winid)

  local above = win_config['row'][false] < fn.winline()

  if win_config['anchor'] == 'NE' then
    opts.move_col = -1
  elseif win_config['anchor'] == 'NW' then
    opts.move_col = nil
  elseif win_config['anchor'] == 'SE' then
    opts.move_col = -2
  elseif win_config['anchor'] == 'SW' then
    opts.move_col = nil
  end

  opts.focusable = false
  if fn.has('nvim-0.9') == 1 then
    opts.title = nil
  end

  opts.height = opts.height + 1
  ctx.virt_bufnr, ctx.virt_winid = ctx.window.create_win_with_border({
    contents = libs.generate_empty_table(#content + 1),
    border = 'none',
    winblend = 100,
  }, opts)

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

  for i = 1, #content + 1 do
    local virt_tbl = {}
    if i > 2 then
      api.nvim_buf_add_highlight(ctx.bufnr, -1, hi_name, i - 1, 0, -1)
    end

    if not above then
      if i == #content + 1 then
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

    api.nvim_buf_set_extmark(ctx.virt_bufnr, virt_ns, i - 1, 0, {
      id = i + 1,
      virt_text = virt_tbl,
      virt_text_pos = pos_char[1],
      virt_lines_above = false,
    })

    if i ~= #content + 1 and i > 1 then
      api.nvim_buf_add_highlight(ctx.bufnr, 0, 'DiagnosticText', i - 1, 0, -1)
    end
  end

  api.nvim_buf_add_highlight(ctx.bufnr, 0, 'DiagnosticTitleSymbol', 0, 0, #ctx.theme.left)
  api.nvim_buf_add_highlight(
    ctx.bufnr,
    0,
    'DiagnosticMsgIcon',
    0,
    #ctx.theme.left,
    #ctx.theme.left + 5
  )
  api.nvim_buf_add_highlight(
    ctx.bufnr,
    0,
    'DiagnosticMsg',
    0,
    #ctx.theme.left + 5,
    #ctx.theme.left + 9
  )

  api.nvim_buf_add_highlight(ctx.bufnr, 0, 'DiagnosticTitleSymbol', 0, #ctx.theme.left + 9, -1)

  api.nvim_set_hl(0, 'DiagnosticText', {
    foreground = colors.foreground,
  })

  api.nvim_set_hl(0, 'DiagnosticTitleText', {
    background = ui.background,
    foreground = '#963656',
  })

  api.nvim_set_hl(0, 'DiagnosticMsgIcon', {
    background = colors.foreground,
    foreground = '#b7f59a',
  })

  api.nvim_set_hl(0, 'DiagnosticMsg', {
    background = colors.foreground,
    foreground = '#000000',
  })

  api.nvim_set_hl(0, 'DiagnosticTitleSymbol', {
    foreground = colors.foreground,
    background = ui.background,
  })

  api.nvim_set_hl(0, 'DiagnosticActionTitle', {
    background = colors.foreground,
    foreground = '#000000',
  })

  api.nvim_buf_add_highlight(
    ctx.bufnr,
    0,
    'DiagnosticSource',
    #content - 1,
    #content[#content] - #source,
    -1
  )

  local current_buffer = api.nvim_get_current_buf()
  local close_autocmds = { 'CursorMoved', 'CursorMovedI', 'InsertEnter' }

  api.nvim_create_autocmd('WinClosed', {
    buffer = ctx.bufnr,
    once = true,
    callback = function()
      if ctx.preview_winid and api.nvim_win_is_valid(ctx.preview_winid) then
        api.nvim_win_close(ctx.preview_winid, true)
      end
      clean_ctx()
    end,
  })

  self:apply_map()

  vim.defer_fn(function()
    libs.close_preview_autocmd(
      current_buffer,
      { ctx.winid, ctx.virt_winid, ctx.preview_winid or nil },
      close_autocmds,
      function()
        clean_ctx()
      end
    )
  end, 0)
end

function diag:move_cursor(entry)
  if diag_conf.twice_into and ctx.winid and api.nvim_win_is_valid(ctx.winid) then
    api.nvim_set_current_win(ctx.winid)
    return
  end

  if diag_conf.show_code_action then
    ctx.act = get_action_obj()
    ctx.act:clear_tmp_data()
  end

  ctx.theme = require('lspsaga').theme()

  local current_winid = api.nvim_get_current_win()

  api.nvim_win_call(current_winid, function()
    -- Save position in the window's jumplist
    vim.cmd("normal! m'")
    api.nvim_win_set_cursor(current_winid, { entry.lnum + 1, entry.col })
    -- Open folds under the cursor
    vim.cmd('normal! zv')
  end)

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

function diag:show_diagnostics(opts, get_diagnostics)
  if not libs.check_lsp_active() then
    return
  end
  local max_width = ctx.window.get_max_float_width()

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

  local severity_sort = if_nil(opts.severity_sort, true)

  local lines = {}
  local highlights = {}

  local diagnostics = get_diagnostics()
  if vim.tbl_isempty(diagnostics) then
    return
  end

  local sorted_diagnostics = severity_sort and table.sort(diagnostics, comp_severity_asc)
    or diagnostics

  local severities = vim.diagnostic.severity
  local wrap = require('lspsaga.wrap')
  for i, diagnostic in ipairs(sorted_diagnostics) do
    local prefix = string.format('%d. ', i)

    local hiname = 'Diagnostic' .. severities[diagnostic.severity] or severities[1]
    local message_lines = vim.split(diagnostic.message, '\n', { trimempty = true })

    local space = ' '
    if diag_conf.show_source then
      message_lines[1] = prefix .. message_lines[1] .. space .. '[' .. diagnostic.source .. ']'
    end
    local start_col = diagnostic.col or diagnostic.range.start.character
    local end_col = diagnostic.end_col or diagnostic.range['end'].character
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

  ctx.show_diag_bufnr, ctx.show_diag_winid = ctx.window.create_win_with_border(content_opts)

  for i, hi in ipairs(highlights) do
    local _, hiname = unpack(hi)
    -- Start highlight after the prefix
    if i == 1 then
      api.nvim_buf_add_highlight(ctx.show_diag_bufnr, -1, hiname, 0, 0, -1)
    else
      api.nvim_buf_add_highlight(ctx.show_diag_bufnr, -1, hiname, i, 0, -1)
    end
  end

  api.nvim_buf_add_highlight(ctx.show_diag_bufnr, -1, 'LspSagaDiagnosticTruncateLine', 1, 0, -1)
  local close_events = { 'CursorMoved', 'InsertEnter' }

  libs.close_preview_autocmd(current_buf, ctx.show_diag_winid, close_events)
  return ctx.show_diag_winid
end

function diag.show_line_diagnostics(opts, bufnr, line_nr, client_id)
  if diag.show_diag_winid and api.nvim_win_is_valid(diag.show_diag_winid) then
    api.nvim_set_current_win(diag.show_diag_winid)
    return
  end

  opts = opts or {}

  local current_line = api.nvim_win_get_cursor(0)[1]
  local get_line_diagnostics = function()
    bufnr = bufnr or api.nvim_get_current_buf()
    line_nr = line_nr or (current_line - 1)

    return lsp.diagnostic.get_line_diagnostics(bufnr, line_nr, opts, client_id)
  end

  opts.show_virtual = true
  opts.header = function()
    return 'Diagnostics in line ' .. current_line
  end
  return diag:show_diagnostics(opts, get_line_diagnostics)
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

  local pos = api.nvim_win_get_cursor(0)

  local get_cursor_diagnostics = function()
    bufnr = bufnr or 0

    local line_nr = pos[1] - 1
    local column_nr = pos[2]

    return vim.tbl_filter(in_range(line_nr, column_nr), vim.diagnostic.get(bufnr, client_id))
  end

  opts.header = function()
    return 'Diagnostic in Column ' .. pos[2]
  end

  return diag:show_diagnostics(opts, get_cursor_diagnostics)
end

return setmetatable(diag, ctx)
