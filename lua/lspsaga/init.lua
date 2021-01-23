local saga = {}

function saga.init_lsp_saga(opts)
  opts = opts or {}
  local diagnostic = require 'lspsaga.diagnostic'
  local handlers = require 'lspsaga.handlers'
  local syntax = require 'lspsaga.syntax'

  handlers.overwrite_default()
  diagnostic.lsp_diagnostic_sign(opts)
  syntax.add_highlight()
end

return saga
