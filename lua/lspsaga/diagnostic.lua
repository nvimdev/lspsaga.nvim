local config = require('lspsaga').config
local act = require('lspsaga.codeaction')
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local diag_conf, ui = config.diagnostic, config.ui
local diagnostic = vim.diagnostic
local api, fn, keymap = vim.api, vim.fn, vim.keymap.set
local insert = table.insert

local diag = {}

local ctx = {}

function diag.__newindex(t, k, v)
  rawset(t, k, v)
end

diag.__index = diag

--- clean ctx table data
--- notice just make ctx to empty not free memory before gc
---@private
local function clean_ctx()
  for k, _ in pairs(ctx) do
    ctx[k] = nil
  end
end

local function get_diagnostic_sign(type)
  local prefix = 'DiagnosticSign'
  return fn.sign_getdefined(prefix .. type)
end

local virt_ns = api.nvim_create_namespace('LspsagaDiagnostic')

---@private
local function get_diag_type(severity)
  local type = { 'Error', 'Warn', 'Info', 'Hint' }
  return severity and type[severity] or type
end

local function get_colors(hi_name)
  local color = api.nvim_get_hl_by_name(hi_name, true)
  return color
end

local function gen_truncate_line(width)
  local char = '─'
  return char:rep(math.floor(width / api.nvim_strwidth(char)))
end

local function clean_msg(msg)
  if msg:find('%(.+%)%S$') then
    return msg:gsub('%(.+%)%S$', '')
  end
  return msg
end

