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

local function get_num()
  local line = api.nvim_get_current_line()
  return line:match('%*%*(%d+)%*%*')
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

function diag:code_action_cb(action_tuples, enriched_ctx)
  local win_conf = api.nvim_win_get_config(self.float_winid)
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
      local action_title = '**' .. index .. '** ' .. client_with_actions[2].title
      contents[#contents + 1] = action_title
    end
  end
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
  api.nvim_buf_add_highlight(self.float_bufnr, 0, 'ActionFix', start_line, 0, #config.ui.actionfix)
  api.nvim_buf_add_highlight(self.float_bufnr, 0, 'SagaTitle', start_line, #config.ui.actionfix, -1)

  for i = 3, #contents do
    local row = start_line + i - 2
    api.nvim_buf_add_highlight(self.float_bufnr, 0, 'CodeActionText', row, 6, -1)
  end
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
  api.nvim_win_set_cursor(self.float_winid, { start_line + 2, 0 })
  api.nvim_buf_add_highlight(self.float_bufnr, ns, 'SagaSelect', start_line + 1, 6, -1)
  action_preview(self.float_winid, curbuf, action_tuples[1])
  api.nvim_create_autocmd('CursorMoved', {
    buffer = self.float_bufnr,
    callback = function()
      local curline = api.nvim_win_get_cursor(self.float_winid)[1]
      if curline > 4 then
        local tuple = action_tuples[tonumber(get_num())]
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
      local sline = start_line + 2
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

      local tuple = action_tuples[tonumber(get_num())]
      if tuple then
        action_preview(self.float_winid, self.main_buf, tuple)
      end
    end)
  end

  util.map_keys(self.float_bufnr, diag_conf.keys.exec_action, function()
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

function diag:get_diag_counts(entrys)
  --E W I W
  local counts = { 0, 0, 0, 0 }

  for _, item in ipairs(entrys) do
    counts[item.severity] = counts[item.severity] + 1
  end

  return counts
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

local FORWARD = 1

function diag:goto_pos(pos)
  local is_forward = pos == FORWARD
  local entry = (is_forward and vim.diagnostic.get_next or vim.diagnostic.get_prev)()
  if not entry then
    return
  end
  (is_forward and vim.diagnostic.goto_next or vim.diagnostic.goto_prev)({
    float = { border = 'rounded' },
  })
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
    act:send_request(curbuf, {
      context = { diagnostics = self:get_cursor_diagnostic() },
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
      self:code_action_cb(action_tuples, enriched_ctx)
      vim.bo[self.float_bufnr].modifiable = false
    end)
  end)
end

return setmetatable(ctx, diag)
