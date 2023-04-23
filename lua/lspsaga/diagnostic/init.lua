local api, fn, keymap = vim.api, vim.fn, vim.keymap.set
local config = require('lspsaga').config
local act = require('lspsaga.codeaction')
local window = require('lspsaga.window')
local util = require('lspsaga.util')
local diag_conf = config.diagnostic
local diagnostic = vim.diagnostic
local ns = api.nvim_create_namespace('DiagnosticJump')
local nvim_buf_set_keymap = api.nvim_buf_set_keymap
local nvim_buf_del_keymap = api.nvim_buf_del_keymap
local action_preview = require('lspsaga.codeaction.preview').action_preview
local preview_win_close = require('lspsaga.codeaction.preview').preview_win_close

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

local function get_num()
  local line = api.nvim_get_current_line()
  local num = line:match('%[(%d+)%]')
  if num then
    num = tonumber(num)
  end
  return num
end

---get the line or cursor diagnostics
---@param opt table
function diag:get_diagnostic(opt)
  local cur_buf = api.nvim_get_current_buf()
  if opt.buffer then
    return vim.diagnostic.get(cur_buf)
  end

  local line, col = unpack(api.nvim_win_get_cursor(0))
  local entrys = vim.diagnostic.get(cur_buf, { lnum = line - 1 })

  if opt.line then
    return entrys
  end

  if opt.cursor then
    local res = {}
    for _, v in pairs(entrys) do
      if v.col <= col and v.end_col >= col then
        res[#res + 1] = v
      end
    end
    return res
  end

  return vim.diagnostic.get()
end

function diag:get_diagnostic_sign(severity)
  local type = self:get_diag_type(severity)
  local prefix = 'DiagnosticSign'
  local sign_conf = fn.sign_getdefined(prefix .. type)
  if not sign_conf or vim.tbl_isempty(sign_conf) then
    return
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

  local win_conf = api.nvim_win_get_config(self.winid)
  local contents = {
    util.gen_truncate_line(win_conf.width),
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
          local action = self.action_tuples[num][2]
          local client = vim.lsp.get_client_by_id(self.action_tuples[num][1])
          act:do_code_action(action, client, self.enriched_ctx)
        end,
      })
    end
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
        action_preview(self.winid, self.main_buf, hi_name, tuple)
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
        action_preview(self.winid, self.main_buf, hi_name, tuple)
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

---get original lsp diagnostic
function diag:get_cursor_diagnostic()
  local diags = diag:get_diagnostic({ cursor = true })
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
  local num = get_num()
  if not num then
    return
  end

  if self.action_tuples[num] then
    act:do_code_action(num, vim.deepcopy(self.action_tuples[num]), self.enriched_ctx)
    self:close_win()
  end
  self:clean_data()
end

function diag:clean_data()
  window.nvim_close_valid_window(self.winid)
  util.delete_scroll_map(self.main_buf)
  for num, _ in pairs(self.action_tuples or {}) do
    pcall(nvim_buf_del_keymap, self.main_buf, 'n', tostring(num))
  end
  clean_ctx()
end

function diag:apply_map()
  keymap('n', diag_conf.keys.exec_action, function()
    self:do_code_action()
    self:close_win()
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

  if diag_conf.show_code_action and util.get_client_by_cap('codeActionProvider') then
    act:send_request(self.main_buf, {
      context = { diagnostics = self:get_cursor_diagnostic() },
      range = {
        start = { entry.lnum + 1, entry.col },
        ['end'] = { entry.lnum + 1, entry.col },
      },
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
      preview_win_close()
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
    util.close_preview_autocmd(current_buffer, { self.winid }, close_autocmds, function()
      preview_win_close()
      if winid == self.winid then
        self:clean_data()
      end
    end)
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
    util.jump_beacon({ entry.lnum, entry.col }, width)
    -- Open folds under the cursor
    vim.cmd('normal! zv')
  end)

  self:render_diagnostic_window(entry)
end

function diag:goto_next(opts)
  local incursor = self:get_diagnostic({ cursor = true })
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
  local incursor = self:get_diagnostic({ cursor = true })
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

return setmetatable(ctx, diag)
