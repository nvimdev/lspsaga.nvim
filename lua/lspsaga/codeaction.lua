local wrap = require "lspsaga.wrap"
local libs = require "lspsaga.libs"
local window = require "lspsaga.codeaction.window"
local api = require "lspsaga.api"
local M = {}

local on_code_action_response = function(ctx)
  window.bufnr = vim.fn.bufnr()
  window.ctx = ctx
  window.content, window.actions = { window.title }, {}

  return function(response)
    for client_id, result in pairs(response or {}) do
      for index, action in ipairs(result.result or {}) do
        table.insert(window.actions, { client_id, action })
        table.insert(window.content, "[" .. index .. "]" .. " " .. action.title)
      end
    end

    if #window.actions == 0 or #window.content == 1 then
      vim.notify("No code actions available", vim.log.levels.INFO)
      return
    end

    table.insert(window.content, 2, wrap.add_truncate_line(window.content))

    window.open {
      contents = window.content,
      filetype = "LspSagaCodeAction",
      enter = true,
      highlight = "LspSagaCodeActionBorder",
    }
  end
end

M.range_code_action = function(context, start_pos, end_pos)
  local active, msg = libs.check_lsp_active()
  if not active then
    print(msg)
    return
  end
  api.code_action_request {
    params = vim.lsp.util.make_given_range_params(start_pos, end_pos),
    context = context,
    callback = on_code_action_response,
  }
end

M.code_action = function()
  local active, _ = libs.check_lsp_active()
  if not active then
    return
  end
  api.code_action_request {
    params = vim.lsp.util.make_range_params(),
    callback = on_code_action_response,
  }
end

return M
