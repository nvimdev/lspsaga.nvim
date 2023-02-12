local api, util, fn, lsp = vim.api, vim.lsp.util, vim.fn, vim.lsp
local config = require('lspsaga').config
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local act = {}
local ctx = {}

act.__index = act
function act.__newindex(t, k, v)
  rawset(t, k, v)
end

local function clean_ctx()
  for k, _ in pairs(ctx) do
    ctx[k] = nil
  end
end

function act:action_callback()
  local contents = {}

  for index, client_with_actions in pairs(self.action_tuples) do
    local action_title = ''
    local indent = index > 9 and '' or ' '
    if #client_with_actions ~= 2 then
      vim.notify('There is something wrong in aciton_tuples')
      return
    end
    if client_with_actions[2].title then
      action_title = indent .. index .. '  ' .. client_with_actions[2].title
    end
    if config.code_action.show_server_name == true then
      local name = vim.lsp.get_client_by_id(client_with_actions[1]).name
      action_title = action_title .. '  ' .. name
    end
    table.insert(contents, action_title)
  end

  local content_opts = {
    contents = contents,
    filetype = 'sagacodeaction',
    buftype = 'nofile',
    enter = true,
    highlight = {
      normal = 'CodeActionNormal',
      border = 'CodeActionBorder',
    },
  }

  local opt = {}
  local max_height = math.floor(vim.o.lines * 0.5)
  opt.height = max_height < #contents and max_height or #contents
  local max_width = math.floor(vim.o.columns * 0.7)
  local max_len = window.get_max_content_length(contents)
  opt.width = max_len + 10 < max_width and max_len + 5 or max_width
  opt.no_size_override = true

  if fn.has('nvim-0.9') == 1 and config.ui.title then
    opt.title = {
      { config.ui.code_action .. ' CodeActions', 'TitleString' },
    }
  end

  self.action_bufnr, self.action_winid = window.create_win_with_border(content_opts, opt)
  vim.wo[self.action_winid].conceallevel = 2
  vim.wo[self.action_winid].concealcursor = 'niv'
  -- initial position in code action window
  api.nvim_win_set_cursor(self.action_winid, { 1, 1 })

  api.nvim_create_autocmd('CursorMoved', {
    buffer = self.action_bufnr,
    callback = function()
      self:set_cursor()
    end,
  })

  for i = 1, #contents, 1 do
    local row = i - 1
    api.nvim_buf_add_highlight(self.action_bufnr, -1, 'CodeActionText', row, 0, -1)
    api.nvim_buf_add_highlight(self.action_bufnr, 0, 'CodeActionNumber', row, 0, 2)
  end

  -- dsiable some move keys in codeaction
  libs.disable_move_keys(self.action_bufnr)

  self:apply_action_keys()
  if config.code_action.num_shortcut then
    self:num_shortcut(self.action_bufnr)
  end
end

local function map_keys(mode, keys, action, options)
  if type(keys) == 'string' then
    keys = { keys }
  end
  for _, key in ipairs(keys) do
    vim.keymap.set(mode, key, action, options)
  end
end

function act:apply_action_keys()
  map_keys('n', config.code_action.keys.exec, function()
    self:do_code_action()
  end, { buffer = self.action_bufnr })

  map_keys('n', config.code_action.keys.quit, function()
    self:close_action_window()
    clean_ctx()
  end, { buffer = self.action_bufnr })
end

function act:send_code_action_request(main_buf, options, cb)
  local diagnostics = lsp.diagnostic.get_line_diagnostics(main_buf)
  self.bufnr = main_buf
  local ctx_diags = { diagnostics = diagnostics }
  local params
  local mode = api.nvim_get_mode().mode
  options = options or {}
  if options.range then
    assert(type(options.range) == 'table', 'code_action range must be a table')
    local start = assert(options.range.start, 'range must have a `start` property')
    local end_ = assert(options.range['end'], 'range must have an `end` property')
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
  params.context = ctx_diags
  if not self.enriched_ctx then
    self.enriched_ctx = { bufnr = main_buf, method = 'textDocument/codeAction', params = params }
  end

  lsp.buf_request_all(main_buf, 'textDocument/codeAction', params, function(results)
    self.pending_request = false
    self.action_tuples = {}

    for client_id, result in pairs(results) do
      for _, action in pairs(result.result or {}) do
        table.insert(self.action_tuples, { client_id, action })
      end
    end

    if #self.action_tuples == 0 then
      vim.notify('No code actions available', vim.log.levels.INFO)
      return
    end

    if cb then
      cb()
    end
  end)
end

function act:set_cursor()
  local col = 4
  local current_line = api.nvim_win_get_cursor(self.action_winid)[1]

  if current_line == #self.action_tuples + 1 then
    api.nvim_win_set_cursor(self.action_winid, { 1, col })
  else
    api.nvim_win_set_cursor(self.action_winid, { current_line, col })
  end
  self:action_preview(self.action_winid, self.bufnr)
end

function act:num_shortcut(bufnr, callback)
  for num, _ in pairs(self.action_tuples or {}) do
    vim.keymap.set('n', tostring(num), function()
      if callback then
        callback()
      end
      self:do_code_action(num)
    end, { buffer = bufnr })
  end
end

function act:code_action(options)
  if self.pending_request then
    vim.notify(
      '[lspsaga.nvim] there is already a code action request please wait',
      vim.log.levels.WARN
    )
    return
  end
  self.pending_request = true
  options = options or {}

  self:send_code_action_request(api.nvim_get_current_buf(), options, function()
    self:action_callback()
  end)
