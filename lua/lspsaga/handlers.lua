local vim,lsp = vim,vim.lsp
local window = require('lspsaga.window')
local handlers = {}

-- Add I custom handlers function in lsp server config
function handlers.overwrite_default(opts)
  -- diagnostic callback
  lsp.handlers['textDocument/hover'] = function(_, method, result)
    vim.lsp.util.focusable_float(method, function()
        if not (result and result.contents) then return end
        local markdown_lines = lsp.util.convert_input_to_markdown_lines(result.contents)
        markdown_lines = lsp.util.trim_empty_lines(markdown_lines)
        if vim.tbl_isempty(markdown_lines) then return end

        local bufnr,contents_winid,_,border_winid = window.fancy_floating_markdown(markdown_lines, {
          max_hover_width = opts.max_hover_width,
          border_style = opts.border_style,
        })

        lsp.util.close_preview_autocmd({"CursorMoved", "BufHidden", "InsertCharPre"}, contents_winid)
        lsp.util.close_preview_autocmd({"CursorMoved", "BufHidden", "InsertCharPre"}, border_winid)
        return bufnr,contents_winid
    end)
    end

  if opts.use_saga_diagnostic_handler == 1 then
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
