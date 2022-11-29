local api, util, fn, lsp = vim.api, vim.lsp.util, vim.fn, vim.lsp
local window = require('lspsaga.window')
local config = require('lspsaga').config_values
local libs = require('lspsaga.libs')
local method = 'textDocument/codeAction'
local saga_augroup = require('lspsaga').saga_augroup

local Action = {}
Action.__index = Action

function Action:action_callback()
  local contents = {}

  for index, client_with_actions in pairs(self.action_tuples) do
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

  if #contents == 1 then
    return
  end

  local content_opts = {
    contents = contents,
    filetype = 'sagacodeaction',
    enter = true,
    highlight = 'LspSagaCodeActionBorder',
  }

  local opt = {}

  if fn.has('nvim-0.9') == 1 then
    opt.title = config.code_action_icon .. 'CodeAction'
  end

  self.action_bufnr, self.action_winid = window.create_win_with_border(content_opts, opt)
  -- initial position in code action window
  api.nvim_win_set_cursor(self.action_winid, { 1, 1 })
  api.nvim_create_autocmd('CursorMoved', {
    group = saga_augroup,
    buffer = self.action_bufnr,
    callback = function()
      self:set_cursor()
    end,
  })

  api.nvim_create_autocmd('QuitPre', {
    group = saga_augroup,
    buffer = self.action_bufnr,
    callback = function()
      self:quit_action_window()
    end,
  })

  api.nvim_buf_add_highlight(self.action_bufnr, -1, 'LspSagaCodeActionTitle', 0, 0, -1)
  api.nvim_buf_add_highlight(self.action_bufnr, -1, 'LspSagaCodeActionTrunCateLine', 1, 0, -1)
  for i = 1, #contents - 2, 1 do
    api.nvim_buf_add_highlight(self.action_bufnr, -1, 'LspSagaCodeActionContent', 1 + i, 0, -1)
  end
  -- dsiable some move keys in codeaction
  libs.disable_move_keys(self.action_bufnr)

  self:apply_action_keys()
  if config.code_action_num_shortcut then
    self:num_shortcut()
  end
end

function Action:apply_action_keys()
  vim.keymap.set('n', config.code_action_keys.exec, function()
    self:do_code_action()
  end, { buffer = self.action_bufnr })

  vim.keymap.set('n', config.code_action_keys.quit, function()
    self:quit_action_window()
  end, { buffer = self.action_bufnr })

  local move = config.move_in_saga
  local opts = { noremap = true, silent = true, nowait = true }
  api.nvim_buf_set_keymap(self.action_bufnr, 'n', move.prev, '<Up>', opts)
  api.nvim_buf_set_keymap(self.action_bufnr, 'n', move.next, '<Down>', opts)
end

function Action:get_clients(results, options)
  local function action_filter(a)
    -- filter by specified action kind
    if options and options.context and options.context.only then
      if not a.kind then
        return false
      end
      local found = false
      for _, o in ipairs(options.context.only) do
        -- action kinds are hierarchical with . as a separator: when requesting only
        -- 'quickfix' this filter allows both 'quickfix' and 'quickfix.foo', for example
        if a.kind:find('^' .. o .. '$') or a.kind:find('^' .. o .. '%.') then
          found = true
          break
        end
      end
      if not found then
        return false
      end
    end
    -- filter by user function
    if options and options.filter and not options.filter(a) then
      return false
    end
    -- no filter removed this action
    return true
  end

  if self.action_tuples == nil then
    self.action_tuples = {}
  end

  for client_id, result in pairs(results) do
    for _, action in pairs(result.result or {}) do
      if action_filter(action) then
        table.insert(self.action_tuples, { client_id, action })
      end
    end
  end
end

local function check_sub_tbl(tbl)
  for _, t in pairs(tbl) do
    if type(t[1]) ~= 'number' then
      return false
    end

    if type(t[2]) ~= 'table' or next(t[2]) == nil then
      return false
    end
  end
  return true
end

function Action:actions_in_cache()
  if not config.code_action_lightbulb.enable then
    return false
  end

  if not config.code_action_lightbulb.cache_code_action then
    return false
  end

  if
    self.action_tuples
    and next(self.action_tuples) ~= nil
    and check_sub_tbl(self.action_tuples)
  then
    return true
  end
end

function Action:send_code_action_request(options, cb)
  local diagnostics = lsp.diagnostic.get_line_diagnostics(self.bufnr)
  local context = { diagnostics = diagnostics }
  local params
  local mode = api.nvim_get_mode().mode
  options = options or {}
  if options.range then
    assert(type(options.range) == 'table', 'code_action range must be a table')
    local start = assert(options.range.start, 'range must have a `start` property')
    local end_ = assert(options.range['end'], 'range must have a `end` property')
    params = util.make_given_range_params(start, end_)
  elseif mode == 'v' or mode == 'V' then
    -- [bufnum, lnum, col, off]; both row and column 1-indexed
    local start = fn.getpos('v')
    local end_ = fn.getpos('.')
    local start_row = start[2]
    local start_col = start[3]
    local end_row = end_[2]
    local end_col = end_[3]

    -- A user can start visual selection at the end and move backwards
    -- Normalize the range to start < end
    if start_row == end_row and end_col < start_col then
      end_col, start_col = start_col, end_col
    elseif end_row < start_row then
      start_row, end_row = end_row, start_row
      start_col, end_col = end_col, start_col
    end
    params = util.make_given_range_params({ start_row, start_col - 1 }, { end_row, end_col - 1 })
  else
    params = util.make_range_params()
  end
  params.context = context
  if self.ctx == nil then
    self.ctx = {}
  end
  self.ctx = { bufnr = self.bufnr, method = method, params = params }

  lsp.buf_request_all(self.bufnr, method, params, function(results)
    self:get_clients(results)
    if #self.action_tuples == 0 then
      vim.notify('No code actions available', vim.log.levels.INFO)
      return
    end
    if cb then
      cb()
    end
  end)
