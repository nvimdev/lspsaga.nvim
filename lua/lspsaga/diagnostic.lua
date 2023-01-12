local config = require('lspsaga').config
local diag_conf, ui = config.diagnostic, config.ui
local diagnostic = vim.diagnostic
local api, fn, keymap = vim.api, vim.fn, vim.keymap.set
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

---@private
local function get_diag_type(severity)
  local type = { 'Error', 'Warn', 'Hint', 'Info' }
  return type[severity]
end

function diag:code_action_cb()
  if not ctx.bufnr or not api.nvim_buf_is_loaded(ctx.bufnr) then
    return
  end

  local contents = {
    '',
    ctx.theme.left .. ui.code_action .. 'Fix ' .. ctx.theme.right,
  }

  for index, client_with_actions in pairs(ctx.act.action_tuples) do
    if #client_with_actions ~= 2 then
      vim.notify('There has something wrong in aciton_tuples')
      return
    end
    if client_with_actions[2].title then
      local action_title = '[' .. index .. ']' .. ' ' .. client_with_actions[2].title
      table.insert(contents, action_title)
    end
  end

  local win_conf = api.nvim_win_get_config(ctx.winid)
  local increase =
    ctx.window.win_height_increase(contents, math.abs(win_conf.width / vim.o.columns))
  local start_line = api.nvim_buf_line_count(ctx.bufnr) + 1
  api.nvim_win_set_config(ctx.winid, { height = win_conf.height + increase + #contents })

  api.nvim_buf_set_option(ctx.bufnr, 'modifiable', true)
  api.nvim_buf_set_lines(ctx.bufnr, -1, -1, false, contents)
  api.nvim_buf_set_option(ctx.bufnr, 'modifiable', false)

  api.nvim_buf_add_highlight(ctx.bufnr, 0, 'DiagnosticActionTitle', start_line, 4, 11)
  api.nvim_buf_add_highlight(ctx.bufnr, 0, 'DiagnosticTitleSymbol', start_line, 0, 4)
  api.nvim_buf_add_highlight(ctx.bufnr, 0, 'DiagnosticTitleSymbol', start_line, 11, -1)

  for i = 2, #contents do
    api.nvim_buf_set_extmark(ctx.bufnr, virt_ns, start_line + i - 2, 0, {
      hl_group = 'CodeActionConceal',
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
  local max_width = ctx.window.get_max_float_width(0.7)
  ctx.main_buf = api.nvim_get_current_buf()
  local cur_word = fn.expand('<cword>')

  local source = ' '

  if entry.source then
    source = source .. entry.source
  end

  if entry.code then
    source = source .. '(' .. entry.code .. ')'
  end

  table.insert(content, '  ' .. entry.message)
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
    buftype = 'nofile',
    wrap = true,
    highlight = {
      border = hi_name .. 'border',
      normal = 'DiagnosticNormal',
    },
  }

  local increase = ctx.window.win_height_increase(content, 0.7)

  local opts = {
    relative = 'cursor',
    style = 'minimal',
    move_col = 3,
    width = max_width,
    height = #content + increase,
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
      { fg = colors.foreground, background = ui.colors.normal_bg }
    )
  end

  ctx.bufnr, ctx.winid = ctx.window.create_win_with_border(content_opts, opts)
  vim.wo[ctx.winid].conceallevel = 2
  vim.wo[ctx.winid].concealcursor = 'niv'
  vim.wo[ctx.winid].showbreak = 'NONE'
  vim.wo[ctx.winid].breakindent = true
  vim.wo[ctx.winid].breakindentopt = 'shift:2'

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
    opts.move_row = 1
  end

  opts.focusable = false
  if fn.has('nvim-0.9') == 1 then
    opts.title = nil
  end

  opts.height = opts.height + 1
  ctx.virt_bufnr, ctx.virt_winid = ctx.window.create_win_with_border({
    contents = ctx.libs.generate_empty_table(#content + 1),
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

  local lsa_colors = require('lspsaga.highlight').get_colors()()
  api.nvim_set_hl(0, 'DiagnosticMsgIcon', {
    background = colors.foreground,
    foreground = lsa_colors.green,
  })

  api.nvim_set_hl(0, 'DiagnosticMsg', {
    background = colors.foreground,
    foreground = lsa_colors.black,
  })

  api.nvim_set_hl(0, 'DiagnosticTitleSymbol', {
    foreground = colors.foreground,
    background = ui.colors.normal_bg,
  })

  api.nvim_set_hl(0, 'DiagnosticActionTitle', {
    background = colors.foreground,
    foreground = lsa_colors.black,
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

  api.nvim_create_autocmd('BufLeave', {
    buffer = ctx.bufnr,
    once = true,
    callback = function()
      if ctx.preview_winid and api.nvim_win_is_valid(ctx.preview_winid) then
        api.nvim_win_close(ctx.preview_winid, true)
        ctx.preview_winid = nil
        ctx.preview_bufnr = nil
      end
    end,
  })

  api.nvim_create_autocmd('BufLeave', {
    buffer = current_buffer,
    once = true,
    callback = function()
      vim.defer_fn(function()
        local cur = api.nvim_get_current_buf()
        if
          cur ~= current_buffer
          and cur ~= ctx.bufnr
          and ctx.bufnr
          and api.nvim_buf_is_loaded(ctx.bufnr)
        then
          api.nvim_win_close(ctx.winid, true)
          if ctx.virt_winid and api.nvim_win_is_valid(ctx.virt_winid) then
            api.nvim_win_close(ctx.virt_winid, true)
          end
          clean_ctx()
        end
      end, 0)
    end,
  })

  self:apply_map()

  vim.defer_fn(function()
    ctx.libs.close_preview_autocmd(
      current_buffer,
      { ctx.winid, ctx.virt_winid, ctx.preview_winid or nil },
      close_autocmds,
      function()
        if ctx.act then
          ctx.act:clear_tmp_data()
        end
      end
    )
  end, 0)
end

function diag:move_cursor(entry)
  if ctx.winid and api.nvim_win_is_valid(ctx.winid) then
    if diag_conf.twice_into then
      api.nvim_set_current_win(ctx.winid)
      return
    else
      api.nvim_win_close(ctx.winid, true)
    end
  end

  ctx.window = require('lspsaga.window')
  ctx.libs = require('lspsaga.libs')
  if diag_conf.show_code_action then
    ctx.act = require('lspsaga.codeaction')
    ctx.act:clear_tmp_data()
  end

  ctx.theme = require('lspsaga').theme()
  local current_winid = api.nvim_get_current_win()

  api.nvim_win_call(current_winid, function()
    -- Save position in the window's jumplist
    vim.cmd("normal! m'")
    api.nvim_win_set_cursor(current_winid, { entry.lnum + 1, entry.col })
    ctx.libs.jump_beacon({ entry.lnum, entry.col }, entry.end_col - entry.col)
    -- Open folds under the cursor
    vim.cmd('normal! zv')
  end)

  self:render_diagnostic_window(entry)
end

function diag.goto_next(opts)
  local next = diagnostic.get_next(opts)
  if next == nil then
    return
  end
  diag:move_cursor(next)
end

function diag.goto_prev(opts)
  local prev = diagnostic.get_prev(opts)
  if not prev then
    return false
  end
  diag:move_cursor(prev)
end

function diag:show(entrys, arg, cursor)
  local cur_buf = api.nvim_get_current_buf()
  local content = {}
  local max_width = math.floor(vim.o.columns * 0.6)
  local window = require('lspsaga.window')
  for index, entry in pairs(entrys) do
    local code_source =
      api.nvim_buf_get_text(entry.bufnr, entry.lnum, entry.col, entry.lnum, entry.end_col, {})
    local line = '[' .. index .. '] ' .. code_source[1] .. '\n' .. '  ' .. entry.message
    if entry.source then
      line = line .. '(' .. entry.source .. ')'
    end
    table.insert(content, line)
  end

  local content_opt = {
    contents = content,
    filetype = 'markdown',
    wrap = true,
    highlight = {
      normal = 'DiagnosticNormal',
      border = 'DiagnosticBorder',
    },
  }

  local increase = window.win_height_increase(content)
  local opt = {
    width = max_width,
    height = #content * 2 + increase,
    no_size_override = true,
  }

  if arg and arg == '++unfocus' then
    opt.focusable = false
  end

  if fn.has('nvim-0.9') == 1 then
    local theme = require('lspsaga').theme()
    local title = cursor and 'Cursor' or 'Line'
    opt.title = {
      { theme.left, 'TitleSymbol' },
      { config.ui.diagnostic, 'TitleIcon' },
      { title .. ' Diagnostic', 'TitleString' },
      { theme.right, 'TitleSymbol' },
    }
  end

  ctx.lnum_bufnr, ctx.lnum_winid = window.create_win_with_border(content_opt, opt)
  vim.wo[ctx.lnum_winid].conceallevel = 2
  vim.wo[ctx.lnum_winid].concealcursor = 'niv'
  vim.wo[ctx.lnum_winid].showbreak = 'NONE'
  vim.wo[ctx.lnum_winid].breakindent = true
  vim.wo[ctx.lnum_winid].breakindentopt = ''

  local ns = api.nvim_create_namespace('DiagnosticLnum')
  local index = 0
  for k, _ in pairs(content) do
    if k > 1 then
      index = index + 2
    end
    local hi = 'Diagnostic' .. get_diag_type(entrys[k].severity)
    api.nvim_buf_set_extmark(ctx.lnum_bufnr, ns, index, 0, {
      hl_group = hi,
      end_col = 3,
      conceal = '◉',
    })
    api.nvim_buf_add_highlight(ctx.lnum_bufnr, 0, hi, index, 3, -1)
    api.nvim_buf_add_highlight(ctx.lnum_bufnr, 0, hi, index + 1, 2, -1)
  end

  local close_autocmds = { 'CursorMoved', 'CursorMovedI', 'InsertEnter', 'BufLeave' }

  vim.defer_fn(function()
    require('lspsaga.libs').close_preview_autocmd(cur_buf, ctx.lnum_winid, close_autocmds)
  end, 0)
end

local function get_diagnostic(cursor)
  cursor = cursor or nil
  local cur_buf = api.nvim_get_current_buf()
  local line, col = unpack(api.nvim_win_get_cursor(0))
  local entrys = diagnostic.get(cur_buf, { lnum = line - 1 })
  if not cursor then
    return entrys
  end
  local res = {}
  for _, v in pairs(entrys) do
    if v.col <= col and v.end_col >= col then
      table.insert(res, v)
    end
  end
  return res
end

function diag:show_diagnostics(arg, cursor)
  local entrys = get_diagnostic(cursor)
  if vim.tbl_isempty(entrys) then
    return
  end
  self:show(entrys, arg, cursor)
end

return setmetatable(diag, ctx)
