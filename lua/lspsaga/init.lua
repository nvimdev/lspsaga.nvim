local saga = {}

saga.config_values = {
  use_saga_diagnostic_sign = true,
  -- diagnostic sign
  error_sign = '',
  warn_sign = '',
  hint_sign = '',
  infor_sign = '',
  -- jump diagnostic header
  error_header = "  Error",
  warn_header = "  Warn",
  hint_header = "  Hint",
  infor_header = "  Infor",
  max_diag_msg_width = 50,
  -- code action title icon
  code_action_icon = ' ',
  finder_definition_icon = '  ',
  finder_reference_icon = '  ',
  definition_preview_icon = '  ',
  -- 1: thin border | 2: rounded border | 3: thick border
  border_style = 1,
  max_hover_width = 0,
  rename_prompt_prefix = '➤',
}

function saga.extend_config(opts)
  opts = opts or {}
  if next(opts) == nil then return  end
  for key,value in pairs(opts) do
    if saga.config_values[key] == nil then
      error(string.format('[LspSaga] Key %s not exist in config values',key))
      return
    end
    saga.config_values[key] = value
  end
end

function saga.init_lsp_saga(opts)
  saga.extend_config(opts)
  local diagnostic = require 'lspsaga.diagnostic'
  local handlers = require 'lspsaga.handlers'
  local syntax = require 'lspsaga.syntax'

  handlers.overwrite_default(saga.config_values)
  if saga.config_values.use_saga_diagnostic_sign then
    diagnostic.lsp_diagnostic_sign(saga.config_values)
  end
  syntax.add_highlight()
end

return saga
