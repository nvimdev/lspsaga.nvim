local saga = {}

saga.config_values = {
  diagnostic_opts = {
    underline = true,
    virtual_text = true,
    signs = {
      enable = true,
      priority = 20
    },
    update_in_insert = false,
  },
  error_sign = '',
  warn_sign = '',
  hint_sign = '',
  infor_sign = '',
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

function saga:extend_config(opts)
  opts = opts or {}
  if next(opts) == nil then return  end
  for key,value in pairs(opts) do
    if self.config_values[key] == nil then
      error(string.format('[LspSaga] Key %s not exist in config values',key))
      return
    end
    if type(self.config_values[key]) == 'table' then
      vim.tbl_extend('keep',self.config_values[key],value)
    else
      self.config_values[key] = value
    end
  end
end

function saga.init_lsp_saga(opts)
  saga:extend_config(opts)
  local diag = require ('lspsaga.diagnostic')
  local syntax = require 'lspsaga.syntax'
  diag.saga_diagnostic_handler()
  syntax.add_highlight()
end

return saga
