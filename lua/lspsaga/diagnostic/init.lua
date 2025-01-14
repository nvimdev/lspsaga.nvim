local api, lsp = vim.api, vim.lsp
local config = require('lspsaga').config
local act = require('lspsaga.codeaction')
local win = require('lspsaga.window')
local util = require('lspsaga.util')
local diag_conf = config.diagnostic
local ns = api.nvim_create_namespace('DiagnosticJump')
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

local function gen_float_title(counts)
  local t = {}
  local found = 0
  for i, v in ipairs(counts) do
    if v > 0 then
      found = found + 1
      local hi = 'Diagnostic' .. vim.diagnostic.severity[i]
      t[#t + 1] = { config.ui.button[1], hi }
      t[#t + 1] = {
        (vim.diagnostic.severity[i]:sub(1, 1) .. ':%s'):format(v),
        hi .. 'Reverse',
      }
      t[#t + 1] = { config.ui.button[2], hi }
    end
  end
  return found > 1 and t or nil
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
    local line_length = #api.nvim_buf_get_lines(cur_buf, line - 1, line, true)[1]
    local lnum = line - 1
    local diagnostics = vim.diagnostic.get(0, { lnum = lnum })
    return vim.tbl_filter(function(d)
      return d.lnum == lnum
        and math.min(d.col, line_length - 1) <= col
        and (d.end_col >= col or d.end_lnum > lnum)
    end, diagnostics)
  end

  return vim.diagnostic.get()
end

function diag:code_action_cb(action_tuples, enriched_ctx, win_conf)
  local contents = {}
  for index, client_with_actions in pairs(action_tuples) do
    if #client_with_actions ~= 2 then
      vim.notify('[lspsaga] failed indexing client actions')
      return
    end
    if client_with_actions[2].title then
      local action_title = '**' .. index .. '** ' .. client_with_actions[2].title
      contents[#contents + 1] = action_title
    end
  end
  local max_content_len = util.get_max_content_length(contents)
  local orig_win_width = api.nvim_win_get_width(win_conf.win)
  if max_content_len > win_conf.width and max_content_len < orig_win_width then
    win_conf.width = (max_content_len - win_conf.width) + win_conf.width
  end
  api.nvim_win_set_config(self.float_winid, win_conf)
  table.insert(contents, 1, util.gen_truncate_line(win_conf.width))
  local increase = util.win_height_increase(contents, math.abs(win_conf.width / vim.o.columns))
  local start_line = api.nvim_buf_line_count(self.float_bufnr) + 1
  local limit_height = math.floor(api.nvim_win_get_height(0) / 3)
  win
    :from_exist(self.float_bufnr, self.float_winid)
    :winsetconf({ height = math.min(win_conf.height + increase + #contents, limit_height) })
    :bufopt('modifiable', true)
    :setlines(contents, -1, -1)
    :bufopt('modifiable', false)
  api.nvim_buf_add_highlight(self.float_bufnr, 0, 'Comment', start_line - 1, 0, -1)
  local curbuf = api.nvim_get_current_buf()
  if diag_conf.jump_num_shortcut then
    for num, _ in ipairs(action_tuples or {}) do
      util.map_keys(curbuf, tostring(num), function()
        local action = action_tuples[num][2]
        local client = lsp.get_client_by_id(action_tuples[num][1])
        act:do_code_action(action, client, enriched_ctx)
        self:clean_data()
      end)
    end
    self.number_count = #action_tuples
  end
  if diag_conf.auto_preview then
    api.nvim_win_set_cursor(self.float_winid, { start_line + 1, 0 })
    api.nvim_buf_add_highlight(self.float_bufnr, ns, 'SagaSelect', start_line, 6, -1)
    action_preview(self.float_winid, curbuf, action_tuples[1])
  end
  api.nvim_create_autocmd('CursorMoved', {
    buffer = self.float_bufnr,
    callback = function()
      local curline = api.nvim_win_get_cursor(self.float_winid)[1]
      if curline >= start_line + 1 then
        api.nvim_buf_clear_namespace(self.float_bufnr, ns, 0, -1)
        local num = util.get_bold_num()
        local tuple = action_tuples[num]
        api.nvim_buf_add_highlight(self.float_bufnr, ns, 'SagaSelect', curline - 1, 6, -1)
        action_preview(self.float_winid, self.main_buf, tuple)
      end
    end,
    desc = 'Lspsaga show code action preview in diagnostic window',
  })

  local function scroll_with_preview(direction)
    api.nvim_win_call(self.float_winid, function()
      local curlnum = api.nvim_win_get_cursor(self.float_winid)[1]
      local lines = api.nvim_buf_line_count(self.float_bufnr)
      api.nvim_buf_clear_namespace(self.float_bufnr, ns, 0, -1)
      local sline = start_line + 1
      local col = 6
      if curlnum < sline then
        curlnum = sline
      elseif curlnum >= sline then
        curlnum = curlnum + direction > lines and sline or curlnum + direction
      end
      api.nvim_win_set_cursor(self.float_winid, { curlnum, col })
      if curlnum >= sline then
        api.nvim_buf_add_highlight(self.float_bufnr, ns, 'SagaSelect', curlnum - 1, 6, -1)
      end

      local tuple = action_tuples[util.get_bold_num()]
      if tuple then
        action_preview(self.float_winid, self.main_buf, tuple)
      end
    end)
  end

  util.map_keys(self.float_bufnr, diag_conf.keys.exec_action, function()
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
  local counts = { 0, 0, 0, 0 }
  for _, entry in ipairs(diags) do
    counts[entry.severity] = counts[entry.severity] + 1
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

  return res, counts
end

function diag:do_code_action(action_tuples, enriched_ctx)
  local num = util.get_bold_num()
  if not num then
    return
  end
  if action_tuples[num] then
    local action = action_tuples[num][2]
    local client = lsp.get_client_by_id(action_tuples[num][1])
    act:do_code_action(action, client, enriched_ctx)
  end
  self:clean_data()
end

function diag:clean_data()
  util.close_win(self.float_winid)
  preview_win_close()
  pcall(util.delete_scroll_map, self.main_buf)
  if self.number_count then
    for i = 1, self.number_count do
      nvim_buf_del_keymap(self.main_buf, 'n', tostring(i))
    end
  end
  clean_ctx()
end

local original_open_float = vim.diagnostic.open_float
---@diagnostic disable-next-line: duplicate-set-field
vim.diagnostic.open_float = function(opts, ...)
  diag.float_bufnr, diag.float_winid = original_open_float(opts, ...)
end

---@return boolean valid
function diag:valid_win_buf()
  if
    self.float_bufnr
    and self.float_winid
    and api.nvim_win_is_valid(self.float_winid)
    and api.nvim_buf_is_valid(self.float_bufnr)
  then
    return true
  end
  return false
end

local FORWARD, BACKWARD = 1, -1

function diag:goto_pos(pos, opts)
  local is_forward = pos == FORWARD
  local entry = (is_forward and vim.diagnostic.get_next or vim.diagnostic.get_prev)(opts)
  if not entry then
    return
  end
  (is_forward and vim.diagnostic.goto_next or vim.diagnostic.goto_prev)(vim.tbl_extend('keep', {
    float = {
      border = config.ui.border,
      format = function(diagnostic)
        if not vim.bo[api.nvim_get_current_buf()].filetype == 'rust' then
          return diagnostic.message
        end
        return diagnostic.message:find('\n`$') and diagnostic.message:gsub('\n`$', '`')
          or diagnostic.message
      end,
      header = '',
      prefix = { '• ', 'Title' },
    },
  }, opts or {}))
  util.valid_markdown_parser()
  require('lspsaga.beacon').jump_beacon({ entry.lnum, entry.col }, #api.nvim_get_current_line())
  vim.schedule(function()
    if not self:valid_win_buf() then
      return
    end
    vim.bo[self.float_bufnr].filetype = 'markdown'
    vim.wo[self.float_winid].conceallevel = 2
    vim.wo[self.float_winid].cocu = 'niv'
    vim.bo[self.float_bufnr].bufhidden = 'wipe'
    api.nvim_create_autocmd('WinClosed', {
      buffer = self.float_bufnr,
      once = true,
      callback = function()
        self:clean_data()
      end,
    })

    if #util.get_client_by_method('textDocument/codeAction') == 0 then
      return
    end
    local curbuf = api.nvim_get_current_buf()
    local diagnostics, counts = self:get_cursor_diagnostic()
    local win_conf = api.nvim_win_get_config(self.float_winid)
    win_conf.title = gen_float_title(counts)
    api.nvim_win_set_config(self.float_winid, win_conf)
    act:send_request(curbuf, {
      context = { diagnostics = diagnostics },
      range = {
        start = { entry.lnum + 1, (entry.col or 1) },
        ['end'] = { entry.lnum + 1, (entry.col or 1) },
      },
      gitsign = false,
    }, function(action_tuples, enriched_ctx)
      if #action_tuples == 0 or not self:valid_win_buf() then
        return
      end
      vim.bo[self.float_bufnr].modifiable = true
      self.main_buf = curbuf
      self:code_action_cb(action_tuples, enriched_ctx, win_conf)
      vim.bo[self.float_bufnr].modifiable = false
    end)
  end)
end

function diag:goto_next(opts)
  self:goto_pos(FORWARD, opts)
end

function diag:goto_prev(opts)
  self:goto_pos(BACKWARD, opts)
end

return setmetatable(ctx, diag)
