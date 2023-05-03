local config = require('lspsaga').config
local act = require('lspsaga.codeaction')
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local diag_conf = config.diagnostic
local diagnostic = vim.diagnostic
local api, fn, keymap = vim.api, vim.fn, vim.keymap.set
local ns = api.nvim_create_namespace('DiagnosticJump')
local nvim_buf_set_keymap = api.nvim_buf_set_keymap
local nvim_buf_del_keymap = api.nvim_buf_del_keymap

local diag = {}

local ctx = {}

function diag.__newindex(t, k, v)
  rawset(t, k, v)
end

diag.__index = diag

--- clean ctx table data
---@private
local function clean_ctx()
  for k, _ in pairs(ctx) do
    ctx[k] = nil
  end
end

function diag:get_diagnostic_sign(severity)
  local type = self:get_diag_type(severity)
  local prefix = 'DiagnosticSign'
  local sign_conf = fn.sign_getdefined(prefix .. type)
  if not sign_conf or vim.tbl_isempty(sign_conf) then
    return type:gsub(1, 1)
  end
  local icon = (sign_conf[1] and sign_conf[1].text) and sign_conf[1].text or type:gsub(1, 1)
  return icon
end

function diag:get_diag_type(severity)
  local type = { 'Error', 'Warn', 'Info', 'Hint' }
  return type[severity]
end

local function clean_msg(msg)
  local pattern = '%(.+%)%S$'
  if msg:find(pattern) then
    return msg:gsub(pattern, '')
  end
  return msg
end