end

function act:apply_action(action, client)
  if action.edit then
    util.apply_workspace_edit(action.edit, client.offset_encoding)
  end
  if action.command then
    local command = type(action.command) == 'table' and action.command or action
    local func = client.commands[command.command] or lsp.commands[command.command]
    if func then
      local enriched_ctx = vim.deepcopy(self.enriched_ctx)
      enriched_ctx.client_id = client.id
      func(command, enriched_ctx)
    else
      local params = {
        command = command.command,
        arguments = command.arguments,
        workDoneToken = command.workDoneToken,
      }
      client.request('workspace/executeCommand', params, nil, self.enriched_ctx.bufnr)
    end
  end
end

function act:do_code_action(num)
  local number
  if num then
    number = tonumber(num)
  else
    local cur_text = api.nvim_get_current_line()
    number = cur_text:match('(%d+)%s+%S')
    number = tonumber(number)
  end

  if not number then
    vim.notify('[Lspsaga] no action number choice', vim.log.levels.WARN)
    return
  end

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
  self:close_action_window()
  clean_ctx()
end

function act:get_action_diff(num, main_buf)
  local action = self.action_tuples[tonumber(num)][2]
  if not action then
    return
  end

  local client = lsp.get_client_by_id(self.action_tuples[tonumber(num)][1])
  if
    not action.edit
    and client
    and vim.tbl_get(client.server_capabilities, 'codeActionProvider', 'resolveProvider')
  then
    local results = lsp.buf_request_sync(main_buf, 'codeAction/resolve', action, 1000)
    action = results[client.id].result
    if not action then
      return
    end
  end

  if not action.edit then
    return
  end

  local all_changes = {}
  if action.edit.documentChanges then
    for _, item in pairs(action.edit.documentChanges) do
      if item.textDocument then
        if not all_changes[item.textDocument.uri] then
          all_changes[item.textDocument.uri] = {}
        end
        for _, edit in pairs(item.edits) do
          table.insert(all_changes[item.textDocument.uri], edit)
        end
      end
    end
  elseif action.edit.changes then
    all_changes = action.edit.changes
  end

  if not (all_changes and not vim.tbl_isempty(all_changes)) then
    return
  end

  local tmp_buf = api.nvim_create_buf(false, false)
  vim.bo[tmp_buf].bufhidden = 'wipe'
  local lines = api.nvim_buf_get_lines(main_buf, 0, -1, false)
  api.nvim_buf_set_lines(tmp_buf, 0, -1, false, lines)

  for _, changes in pairs(all_changes) do
    util.apply_text_edits(changes, tmp_buf, client.offset_encoding)
  end
  local data = api.nvim_buf_get_lines(tmp_buf, 0, -1, false)
  api.nvim_buf_delete(tmp_buf, { force = true })
  local diff = vim.diff(table.concat(lines, '\n') .. '\n', table.concat(data, '\n') .. '\n')
  return diff
end

function act:action_preview(main_winid, main_buf)
  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    api.nvim_win_close(self.preview_winid, true)
    self.preview_winid = nil
  end
  local line = api.nvim_get_current_line()
  local num = line:match('(%d+)%s+%S')
  if not num then
    return
  end

  local tbl = self:get_action_diff(num, main_buf)
  if not tbl or #tbl == 0 then
    return
  end

  tbl = vim.split(tbl, '\n')
  table.remove(tbl, 1)

  local win_conf = api.nvim_win_get_config(main_winid)
  local opt = {}
  opt.relative = 'editor'
  local max_height = math.floor(vim.o.lines * 0.4)
  opt.height = #tbl > max_height and max_height or #tbl

  if win_conf.anchor:find('^N') then
    if win_conf.row[false] - opt.height > 0 then
      opt.row = win_conf.row[false]
      opt.anchor = win_conf.anchor:gsub('N', 'S')
    else
      opt.row = win_conf.row[false] + win_conf.height + 2
      if #vim.wo[fn.bufwinid(main_buf)].winbar > 0 then
        opt.row = opt.row + 1
      end
      opt.anchor = win_conf.anchor
    end
  else
    if win_conf.row[false] - win_conf.height - opt.height - 4 > 0 then
      opt.row = win_conf.row[false] - win_conf.height - 2
      opt.anchor = win_conf.anchor
    else
      opt.row = win_conf.row[false]
      opt.anchor = win_conf.anchor:gsub('S', 'N')
    end
  end
  opt.col = win_conf.col[false]

  local max_width = math.floor(vim.o.columns * 0.6)
  if max_width < win_conf.width then
    max_width = win_conf.width
  end

  opt.width = max_width
  opt.no_size_override = true

  if fn.has('nvim-0.9') == 1 and config.ui.title then
    opt.title = { { 'Action Preview', 'ActionPreviewTitle' } }
  end

  local content_opts = {
    contents = tbl,
    filetype = 'diff',
    bufhidden = 'wipe',
    highlight = {
      normal = 'ActionPreviewNormal',
      border = 'ActionPreviewBorder',
    },
  }

  local preview_buf
  preview_buf, self.preview_winid = window.create_win_with_border(content_opts, opt)
  vim.bo[preview_buf].syntax = 'on'
  return self.preview_winid
end

function act:close_action_window()
  if self.action_winid and api.nvim_win_is_valid(self.action_winid) then
    api.nvim_win_close(self.action_winid, true)
  end
  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    api.nvim_win_close(self.preview_winid, true)
  end
end

function act:clean_context()
  clean_ctx()
end

return setmetatable(ctx, act)
