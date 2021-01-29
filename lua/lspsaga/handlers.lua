local vim,lsp = vim,vim.lsp
local handlers = {}

-- Add I custom handlers function in lsp server config
function handlers.overwrite_default(opts)
  if opts.use_saga_diagnostic_handler then
    lsp.handlers['textDocument/publishDiagnostics'] = vim.lsp.with(
      vim.lsp.diagnostic.on_publish_diagnostics, {
          -- Enable underline, use default values
          underline = true,
          -- Enable virtual text, override spacing to 4
          virtual_text = true,
          signs = {
            enable = true,
            priority = 20
          },
          -- Disable a feature
          update_in_insert = false,
      })
  end
end

return handlers
