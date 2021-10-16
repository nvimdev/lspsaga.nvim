local M = {}

M.methods = {
  code_action = "textDocument/codeAction",
}

M.diagnostics_line = function(bufnr, winid)
  vim.diagnostic.get(bufnr, { lnum = vim.api.nvim_win_get_cursor(winid)[1] - 1 })
end

M.code_action_request = function(args)
  local winid, bufnr = (args.winid or vim.api.nvim_get_current_win()), vim.api.nvim_get_current_buf()
  args.params.context = args.context or { diagnostics = M.diagnostics_line(bufnr, winid) }
  local callback = args.callback { bufnr = bufnr, method = M.methods.code_action, params = args.params }
  vim.lsp.buf_request_all(bufnr, M.methods.code_action, args.params, callback)
end

local execute = function(client, action, ctx)
  if action.edit then
    vim.lsp.util.apply_workspace_edit(action.edit)
  end

  if action.command then
    local command = type(action.command) == "table" and action.command or action
    local fn = vim.lsp.commands[command.command]
    if fn then
      local enriched_ctx = vim.deepcopy(ctx)
      enriched_ctx.client_id = client.id
      fn(command, ctx)
    else
      vim.lsp.buf.execute_command(command)
    end
  end
end

M.code_action_execute = function(client_id, action, ctx)
  local client = vim.lsp.get_client_by_id(client_id)
  if
    not action.edit
    and client
    and type(client.resolved_capabilities.code_action) == "table"
    and client.resolved_capabilities.code_action.resolveProvider
  then
    client.request("codeAction/resolve", action, function(err, resolved_action)
      if err then
        vim.notify(err.code .. ": " .. err.message, vim.log.levels.ERROR)
        return
      end
      execute(client, resolved_action, ctx)
    end)
  else
    execute(client, action, ctx)
  end
end

return M