function diag:code_action_cb(hi_name)
  if not self.bufnr or not api.nvim_buf_is_loaded(self.bufnr) then
    return
  end

  if not self.action_tuples or next(self.action_tuples) == nil then
    return
  end

  local win_conf = api.nvim_win_get_config(self.winid)
  local contents = {
    libs.gen_truncate_line(win_conf.width),
    config.ui.actionfix .. 'Actions',
  }

  for index, client_with_actions in pairs(self.action_tuples) do
    if #client_with_actions ~= 2 then
      vim.notify('There is something wrong in aciton_tuples')
      return
    end
    if client_with_actions[2].title then
      local title = clean_msg(client_with_actions[2].title)
      local action_title = '[[' .. index .. ']] ' .. title
      contents[#contents + 1] = action_title
    end
  end

  local increase = window.win_height_increase(contents, math.abs(win_conf.width / vim.o.columns))

  local start_line = api.nvim_buf_line_count(self.bufnr) + 1
  api.nvim_win_set_config(self.winid, { height = win_conf.height + increase + #contents })

  api.nvim_buf_set_option(self.bufnr, 'modifiable', true)
  api.nvim_buf_set_lines(self.bufnr, -1, -1, false, contents)
  api.nvim_buf_set_option(self.bufnr, 'modifiable', false)

  api.nvim_buf_add_highlight(self.bufnr, 0, hi_name, start_line - 1, 0, -1)
  api.nvim_buf_add_highlight(self.bufnr, 0, 'ActionFix', start_line, 0, #config.ui.actionfix)

  api.nvim_buf_add_highlight(self.bufnr, 0, 'TitleString', start_line, #config.ui.actionfix, -1)

  for i = 3, #contents do
    local row = start_line + i - 2
    api.nvim_buf_add_highlight(self.bufnr, 0, 'CodeActionText', row, 6, -1)
  end

  if diag_conf.jump_num_shortcut then
    for num, _ in pairs(self.action_tuples or {}) do
      nvim_buf_set_keymap(self.main_buf, 'n', tostring(num), '', {
        noremap = true,
        nowait = true,
        callback = function()
          act:do_code_action(nil, self.action_tuples[num], self.enriched_ctx)
          self:clean_data()
        end,
      })
    end
  end

  local function get_num()
    local line = api.nvim_get_current_line()
    local num = line:match('%[(%d+)%]')
    if num then
      num = tonumber(num)
    end
    return num
  end

  api.nvim_create_autocmd('CursorMoved', {
    buffer = self.bufnr,
    callback = function()
      local curline = api.nvim_win_get_cursor(self.winid)[1]
      if curline > 3 then
        local num = get_num()
        if not num then
          return
        end
        local tuple = vim.deepcopy(self.action_tuples[num])
        self.preview_winid = act:action_preview(self.winid, self.main_buf, hi_name, tuple)
      end
    end,
    desc = 'Lspsaga show code action preview in diagnostic window',
  })

  local function scroll_with_preview(direction)
    api.nvim_win_call(self.winid, function()
      local curlnum = api.nvim_win_get_cursor(self.winid)[1]
      local lines = api.nvim_buf_line_count(self.bufnr)
      local col = 6
      if curlnum < 4 then
        curlnum = 4
      elseif curlnum >= 4 then
        curlnum = curlnum + direction > lines and 4 or curlnum + direction
      end
      api.nvim_win_set_cursor(self.winid, { curlnum, col })
      api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)
      if curlnum > 3 then
        api.nvim_buf_add_highlight(self.bufnr, ns, 'FinderSelection', curlnum - 1, 6, -1)
      end

      local num = get_num()
      if not num then
        return
      end
      local tuple = vim.deepcopy(self.action_tuples[num])
      if tuple then
        self.preview_winid = act:action_preview(self.winid, self.main_buf, hi_name, tuple)
      end
    end)
  end

  nvim_buf_set_keymap(self.main_buf, 'n', config.scroll_preview.scroll_down, '', {
    noremap = true,
    nowait = true,
    callback = function()
      scroll_with_preview(1)
    end,
  })

  nvim_buf_set_keymap(self.main_buf, 'n', config.scroll_preview.scroll_up, '', {
    noremap = true,
    nowait = true,
    callback = function()
      scroll_with_preview(-1)
    end,
  })
end

local function cursor_diagnostic()
  local diags = require('lspsaga.showdiag'):get_diagnostic({ cursor = true })
  local res = {}
  for _, entry in ipairs(diags) do
    res[#res + 1] = {
      message = entry.message,
      code = entry.code or nil,
      codeDescription = entry.codeDescription or nil,
      data = entry.data or nil,
      tags = entry.tags or nil,
      relatedInformation = entry.relatedInformation or nil,
      source = entry.source or nil,
      severity = entry.severity or nil,
      range = {
        start = {
          line = entry.lnum,
        },
        ['end'] = {
          line = entry.end_lnum,
        },
      },
    }
  end

  return res
end

function diag:do_code_action()
  local line = api.nvim_get_current_line()
  local num = line:match('%[(%d+)%]')
  if not num then
    return
  end

  num = tonumber(num)
  local action
  action = self.action_tuples[num] and vim.deepcopy(self.action_tuples[num]) or nil
  local enriched_ctx = vim.deepcopy(self.enriched_ctx)
  self:clean_data()
  if action then
    act:do_code_action(num, action, enriched_ctx)
  end
end

function diag:clean_data()
  window.nvim_close_valid_window({ self.winid, self.preview_winid })
  libs.delete_scroll_map(self.main_buf)
  for num, _ in pairs(self.action_tuples or {}) do
    pcall(nvim_buf_del_keymap, self.main_buf, 'n', tostring(num))
  end
  clean_ctx()
end

function diag:apply_map()
  keymap('n', diag_conf.keys.exec_action, function()
    self:do_code_action()
  end, { buffer = self.bufnr, nowait = true })

  keymap('n', diag_conf.keys.quit, function()
    self:clean_data()
  end, { buffer = self.bufnr, nowait = true })
end

function diag:get_diag_counts(entrys)
  --E W I W
  local counts = { 0, 0, 0, 0 }

  for _, item in ipairs(entrys) do
    counts[item.severity] = counts[item.severity] + 1
  end

  return counts
end

local function source_clean(source)
  if source == 'typescript' then
    return 'ts'
  end
  return source
end

function diag:render_diagnostic_window(entry, option)
  option = option or {}
  self.main_buf = api.nvim_get_current_buf()
  local diag_type = self:get_diag_type(entry.severity)
  local sign = self:get_diagnostic_sign(entry.severity)

  local source = ''

  if entry.source then
    source = source .. source_clean(entry.source)
  end

  if entry.code then
    source = source .. '(' .. entry.code .. ')'
  end

  local content = {}
  content = vim.split(entry.message, '\n', { trimempty = true })
  content[1] = sign .. ' ' .. content[1]
  local source_col
  if #source > 0 then
    source_col = #content[1] + 1
    content[1] = content[1] .. ' ' .. source
  end

  if diag_conf.extend_relatedInformation then
    if entry.user_data.lsp.relatedInformation and #entry.user_data.lsp.relatedInformation > 0 then
      vim.tbl_map(function(item)
        if item.location and item.location.range then
          local fname
          if item.location.uri then
            fname = fn.fnamemodify(vim.uri_to_fname(item.location.uri), ':t')
          end
          local range = '('
            .. item.location.range.start.line + 1
            .. ':'
            .. item.location.range.start.character
            .. '): '
          item.message = fname and fname .. range .. item.message or range .. item.message
        end
        content[#content + 1] = (' '):rep(3) .. item.message
      end, entry.user_data.lsp.relatedInformation)
    end
  end

  local hi_name = 'Diagnostic' .. diag_type

  if diag_conf.show_code_action and libs.get_client_by_cap('codeActionProvider') then
    local cursor_diags = cursor_diagnostic()
    act:send_code_action_request(self.main_buf, {
      context = { diagnostics = cursor_diags },
      range = {
        start = { entry.lnum + 1, entry.col },
        ['end'] = { entry.lnum + 1, entry.col },
      },
      silent = true,
    }, function(action_tuples, enriched_ctx)
      self.action_tuples = action_tuples
      self.enriched_ctx = enriched_ctx
      act:clean_context()
      self:code_action_cb(hi_name)
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

  local content_opts = {
    contents = content,
    filetype = 'markdown',
    wrap = true,
    highlight = {
      border = diag_conf.border_follow and hi_name or 'DiagnosticBorder',
      normal = 'DiagnosticNormal',
    },
  }

  local opts = {
    relative = 'cursor',
    style = 'minimal',
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
  vim.wo[self.winid].linebreak = false

  api.nvim_buf_add_highlight(self.bufnr, 0, hi_name, 0, 0, #sign)

  for i, _ in ipairs(content) do
    local start = i == 1 and #sign or 3
    api.nvim_buf_add_highlight(
      self.bufnr,
      0,
      diag_conf.text_hl_follow and hi_name or 'DiagnosticText',
      i - 1,
      start,
      -1
    )
  end

  if source_col then
    api.nvim_buf_add_highlight(self.bufnr, 0, 'DiagnosticSource', 0, source_col, -1)
  end

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
          clean_ctx()
        end
      end, 0)
    end,
  })

  self:apply_map()

  local close_autocmds = { 'CursorMoved', 'InsertEnter' }
  local winid = self.winid
  vim.defer_fn(function()
    libs.close_preview_autocmd(
      current_buffer,
      { self.winid, self.preview_winid or nil },
      close_autocmds,
      function()
        if winid == self.winid then
          self:clean_data()
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
    if entry.col == 0 then
      local text = api.nvim_buf_get_text(entry.bufnr, entry.lnum, 0, entry.lnum, -1, {})[1]
      local scol = text:find('%S')
      if scol ~= 0 then
        entry.col = scol
      end
    end

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
  local incursor = require('lspsaga.showdiag'):get_diagnostic({ cursor = true })
  local entry
  if next(incursor) ~= nil and not (self.winid and api.nvim_win_is_valid(self.winid)) then
    entry = incursor[1]
  else
    entry = diagnostic.get_next(opts)
  end
  if not entry then
    return
  end
  self:move_cursor(entry)
end

function diag:goto_prev(opts)
  local incursor = require('lspsaga.showdiag'):get_diagnostic({ cursor = true })
  local entry
  if next(incursor) ~= nil and not (self.winid and api.nvim_win_is_valid(self.winid)) then
    entry = incursor[1]
  else
    entry = diagnostic.get_prev(opts)
  end
  if not entry then
    return
  end
  self:move_cursor(entry)
end

function diag:close_exist_win()
  local has = false
  if self.winid and api.nvim_win_is_valid(self.winid) then
    has = true
    api.nvim_win_close(self.winid, true)
    act:clean_context()
  end
  clean_ctx()
  return has
end

local function on_top_right(content)
  local width = window.get_max_content_length(content)
  if width >= math.floor(vim.o.columns * 0.75) then
    width = math.floor(vim.o.columns * 0.5)
  end
  local opt = {
    relative = 'editor',
    row = 1,
    col = vim.o.columns - width,
    height = #content,
    width = width,
    focusable = false,
  }
  return opt
end

local function get_row_col(content)
  local res = {}
  local curwin = api.nvim_get_current_win()
  local max_len = window.get_max_content_length(content)
  local current_col = api.nvim_win_get_cursor(curwin)[2]
  local end_col = api.nvim_strwidth(api.nvim_get_current_line())
  local winwidth = api.nvim_win_get_width(curwin)
  if current_col < end_col then
    current_col = end_col
  end

  if winwidth - max_len > current_col + 20 then
    res.row = fn.winline() - 1
    res.col = current_col + 20
  else
    res.row = fn.winline() + 1
    res.col = current_col + 20
  end
  return res
end

local function theme_bg()
  local conf = api.nvim_get_hl_by_name('Normal', true)
  if conf.background then
    return conf.background
  end
  return 'NONE'
end

function diag:on_insert()
  local winid, bufnr

  local function max_width(content)
    local width = window.get_max_content_length(content)
    if width == vim.o.columns - 10 then
      width = vim.o.columns * 0.6
    end
    return width
  end

  local function create_window(content, buf)
    local float_opt
    if not config.diagnostic.on_insert_follow then
      float_opt = on_top_right(content)
    else
      local res = get_row_col(content)
      float_opt = {
        relative = 'win',
        win = api.nvim_get_current_win(),
        width = max_width(content),
        height = #content,
        row = res.row,
        col = res.col,
        focusable = false,
      }
    end

    return window.create_win_with_border({
      contents = content,
      bufnr = buf or nil,
      winblend = config.diagnostic.insert_winblend,
      highlight = {
        normal = 'DiagnosticInsertNormal',
      },
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
    api.nvim_win_hide(winid)
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
          hi[#hi + 1] = 'Diagnostic' .. self:get_diag_type(item.severity)
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
        bufnr, winid =
          create_window(content, (bufnr and api.nvim_buf_is_valid(bufnr)) and bufnr or nil)
        vim.bo[bufnr].modifiable = true
        vim.wo[winid].wrap = true
        if fn.has('nvim-0.9') == 1 then
          api.nvim_set_option_value('fillchars', 'lastline: ', { scope = 'local', win = winid })
        end
      end
      set_lines(content)
      if bufnr and api.nvim_buf_is_loaded(bufnr) then
        for i = 1, #hi do
          api.nvim_buf_add_highlight(bufnr, 0, hi[i], i - 1, 0, -1)
        end
      end

      api.nvim_set_hl(0, 'DiagnosticInsertNormal', {
        background = theme_bg(),
        default = true,
      })

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
        width = max_width(content),
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
