local lib = require 'lspsaga.libs'
local lsp = vim.lsp
local M = {}

function M.lsp_before_save()
  local defs = {}
  local ext = vim.fn.expand('%:e')
  table.insert(defs,{"BufWritePre", '*.'..ext ,
                    "lua vim.lsp.buf.formatting_sync(nil,1000)"})
  if ext == 'go' then
    table.insert(defs,{"BufWritePre","*.go",
            "lua require('lspsaga.action').go_organize_imports_sync(1000)"})
  end
  lib.nvim_create_augroup('lsp_before_save',defs)
end

-- Synchronously organise (Go) imports. Taken from
-- https://github.com/neovim/nvim-lsp/issues/115#issuecomment-654427197.
function M.go_organize_imports_sync(timeout_ms)
  local context = { source = { organizeImports = true } }
  vim.validate { context = { context, 't', true } }
  local params = vim.lsp.util.make_range_params()
  params.context = context

  -- See the implementation of the textDocument/codeAction callback
  -- (lua/vim/lsp/handler.lua) for how to do this properly.
  local result = lsp.buf_request_sync(0, "textDocument/codeAction", params, timeout_ms)
  if not result or next(result) == nil then return end
  local actions = result[1].result
  if not actions then return end
  local action = actions[1]

  -- textDocument/codeAction can return either Command[] or CodeAction[]. If it
  -- is a CodeAction, it can have either an edit, a command or both. Edits
  -- should be executed first.
  if action.edit or type(action.command) == "table" then
    if action.edit then
      vim.lsp.util.apply_workspace_edit(action.edit)
    end
    if type(action.command) == "table" then
      vim.lsp.buf.execute_command(action.command)
    end
  else
    vim.lsp.buf.execute_command(action)
  end
end

return M
