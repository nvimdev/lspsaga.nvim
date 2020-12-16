local vim,lsp = vim,vim.lsp
local window = require('lspsaga.window')
local handlers = {}

local function lookup_section(settings, section)
  for part in vim.gsplit(section, '.', true) do
    settings = settings[part]
    if not settings then
      return
    end
  end
  return settings
end

-- Add I custom handlers function in lsp server config
function handlers.add_handlers(server_setup)

  server_setup.handlers["window/logMessage"] = function(err, method, params, client_id)
        if params and params.type <= server_setup.log_level then
          assert(vim.lsp.handlers["window/logMessage"], "Callback for window/logMessage notification is not defined")
          vim.lsp.handlers["window/logMessage"](err, method, params, client_id)
        end
      end

  server_setup.handlers["window/showMessage"] = function(err, method, params, client_id)
    if params and params.type <= server_setup.message_level then
      assert(vim.lsp.handlers["window/showMessage"], "Callback for window/showMessage notification is not defined")
      vim.lsp.handlers["window/showMessage"](err, method, params, client_id)
    end
  end

  -- add workspace/configuration callback function
  server_setup.handlers["workspace/configuration"] = function(err, _, params, _)
      if err then error(tostring(err)) end
      if not params.items then
        return {}
      end

      local result = {}
      for _, item in ipairs(params.items) do
        if item.section then
          local value = lookup_section(server_setup.settings, item.section) or vim.NIL
          -- For empty sections with no explicit '' key, return settings as is
          if value == vim.NIL and item.section == '' then
            value = server_setup.settings or vim.NIL
          end
          table.insert(result, value)
        end
      end
      return result
    end

  -- diagnostic callback
  server_setup.handlers['textDocument/hover'] = function(_, method, result)
    vim.lsp.util.focusable_float(method, function()
        if not (result and result.contents) then return end
        local markdown_lines = lsp.util.convert_input_to_markdown_lines(result.contents)
        markdown_lines = lsp.util.trim_empty_lines(markdown_lines)
        if vim.tbl_isempty(markdown_lines) then return end

        local bufnr,contents_winid,_,border_winid = window.fancy_floating_markdown(markdown_lines)
        lsp.util.close_preview_autocmd({"CursorMoved", "BufHidden", "InsertCharPre"}, contents_winid)
        lsp.util.close_preview_autocmd({"CursorMoved", "BufHidden", "InsertCharPre"}, border_winid)
        return bufnr,contents_winid
    end)
    end

  server_setup.handlers['textDocument/publishDiagnostics'] = vim.lsp.with(
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

return handlers
