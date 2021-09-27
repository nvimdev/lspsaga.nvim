local command = {}
local provider = require "lspsaga.provider"
local lsprename = require "lspsaga.rename"
local lsphover = require "lspsaga.hover"
local diagnostic = require "lspsaga.diagnostic"
local codeaction = require "lspsaga.codeaction"
local signature = require "lspsaga.signaturehelp"
local floaterm = require "lspsaga.floaterm"
local implement = require "lspsaga.implement"

local subcommands = {
  lsp_finder = provider.lsp_finder,
  preview_definition = provider.preview_definition,
  rename = lsprename.rename,
  hover_doc = lsphover.render_hover_doc,
  show_cursor_diagnostics = diagnostic.show_cursor_diagnostics,
  show_line_diagnostics = diagnostic.show_line_diagnostics,
  diagnostic_jump_next = diagnostic.lsp_jump_diagnostic_next,
  diagnostic_jump_prev = diagnostic.lsp_jump_diagnostic_prev,
  code_action = codeaction.code_action,
  range_code_action = codeaction.range_code_action,
  signature_help = signature.signature_help,
  open_floaterm = floaterm.open_float_terminal,
  close_floaterm = floaterm.close_float_terminal,
  implement = implement.lspsaga_implementation,
}

function command.command_list()
  return vim.tbl_keys(subcommands)
end

function command.load_command(cmd, ...)
  local args = { ... }
  if next(args) ~= nil then
    subcommands[cmd](args[1])
  else
    subcommands[cmd]()
  end
end

return command
