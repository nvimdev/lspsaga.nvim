local command = {}

local subcommands = {
  lsp_finder = function()
    require('lspsaga.finder'):lsp_finder()
  end,
  peek_definition = function()
    require('lspsaga.definition'):peek_definition()
  end,
  goto_defintion = function()
    require('lspsaga.definition'):goto_defintion()
  end,
  rename = function()
    require('lspsaga.rename'):lsp_rename()
  end,
  hover_doc = function()
    require('lspsaga.hover'):render_hover_doc()
  end,
  show_cursor_diagnostics = function()
    require('lspsaga.diagnostic'):show_diagnostics(arg, true)
  end,
  show_line_diagnostics = function(arg)
    require('lspsaga.diagnostic'):show_diagnostics(arg)
  end,
  diagnostic_jump_next = function()
    require('lspsaga.diagnostic').goto_next()
  end,
  diagnostic_jump_prev = function()
    require('lspsaga.diagnostic').goto_prev()
  end,
  code_action = function()
    require('lspsaga.codeaction'):code_action()
  end,
  outline = function()
    require('lspsaga.outline'):outline()
  end,
  incoming_calls = function()
    require('lspsaga.callhierarchy'):incoming_calls()
  end,
  outgoing_calls = function()
    require('lspsaga.callhierarchy'):outgoing_calls()
  end,
  open_floaterm = function(cmd)
    require('lspsaga.floaterm'):open_float_terminal(cmd)
  end,
  close_floaterm = function()
    require('lspsaga.floaterm'):close_float_terminal()
  end,
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