function diag:code_action_cb()
  if not self.bufnr or not api.nvim_buf_is_loaded(self.bufnr) then
    return
  end

  local contents = {}

  for index, client_with_actions in pairs(act.action_tuples) do
    if #client_with_actions ~= 2 then
      vim.notify('There is something wrong in aciton_tuples')
      return
    end
    if client_with_actions[2].title then
      local title = clean_msg(client_with_actions[2].title)
      local action_title = '[[' .. index .. ']] ' .. title
      table.insert(contents, action_title)
    end
  end

  local win_conf = api.nvim_win_get_config(self.winid)
  local increase = window.win_height_increase(contents, math.abs(win_conf.width / vim.o.columns))
  table.insert(contents, 1, gen_truncate_line(win_conf.width))
  local start_line = api.nvim_buf_line_count(self.bufnr) + 1
  api.nvim_win_set_config(self.winid, { height = win_conf.height + increase + #contents })

  api.nvim_buf_set_option(self.bufnr, 'modifiable', true)
  api.nvim_buf_set_lines(self.bufnr, -1, -1, false, contents)
  api.nvim_buf_set_option(self.bufnr, 'modifiable', false)

  api.nvim_buf_add_highlight(self.bufnr, 0, 'Comment', start_line - 1, 0, -1)
  for i = 2, #contents do
    api.nvim_buf_add_highlight(self.bufnr, 0, 'CodeActionText', start_line + i - 2, 0, -1)
  end

  keymap('n', diag_conf.keys.go_action, function()
    if self.winid and api.nvim_win_is_valid(self.winid) then
      api.nvim_win_set_cursor(self.winid, { start_line + 2, 4 })
    end
  end, { buffer = self.bufnr, nowait = true, noremap = true })

  if diag_conf.jump_num_shortcut then
    self.remove_num_map = function()
      for i = 3, #contents do
        pcall(vim.keymap.del, 'n', tostring(i - 2), { buffer = self.main_buf })
      end
    end

    act:num_shortcut(self.main_buf, function()
      if self.winid and api.nvim_win_is_valid(self.winid) then
        api.nvim_win_close(self.winid, true)
      end
      if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
        api.nvim_win_close(self.preview_winid, true)
      end
      vim.defer_fn(function()
        clean_ctx()
      end, 10)
    end)
  end

  api.nvim_create_autocmd('CursorMoved', {
    buffer = self.bufnr,
    callback = function()
      self.preview_winid = act:action_preview(self.winid, self.main_buf)
    end,
    desc = 'Lspsaga show code action preview in diagnostic window',
  })
end

function diag:do_code_action()
  local line = api.nvim_get_current_line()
  local num = line:match('%[(%d+)%]')
  if not num then
    return
  end
  act:do_code_action(num)
end

function diag:apply_map()
  keymap('n', diag_conf.keys.exec_action, function()
    self:do_code_action()
    window.nvim_close_valid_window({ self.winid, self.virt_winid, self.preview_winid })
  end, { buffer = self.bufnr, nowait = true })

  keymap('n', diag_conf.keys.quit, function()
    for _, id in pairs({ self.winid, self.virt_winid, self.preview_winid }) do
      if api.nvim_win_is_valid(id) then
        api.nvim_win_close(id, true)
      end
    end
  end, { buffer = self.bufnr, nowait = true })
end

function diag:render_diagnostic_window(entry, option)
  option = option or {}
  self.main_buf = api.nvim_get_current_buf()
  local diag_type = get_diag_type(entry.severity)
  local content = {}

  local source = ' '

  if entry.source then
    source = source .. entry.source
  end

  if entry.code then
    source = source .. '(' .. entry.code .. ')'
  end

  local convert = vim.split(entry.message, '\n', { trimempty = true })
  vim.list_extend(content, convert)
  content[#content] = content[#content] .. source

  if diag_conf.show_code_action then
    act:send_code_action_request(self.main_buf, {
      range = {
        start = { entry.lnum + 1, entry.col },
        ['end'] = { entry.lnum + 1, entry.col },
      },
    }, function()
      self:code_action_cb()
    end)
  end
  local max_width = math.floor(vim.o.columns * diag_conf.max_width)
  local max_len = window.get_max_content_length(content)

  if max_len < max_width then
    max_width = max_len
  elseif max_width - max_len > 15 then
    max_width = max_len + 10
  end

  local increase = window.win_height_increase(content, diag_conf.max_width)

  local hi_name = 'Diagnostic' .. diag_type
  local content_opts = {
    contents = content,
    filetype = 'markdown',
    buftype = 'nofile',
    wrap = true,
    highlight = {
      border = diag_conf.border_follow and hi_name or 'DiagnosticBorder',
      normal = 'DiagnosticNormal',
    },
  }

  local opts = {
    relative = 'cursor',
    style = 'minimal',
    move_col = 3,
    width = max_width,
    height = #content + increase,
    no_size_override = true,
    focusable = true,
  }

  self.bufnr, self.winid = window.create_win_with_border(content_opts, opts)
  vim.wo[self.winid].conceallevel = 2
  vim.wo[self.winid].concealcursor = 'niv'
  vim.wo[self.winid].showbreak = 'NONE'
  vim.wo[self.winid].breakindent = true
  vim.wo[self.winid].breakindentopt = 'shift:0'

  local win_config = api.nvim_win_get_config(self.winid)

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

  opts.height = opts.height + 1
  opts.width = 4

  local theme_bg = api.nvim_get_hl_by_name('Normal', true)
  local winblend = theme_bg.background and 100 or 0

  self.virt_bufnr, self.virt_winid = window.create_win_with_border({
    contents = libs.generate_empty_table(#content + 2),
    noborder = true,
    buftype = 'nofile',
    filetype = 'diagvirt',
    highlight = {
      normal = 'SagaNormal',
    },
    winblend = winblend,
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

  for i = 1, #content + 2 do
    local virt_tbl = {}
    if i == 1 then
      api.nvim_buf_add_highlight(self.bufnr, 0, 'DiagnosticText', i - 1, 0, -1)
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

    api.nvim_buf_set_extmark(self.virt_bufnr, virt_ns, i - 1, 0, {
      id = i + 1,
      virt_text = virt_tbl,
      virt_text_pos = pos_char[1],
      virt_lines_above = false,
    })
  end
  local color = get_colors(hi_name)

  api.nvim_set_hl(0, 'DiagnosticText', {
    foreground = color.foreground,
    default = diag_conf.text_hl_follow,
  })

  api.nvim_buf_add_highlight(
    self.bufnr,
    0,
    'DiagnosticSource',
    #content - 1,
    #content[#content] - #source,
    -1
  )

  local current_buffer = api.nvim_get_current_buf()

  api.nvim_create_autocmd('BufLeave', {
    buffer = self.bufnr,
    once = true,
    callback = function()
      if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
        api.nvim_win_close(self.preview_winid, true)
        self.preview_winid = nil
        self.preview_bufnr = nil
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
          and cur ~= self.bufnr
          and self.bufnr
          and api.nvim_buf_is_loaded(self.bufnr)
        then
          api.nvim_win_close(self.winid, true)
          if self.virt_winid and api.nvim_win_is_valid(self.virt_winid) then
            api.nvim_win_close(self.virt_winid, true)
          end
          clean_ctx()
        end
      end, 0)
    end,
  })

  self:apply_map()

  local close_autocmds = { 'CursorMoved', 'InsertEnter', 'TextChanged' }
  vim.defer_fn(function()
    libs.close_preview_autocmd(
      current_buffer,
      { self.winid, self.virt_winid, self.preview_winid or nil },
      close_autocmds,
      function(event)
        if self.remove_num_map then
          self.remove_num_map()
        end
        if event == 'TextChanged' or event == 'InsertEnter' then
          act:clean_context()
          clean_ctx()
        end
      end
    )
  end, 0)
end

function diag:move_cursor(entry)
  local current_winid = api.nvim_get_current_win()

  api.nvim_win_call(current_winid, function()
    -- Save position in the window's jumplist
    vim.cmd("normal! m'")
    api.nvim_win_set_cursor(current_winid, { entry.lnum + 1, entry.col })
    local width = entry.end_col - entry.col
    if width <= 0 then
      width = #api.nvim_get_current_line()
    end
    libs.jump_beacon({ entry.lnum, entry.col }, width)
    -- Open folds under the cursor
    vim.cmd('normal! zv')
  end)

  self:render_diagnostic_window(entry)
end

function diag:goto_next(opts)
  local next = diagnostic.get_next(opts)
  if next == nil then
    return
  end
  self:move_cursor(next)
end

function diag:goto_prev(opts)
  local prev = diagnostic.get_prev(opts)
  if not prev then
    return false
  end
  self:move_cursor(prev)
end

local function tbl_append(t1, t2)
  for i, v in ipairs(t2) do
    table.insert(t1, i, v)
  end
end

function diag:show(entrys, dtype, arg)
  local cur_buf = api.nvim_get_current_buf()
  local cur_win = api.nvim_get_current_win()
  local content = {}
  local len = {}
  local counts = {
    Error = 0,
    Warn = 0,
    Info = 0,
    Hint = 0,
  }
  for _, entry in pairs(entrys) do
    local type = get_diag_type(entry.severity)
    counts[type] = counts[type] + 1
    local start_col = entry.end_col > entry.col and entry.col or entry.end_col
    local end_col = entry.end_col > entry.col and entry.end_col or entry.col
    local code_source =
      api.nvim_buf_get_text(entry.bufnr, entry.lnum, start_col, entry.lnum, end_col, {})
    insert(len, #code_source[1])
    local sign = get_diagnostic_sign(get_diag_type(entry.severity))[1] or {}
    if not sign.text then
      sign.text = ui.diagnostic
    end
    local line = sign.text
      .. ' '
      .. code_source[1]
      .. '  '
      .. entry.lnum + 1
      .. ':'
      .. entry.col
      .. '\n'
      .. '  '
      .. entry.message
    if entry.source then
      line = line .. '(' .. entry.source .. ')'
    end
    table.insert(content, line)
  end

  local increase = window.win_height_increase(content)
  local max_len = window.get_max_content_length(content)
  local max_height = math.floor(vim.o.lines * 0.5)
  local actual_height = #content * 2 + increase + 2
  local max_width = math.floor(vim.o.columns * 0.5)
  local opt = {
    width = max_len + 8 < max_width and max_len + 5 or max_width,
    height = actual_height > max_height and max_height or actual_height,
    no_size_override = true,
  }

  local function dtype_title()
    local pos = api.nvim_win_get_cursor(cur_win)
    if dtype == 'cursor' then
      return 'Ln: ' .. pos[1] .. ' Col: ' .. pos[2]
    elseif dtype == 'line' then
      return 'Ln: ' .. pos[1]
    else
      return 'Buffer: ' .. cur_buf
    end
  end

  local title_count = dtype_title()
  local title_hi_scope = {}
  title_hi_scope[#title_hi_scope + 1] = { 'DiagnosticHead', 0, #title_count }
  ---@diagnostic disable-next-line: param-type-mismatch
  for _, i in ipairs(get_diag_type()) do
    if counts[i] ~= 0 then
      local start = #title_count
      title_count = title_count .. ' ' .. i .. ': ' .. counts[i]
      table.insert(title_hi_scope, { 'Diagnostic' .. i, start + 1, #title_count })
    end
  end

  local title = {
    title_count,
    gen_truncate_line(opt.width),
  }
  tbl_append(content, title)

  local content_opt = {
    contents = content,
    filetype = 'markdown',
    wrap = true,
    highlight = {
      normal = 'DiagnosticNormal',
      border = 'DiagnosticBorder',
    },
  }

  local close_autocmds = { 'CursorMoved', 'CursorMovedI', 'InsertEnter', 'BufDelete' }
  if arg and arg == '++unfocus' then
    opt.focusable = false
    close_autocmds[#close_autocmds] = 'BufLeave'
  else
    opt.focusable = true
    api.nvim_create_autocmd('BufEnter', {
      callback = function(args)
        if not self.lnum_winid or not api.nvim_win_is_valid(self.lnum_winid) then
          pcall(api.nvim_del_autocmd, args.id)
        end
        local curbuf = api.nvim_get_current_buf()
        if
          curbuf ~= self.lnum_bufnr
          and self.lnum_winid
          and api.nvim_win_is_valid(self.lnum_winid)
        then
          api.nvim_win_close(self.lnum_winid, true)
          self.lnum_winid = nil
          self.lnum_bufnr = nil
          pcall(api.nvim_del_autocmd, args.id)
        end
      end,
    })
  end

  self.lnum_bufnr, self.lnum_winid = window.create_win_with_border(content_opt, opt)
  vim.wo[self.lnum_winid].conceallevel = 2
  vim.wo[self.lnum_winid].concealcursor = 'niv'
  vim.wo[self.lnum_winid].showbreak = 'NONE'
  vim.wo[self.lnum_winid].breakindent = true
  vim.wo[self.lnum_winid].breakindentopt = ''

  for _, item in pairs(title_hi_scope) do
    api.nvim_buf_add_highlight(self.lnum_bufnr, 0, item[1], 0, item[2], item[3])
  end
  api.nvim_buf_add_highlight(self.lnum_bufnr, 0, 'Comment', 1, 0, -1)

  local index = 2
  for k, item in pairs(entrys) do
    local diag_type = get_diag_type(item.severity)
    local hi = 'Diagnostic' .. diag_type
    local sign = get_diagnostic_sign(diag_type)[1] or {}
    local col_end = sign.text and #sign.text + 1 or 1
    api.nvim_buf_add_highlight(self.lnum_bufnr, 0, hi, index, 0, col_end)
    api.nvim_buf_add_highlight(
      self.lnum_bufnr,
      0,
      'DiagnosticWord',
      index,
      col_end,
      col_end + len[k]
    )
    api.nvim_buf_add_highlight(self.lnum_bufnr, 0, 'DiagnosticPos', index, col_end + len[k] + 1, -1)
    api.nvim_buf_add_highlight(self.lnum_bufnr, 0, hi, index + 1, 2, -1)
    index = index + 2
  end

  vim.keymap.set('n', '<CR>', function()
    local text = api.nvim_get_current_line()
    local data = text:match('%d+:%d+')
    if data then
      local lnum, col = unpack(vim.split(data, ':', { trimempty = true }))
      if lnum and col then
        api.nvim_win_close(self.lnum_winid, true)
        self.lnum_winid = nil
        self.lnum_bufnr = nil
        api.nvim_set_current_win(cur_win)
        api.nvim_win_set_cursor(cur_win, { tonumber(lnum), tonumber(col) })
        local width = #api.nvim_get_current_line()
        libs.jump_beacon({ tonumber(lnum) - 1, tonumber(col) }, width)
      end
    end
  end, { buffer = self.lnum_bufnr, nowait = true, silent = true })

  vim.defer_fn(function()
    libs.close_preview_autocmd(cur_buf, self.lnum_winid, close_autocmds)
  end, 0)
end

local function sort_by_severity(entrys)
  table.sort(entrys, function(k1, k2)
    return k1.severity < k2.severity
  end)
end

local function get_diagnostic(type)
  local cur_buf = api.nvim_get_current_buf()
  local line, col = unpack(api.nvim_win_get_cursor(0))
  local entrys = diagnostic.get(cur_buf, { lnum = line - 1 })
  if type ~= 'cursor' then
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

function diag:show_diagnostics(arg, type)
  local entrys = get_diagnostic(type)
  if vim.tbl_isempty(entrys) then
    return
  end
  sort_by_severity(entrys)
  self:show(entrys, type, arg)
end

function diag:show_buf_diagnostic(arg)
  local entrys = vim.diagnostic.get(0)
  if vim.tbl_isempty(entrys) then
    return
  end
  sort_by_severity(entrys)
  self:show(entrys, type, arg)
end

function diag:close_exist_win()
  local has = false
  if self.winid and api.nvim_win_is_valid(self.winid) then
    has = true
    api.nvim_win_close(self.winid, true)
    act:clean_context()
  end
  if self.virt_winid and api.nvim_win_is_valid(self.virt_winid) then
    api.nvim_win_close(self.virt_winid, true)
  end
  if self.lnum_winid and api.nvim_win_is_valid(self.lnum_winid) then
    api.nvim_win_close(self.lnum_winid, true)
  end
  clean_ctx()
  return has
end

function diag:on_insert()
  local winid, bufnr

  local function on_top_right(content)
    local width = window.get_max_content_length(content)
    local opt = {
      relative = 'editor',
      row = 1,
      col = vim.o.columns - width,
      height = #content,
      width = width,
      -- focusable = false,
    }
    return opt
  end

  local function get_row_col(content)
    local res = {}
    local curwin = api.nvim_get_current_win()
    local max_len = window.get_max_content_length(content)
    local tail = #api.nvim_get_current_line() + 20
    local col = api.nvim_win_get_cursor(curwin)[2]
    if tail + max_len >= api.nvim_win_get_width(curwin) then
      res.row = fn.winline()
    else
      res.row = fn.winline() - 1
    end
    res.col = col + 20

    return res
  end

  local function create_window(content)
    local width = window.get_max_content_length(content)
    local float_opt
    if not config.diagnostic.on_insert_follow then
      float_opt = on_top_right(content)
    else
      local res = get_row_col(content)
      float_opt = {
        relative = 'win',
        win = api.nvim_get_current_win(),
        width = width,
        height = #content,
        row = res.row,
        col = res.col,
        focusable = false,
      }
    end
    --make sure this window highlight same as normal
    --may break other floatwindow highlight? not sure
    api.nvim_set_hl(0, 'NormalFloat', { link = 'Normal' })
    return window.create_win_with_border({
      contents = content,
      noborder = true,
    }, float_opt)
  end

  local function set_lines(content)
    if bufnr and api.nvim_buf_is_loaded(bufnr) then
      api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
    end
  end

  local function reduce_width()
    if not winid or not api.nvim_win_is_valid(winid) then
      return
    end
    local win_conf = api.nvim_win_get_config(winid)
    api.nvim_win_set_config(winid, {
      relative = win_conf.relative,
      width = 1,
      win = win_conf.win,
      row = win_conf.row[false],
      col = win_conf.col[false],
    })
  end

  local group = api.nvim_create_augroup('Lspsaga Diagnostic on insert', { clear = true })
  api.nvim_create_autocmd('DiagnosticChanged', {
    group = group,
    callback = function(opt)
      if api.nvim_get_mode().mode ~= 'i' then
        set_lines({})
        return
      end

      local content = {}
      local hi = {}
      local diagnostics = opt.data.diagnostics
      local lnum = api.nvim_win_get_cursor(0)[1] - 1
      for _, item in pairs(diagnostics) do
        if item.lnum == lnum then
          hi[#hi + 1] = 'Diagnostic' .. get_diag_type(item.severity)
          -- print(item.message)
          if item.message:find('\n') then
            item.message = item.message:gsub('\n', '')
          end
          content[#content + 1] = item.message
        end
      end

      if #content == 0 then
        set_lines({})
        reduce_width()
        return
      end

      if not winid or not api.nvim_win_is_valid(winid) then
        bufnr, winid = create_window(content)
        vim.bo[bufnr].modifiable = true
      end
      set_lines(content)
      if bufnr and api.nvim_buf_is_loaded(bufnr) then
        for i = 1, #hi do
          api.nvim_buf_add_highlight(bufnr, 0, hi[i], i - 1, 0, -1)
        end
      end

      if not diag_conf.on_insert_follow then
        api.nvim_win_set_config(winid, on_top_right(content))
        return
      end

      local curwin = api.nvim_get_current_win()
      local res = get_row_col(content)
      api.nvim_win_set_config(winid, {
        relative = 'win',
        win = curwin,
        height = #content,
        row = res.row,
        col = res.col,
      })
    end,
  })

  api.nvim_create_autocmd('ModeChanged', {
    group = group,
    callback = function()
      if winid and api.nvim_win_is_valid(winid) then
        set_lines({})
        reduce_width()
      end
    end,
  })

  api.nvim_create_user_command('DiagnosticInsertDisable', function()
    if winid and api.nvim_win_is_valid(winid) then
      api.nvim_win_close(winid, true)
      winid = nil
      bufnr = nil
    end
    api.nvim_del_augroup_by_id(group)
  end, {})
end

return setmetatable(ctx, diag)
