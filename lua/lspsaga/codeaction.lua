local api = vim.api
local window = require('lspsaga.window')
local config = require('lspsaga').config_values
local wrap = require('lspsaga.wrap')
local libs = require('lspsaga.libs')
local method = 'textDocument/codeAction'
local saga_augroup = require('lspsaga').saga_augroup

local Action = {}
Action.__index = Action

function Action:action_callback()
  local contents = {}
  local title = config['code_action_icon'] .. 'CodeActions:'
  table.insert(contents, title)

  local index = 0
  for _, client_with_actions in pairs(self.action_tuples) do
    local action_title = ''
    if #client_with_actions ~= 2 then
      vim.notify('There has somethint wrong in aciton_tuples')
      return
    end
    index = index + 1
    if client_with_actions[2].title then
      action_title = '[' .. index .. ']' .. ' ' .. client_with_actions[2].title
      if self.actions == nil then
        self.actions = {}
      end
      self.actions[index] = client_with_actions
    end
    table.insert(contents, action_title)
  end

  if #contents == 1 then
    return
  end

  -- insert blank line
  local truncate_line = wrap.add_truncate_line(contents)
  table.insert(contents, 2, truncate_line)

  local content_opts = {
    contents = contents,
    filetype = 'sagacodeaction',
    enter = true,
    highlight = 'LspSagaCodeActionBorder',
  }

  self.action_bufnr, self.action_winid = window.create_win_with_border(content_opts)
  -- initial position in code action window
  api.nvim_win_set_cursor(self.action_winid, { 3, 1 })
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
  if #self.action_tuples == 0 then
    vim.notify('No code actions available', vim.log.levels.INFO)
    return
  end
end

function Action:actions_in_cache()
  if not config.code_action_lightbulb.enable then
    return false
  end

  if self.action_tuples and next(self.action_tuples) ~= nil then
    return true
  end
end

function Action:code_action()
  local in_cache = self:actions_in_cache()
  if in_cache then
    self:action_callback()
    return
  end

  self.bufnr = api.nvim_get_current_buf()
  local diagnostics = vim.lsp.diagnostic.get_line_diagnostics(self.bufnr)
  local context = { diagnostics = diagnostics }
  local params = vim.lsp.util.make_range_params()
  params.context = context
  if self.ctx == nil then
    self.ctx = {}
  end
  self.ctx = { bufnr = self.bufnr, method = method, params = params }

  vim.lsp.buf_request_all(self.bufnr, method, params, function(results)
    self:get_clients(results)
    self:action_callback()
  end)
end

function Action:range_code_action(context, start_pos, end_pos)
  local in_cache = self:actions_in_cache()
  if in_cache then
    self:action_callback()
    return
  end

  self.bufnr = api.nvim_get_current_buf()
  vim.validate({ context = { context, 't', true } })
  context = context or { diagnostics = vim.lsp.diagnostic.get_line_diagnostics(self.bufnr) }
  local params = vim.lsp.util.make_given_range_params(start_pos, end_pos)
  params.context = context
  if self.ctx == nil then
    self.ctx = {}
  end
  self.ctx = { bufnr = self.bufnr, method = method, params = params }

  vim.lsp.buf_request_all(self.bufnr, method, params, function(results)
    self:get_clients(results)
    self:action_callback()
  end)
end

function Action:set_cursor()
  local col = 1
  local current_line = api.nvim_win_get_cursor(self.action_winid)[1]

  if current_line == 1 then
    api.nvim_win_set_cursor(self.action_winid, { 3, col })
  elseif current_line == 2 then
    api.nvim_win_set_cursor(self.action_winid, { 2 + #self.actions, col })
  elseif current_line == #self.actions + 3 then
    api.nvim_win_set_cursor(self.action_winid, { 3, col })
  end
end

function Action:num_shortcut()
  for num, _ in pairs(self.actions) do
    vim.keymap.set('n', tostring(num), function()
      self:do_code_action(num)
    end, { buffer = self.action_bufnr })
  end
end

function Action:apply_action(action, client)
  if action.edit then
    vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
  end
  if action.command then
    local command = type(action.command) == 'table' and action.command or action
    local fn = client.commands[command.command] or vim.lsp.commands[command.command]
    if fn then
      local enriched_ctx = vim.deepcopy(self.ctx)
      enriched_ctx.client_id = client.id
      fn(command, enriched_ctx)
    else
      -- Not using command directly to exclude extra properties,
      -- see https://github.com/python-lsp/python-lsp-server/issues/146
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
  local action = self.actions[number][2]
  local client = vim.lsp.get_client_by_id(self.actions[number][1])

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

function Action:clear_tmp_data()
  self.actions = {}
  self.bufnr = 0
  self.action_bufnr = 0
  self.action_winid = 0
  self.action_tuples = {}
  self.ctx = {}
end

function Action:quit_action_window()
  if self.action_bufnr == 0 and self.action_winid == 0 then
    return
  end
  window.nvim_close_valid_window(self.action_winid)
  self:clear_tmp_data()
end

return Action