end

function Action:set_cursor()
  local col = 1
  local current_line = api.nvim_win_get_cursor(self.action_winid)[1]

  if current_line == #self.action_tuples + 1 then
    api.nvim_win_set_cursor(self.action_winid, { 1, col })
  else
    api.nvim_win_set_cursor(self.action_winid, { current_line, col })
  end
  self:action_preview(self.action_winid, self.bufnr)
end

function Action:num_shortcut()
  for num, _ in pairs(self.action_tuples) do
    vim.keymap.set('n', tostring(num), function()
      self:do_code_action(num)
    end, { buffer = self.action_bufnr })
  end
end

function Action:code_action(options)
  self.bufnr = api.nvim_get_current_buf()

  options = options or {}
  self:send_code_action_request(options, function()
    self:action_callback()
  end)
end

function Action:apply_action(action, client)
  if action.edit then
    util.apply_workspace_edit(action.edit, client.offset_encoding)
  end
  if action.command then
    local command = type(action.command) == 'table' and action.command or action
    local func = client.commands[command.command] or lsp.commands[command.command]
    if func then
      local enriched_ctx = vim.deepcopy(self.ctx)
      enriched_ctx.client_id = client.id
      fn(command, enriched_ctx)
    else
      local params = {
        command = command.command,
        arguments = command.arguments,
        workDoneToken = command.workDoneToken,
      }
      client.request('workspace/executeCommand', params, nil, self.ctx.bufnr)
    end
  end
end

function Action:do_code_action(num)
  local number = num and tonumber(num) or tonumber(vim.fn.expand('<cword>'))
  local action = self.action_tuples[number][2]
  local client = lsp.get_client_by_id(self.action_tuples[number][1])

  if
    not action.edit
    and client
    and vim.tbl_get(client.server_capabilities, 'codeActionProvider', 'resolveProvider')
  then
    client.request('codeAction/resolve', action, function(err, resolved_action)
      if err then
        vim.notify(err.code .. ': ' .. err.message, vim.log.levels.ERROR)
        return
      end
      self:apply_action(resolved_action, client)
    end)
  else
    self:apply_action(action, client)
  end
  self:quit_action_window()
end

function Action:get_action_diff(num, main_buf)
  local action = self.action_tuples[tonumber(num)][2]
  if not action then
    return
  end

  local old_lines = {}

  local new_lines = ''

  if action.edit then
    local key = vim.tbl_keys(action.edit.changes)
    local schema = key[1]
    local text_edits = action.edit.changes[schema]
    for _, v in pairs(text_edits) do
      local start = v.range.start.line
      local _end = v.range['end'].line + 1
      new_lines = new_lines .. (start + 1) .. ' ' .. v.newText
      table.insert(
        old_lines,
        (start + 1) .. ' ' .. api.nvim_buf_get_lines(main_buf, start, _end, false)[1] .. '\n'
      )
    end
    return vim.diff(table.concat(old_lines, '') .. '\n', new_lines .. '\n')
  end
end

function Action:action_preview(main_winid, main_buf)
  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    api.nvim_win_close(self.preview_winid, true)
    self.preview_winid = nil
  end
  local line = api.nvim_get_current_line()
  local num = line:match('%[([1-9])%]')
  if not num then
    return
  end

  local tbl = self:get_action_diff(num, main_buf)
  if not tbl then
    return
  end

  tbl = vim.split(tbl, '\n')
  table.remove(tbl, 1)

  local win_conf = api.nvim_win_get_config(main_winid)
  local col_start = win_conf.col[false] - win_conf['col'][true]
  local win_width, _ = vim.lsp.util._make_floating_popup_size(tbl)
  local opt = {}
  opt.relative = 'editor'
  if col_start + win_conf.width + win_width >= vim.o.columns then
    opt.row = win_conf.anchor:find('^N') and win_conf.row[false] + #tbl + win_conf.height
      or win_conf.row[false] - win_conf.height - 2
    opt.col = win_conf.col[false]
    opt.anchor = win_conf.anchor
    opt.width = win_conf.width
    opt.height = #tbl
    opt.no_size_override = true
  else
    opt.row = win_conf.row[false] + 2
    opt.col = win_conf.col[false] + win_conf.width + 2
  end

  if fn.has('nvim-0.9') == 1 then
    opt.title = { { 'Action Preivew', 'DiagnosticActionPtitle' } }
  end

  local content_opts = {
    contents = tbl,
    filetype = 'diff',
    highlight = 'DiagnosticActionPborder',
  }

  local preview_buf
  preview_buf, self.preview_winid = window.create_win_with_border(content_opts, opt)
  vim.bo[preview_buf].syntax = 'on'
  return self.preview_winid
end

function Action:clear_tmp_data()
  for k, v in pairs(self) do
    if type(v) ~= 'function' then
      self[k] = nil
    end
  end
end

function Action:quit_action_window()
  if self.action_bufnr == 0 and self.action_winid == 0 then
    return
  end
  window.nvim_close_valid_window({ self.action_winid, self.preview_winid })
  self:clear_tmp_data()
end

return Action
