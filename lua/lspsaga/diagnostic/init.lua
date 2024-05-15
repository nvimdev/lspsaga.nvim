local api, fn = vim.api, vim.fn
local config = require('lspsaga').config
local act = require('lspsaga.codeaction')
local win = require('lspsaga.window')
local util = require('lspsaga.util')
local diag_conf = config.diagnostic
local diagnostic = vim.diagnostic
local ns = api.nvim_create_namespace('DiagnosticJump')
local jump_beacon = require('lspsaga.beacon').jump_beacon
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
  return line:match('%[(%d+)%]')
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
      if v.col <= col and (v.end_col and v.end_col > col or true) then
        res[#res + 1] = v
      end
    end
    return res
  end

  return vim.diagnostic.get()
end

local function clean_msg(msg)
  local pattern = '%(.+%)%S$'
  if msg:find(pattern) then
    return msg:gsub(pattern, '')
  end
  return msg
end

function diag:code_action_cb(action_tuples, enriched_ctx)
  if not self.bufnr or not api.nvim_buf_is_loaded(self.bufnr) then
    return
  end

  local win_conf = api.nvim_win_get_config(self.winid)
  local contents = {
    util.gen_truncate_line(win_conf.width),
    config.ui.actionfix .. 'Actions',
  }

  for index, client_with_actions in pairs(action_tuples) do
    if #client_with_actions ~= 2 then
      vim.notify('[lspsaga] failed indexing client actions')
      return
    end
    if client_with_actions[2].title then
      local title = clean_msg(client_with_actions[2].title)
      local action_title = '[[' .. index .. ']] ' .. title
      contents[#contents + 1] = action_title
    end
  end
  local increase = util.win_height_increase(contents, math.abs(win_conf.width / vim.o.columns))
  local start_line = api.nvim_buf_line_count(self.bufnr) + 1
  local limit_height = math.floor(api.nvim_win_get_height(0) / 3)
  win
    :from_exist(self.bufnr, self.winid)
    :winsetconf({ height = math.min(win_conf.height + increase + #contents, limit_height) })
    :bufopt('modifiable', true)
    :setlines(contents, -1, -1)
    :bufopt('modifiable', false)

  api.nvim_buf_add_highlight(self.bufnr, 0, 'Comment', start_line - 1, 0, -1)
  api.nvim_buf_add_highlight(self.bufnr, 0, 'ActionFix', start_line, 0, #config.ui.actionfix)
  api.nvim_buf_add_highlight(self.bufnr, 0, 'SagaTitle', start_line, #config.ui.actionfix, -1)

  for i = 3, #contents do
    local row = start_line + i - 2
    api.nvim_buf_add_highlight(self.bufnr, 0, 'CodeActionText', row, 6, -1)
  end

  if diag_conf.jump_num_shortcut then
    for num, _ in ipairs(action_tuples or {}) do
      util.map_keys(self.main_buf, tostring(num), function()
        local action = action_tuples[num][2]
        local client = vim.lsp.get_client_by_id(action_tuples[num][1])
        act:do_code_action(action, client, enriched_ctx)
        self:clean_data()
      end)
    end
    self.number_count = #action_tuples
  end
  api.nvim_win_set_cursor(self.winid, { start_line + 2, 0 })
  api.nvim_buf_add_highlight(self.bufnr, ns, 'SagaSelect', start_line + 1, 6, -1)
  action_preview(self.winid, self.main_buf, action_tuples[1])
  api.nvim_create_autocmd('CursorMoved', {
    buffer = self.bufnr,
    callback = function()
      local curline = api.nvim_win_get_cursor(self.winid)[1]
      if curline > 4 then
        local tuple = action_tuples[tonumber(get_num())]
        action_preview(self.winid, self.main_buf, tuple)
      end
    end,
    desc = 'Lspsaga show code action preview in diagnostic window',
  })

  local function scroll_with_preview(direction)
    api.nvim_win_call(self.winid, function()
      local curlnum = api.nvim_win_get_cursor(self.winid)[1]
      local lines = api.nvim_buf_line_count(self.bufnr)
      api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)
      local sline = start_line + 2
      local col = 6
      if curlnum < sline then
        curlnum = sline
      elseif curlnum >= sline then
        curlnum = curlnum + direction > lines and sline or curlnum + direction
      end
      api.nvim_win_set_cursor(self.winid, { curlnum, col })
      if curlnum >= sline then
        api.nvim_buf_add_highlight(self.bufnr, ns, 'SagaSelect', curlnum - 1, 6, -1)
      end

      local tuple = action_tuples[tonumber(get_num())]
      if tuple then
        action_preview(self.winid, self.main_buf, tuple)
      end
    end)
  end

  util.map_keys(self.bufnr, diag_conf.keys.exec_action, function()
    self:close_win()
    self:do_code_action(action_tuples, enriched_ctx)
  end)

  util.map_keys(self.main_buf, config.scroll_preview.scroll_down, function()
    scroll_with_preview(1)
  end)

  util.map_keys(self.main_buf, config.scroll_preview.scroll_up, function()
    scroll_with_preview(-1)
  end)
end

---get original lsp diagnostic
function diag:get_cursor_diagnostic()
  local diags = diag:get_diagnostic({ cursor = true })
  local res = {}
  for _, entry in ipairs(diags) do
    res[#res + 1] = {
      code = entry.code or nil,
      message = entry.message,
      codeDescription = entry.codeDescription
        or vim.tbl_get(entry, 'user_data', 'lsp', 'codeDescription'),
      data = vim.tbl_get(entry, 'user_data', 'lsp', 'data'),
      tags = entry.tags or nil,
      relatedInformation = vim.tbl_get(entry, 'user_data', 'lsp.relatedInformation'),
      source = entry.source or nil,
      severity = entry.severity or nil,
      range = {
        start = {
          line = entry.lnum,
          character = entry.col,
        },
        ['end'] = {
          line = entry.end_lnum,
          character = entry.end_col,
        },
      },
    }
  end

  return res
end

function diag:do_code_action(action_tuples, enriched_ctx)
  local num = get_num()
  if not num then
    return
  end

  if action_tuples[num] then
    act:do_code_action(num, action_tuples[num], enriched_ctx)
    self:close_win()
  end
  self:clean_data()
end

function diag:clean_data()
  util.close_win(self.winid)
  pcall(util.delete_scroll_map, self.main_buf)
  if self.number_count then
    for i = 1, self.number_count do
      nvim_buf_del_keymap(self.main_buf, 'n', tostring(i))
    end
  end
  clean_ctx()
end

function diag:get_diag_counts(entrys)
  --E W I W
  local counts = { 0, 0, 0, 0 }

  for _, item in ipairs(entrys) do
    counts[item.severity] = counts[item.severity] + 1
  end

  return counts
end

function diag:render_diagnostic_window(entry, option)
  option = option or {}
  self.main_buf = api.nvim_get_current_buf()
  local hi_name = 'Diagnostic' .. vim.diagnostic.severity[entry.severity]
  local content = vim.split(entry.message, '\n', { trimempty = true })

  if diag_conf.extend_relatedInformation then
    local relatedInformation = vim.tbl_get(entry, 'user_data', 'lsp', 'relatedInformation')
    if relatedInformation and #relatedInformation > 0 then
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
          content[#content + 1] = fname and fname .. range .. item.message or range .. item.message
        end
      end, entry.user_data.lsp.relatedInformation)
    end
  end

  if diag_conf.show_code_action and #util.get_client_by_method('textDocument/codeAction') > 0 then
    act:send_request(self.main_buf, {
      context = { diagnostics = self:get_cursor_diagnostic() },
      range = {
        start = { entry.lnum + 1, (entry.col or 1) },
        ['end'] = { entry.lnum + 1, (entry.col or 1) },
      },
      gitsign = false,
    }, function(action_tuples, enriched_ctx)
      if #action_tuples == 0 then
        return
      end
      self:code_action_cb(action_tuples, enriched_ctx)
    end)
  end

  local virt = {}
  if entry.source then
    virt[#virt + 1] = { entry.source, 'Comment' }
  end
  if entry.code then
    virt[#virt + 1] = { ' ' .. entry.code, 'Comment' }
  end

  local max_width = math.floor(vim.o.columns * diag_conf.max_width)
  local max_len = util.get_max_content_length(content)
    + (entry.source and #entry.source or 0)
    + (entry.code and #tostring(entry.code) or 0)
    + 2

  local increase = util.win_height_increase(content, diag_conf.max_width)

  local float_opt = {
    relative = 'cursor',
    width = math.min(max_width, max_len),
    height = #content + increase,
    focusable = true,
  }

  if config.ui.title then
    float_opt.title = { { vim.diagnostic.severity[entry.severity], hi_name } }
  end

  self.bufnr, self.winid = win
    :new_float(float_opt)
    :setlines(content)
    :bufopt({
      ['filetype'] = 'markdown',
      ['modifiable'] = false,
      ['bufhidden'] = 'wipe',
      ['buftype'] = 'nofile',
    })
    :winopt({
      ['conceallevel'] = 2,
      ['concealcursor'] = 'niv',
      ['showbreak'] = 'NONE',
      ['breakindent'] = true,
      ['breakindentopt'] = 'shift:0',
      ['linebreak'] = false,
    })
    :winhl('DiagnosticNormal', diag_conf.border_follow and hi_name or 'DiagnosticBorder')
    :wininfo()

  api.nvim_buf_set_extmark(self.bufnr, ns, #content - 1, 0, {
    virt_text = virt,
    hl_mode = 'combine',
  })

  for i, _ in ipairs(content) do
    api.nvim_buf_add_highlight(
      self.bufnr,
      0,
      diag_conf.text_hl_follow and hi_name or 'DiagnosticText',
      i - 1,
      0,
      -1
    )
  end

  api.nvim_create_autocmd('BufLeave', {
    buffer = self.bufnr,
    once = true,
    callback = function()
      preview_win_close()
    end,
  })

  api.nvim_create_autocmd('BufLeave', {
    buffer = self.main_buf,
    once = true,
    callback = function()
      vim.defer_fn(function()
        local cur = api.nvim_get_current_buf()
        if
          cur ~= self.main_buf
          and cur ~= self.bufnr
          and self.bufnr
          and api.nvim_buf_is_loaded(self.bufnr)
        then
          api.nvim_win_close(self.winid, true)
          clean_ctx()
        end
        preview_win_close()
      end, 0)
    end,
  })

  util.map_keys(self.bufnr, diag_conf.keys.quit, function()
    self:clean_data()
  end)

  local close_autocmds = { 'CursorMoved', 'InsertEnter' }
  vim.defer_fn(function()
    self.auid = api.nvim_create_autocmd(close_autocmds, {
      buffer = self.main_buf,
      once = true,
      callback = function(args)
        preview_win_close()
        util.close_win(self.winid)
        self:clean_data()
        api.nvim_del_autocmd(args.id)
      end,
    })
  end, 0)
end

function diag:move_cursor(entry)
  local current_winid = api.nvim_get_current_win()
  if self.winid and api.nvim_win_is_valid(self.winid) then
    api.nvim_win_close(self.winid, true)
    preview_win_close()
    pcall(api.nvim_del_autocmd, self.auid)
  end

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

    api.nvim_win_set_cursor(current_winid, { entry.lnum + 1, (entry.col or 1) })
    local width = entry.end_col - (entry.col or 1)
    if width <= 0 then
      width = #api.nvim_get_current_line()
    end
    jump_beacon({ entry.lnum, entry.col or entry.end_col }, width)
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
