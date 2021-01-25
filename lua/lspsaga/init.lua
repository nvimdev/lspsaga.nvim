local saga = {}

saga.config_values = {
  -- diagnostic sign
  error_sign = '',
  warn_sign = '',
  hint_sign = '',
  infor_sign = '',
  -- code action title icon
  code_action_icon = ' ',
  finder_definition_icon = '  ',
  finder_reference_icon = '  ',
  definition_preview_icon = '  '
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

  handlers.overwrite_default()
  diagnostic.lsp_diagnostic_sign(saga.config_values)
  syntax.add_highlight()
end

return saga
