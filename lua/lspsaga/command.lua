local command = {}

local subcommands = {
  finder = function(args)
    require('lspsaga.finder'):new(args)
  end,
  peek_definition = function()
    require('lspsaga.definition'):init(1, 1)
  end,
  goto_definition = function(args)
    require('lspsaga.definition'):init(1, 2, args)
  end,
  peek_type_definition = function()
    require('lspsaga.definition'):init(2, 1)
  end,
  goto_type_definition = function(args)
    require('lspsaga.definition'):init(2, 2, args)
  end,
  rename = function(args)
    require('lspsaga.rename'):lsp_rename(args)
  end,
  project_replace = function(args)
    require('lspsaga.rename.project'):new(args)
  end,
  hover_doc = function(args)
    require('lspsaga.hover'):render_hover_doc(args)
  end,
  show_workspace_diagnostics = function(args)
    require('lspsaga.diagnostic.show'):show_diagnostics({ workspace = true, args = args })
  end,
  show_line_diagnostics = function(args)
    require('lspsaga.diagnostic.show'):show_diagnostics({ line = true, args = args })
  end,
  show_buf_diagnostics = function(args)
    require('lspsaga.diagnostic.show'):show_diagnostics({ buffer = true, args = args })
  end,
  show_cursor_diagnostics = function(args)
    require('lspsaga.diagnostic.show'):show_diagnostics({ cursor = true, args = args })
  end,
  diagnostic_jump_next = function()
    require('lspsaga.diagnostic'):goto_next()
  end,
  diagnostic_jump_prev = function()
    require('lspsaga.diagnostic'):goto_prev()
  end,
  code_action = function()
    require('lspsaga.codeaction'):code_action()
  end,
  outline = function()
    require('lspsaga.symbol'):outline()
  end,
  incoming_calls = function(args)
    require('lspsaga.callhierarchy'):send_method(2, args)
  end,
  outgoing_calls = function(args)
    require('lspsaga.callhierarchy'):send_method(3, args)
  end,
  supertypes = function(args)
    require('lspsaga.typehierarchy'):send_method(2, args)
  end,
  subtypes = function(args)
    require('lspsaga.typehierarchy'):send_method(3, args)
  end,
  term_toggle = function(args)
    require('lspsaga.floaterm'):open_float_terminal(args)
  end,
  open_log = function()
    require('lspsaga.logger'):open()
  end,
  winbar_toggle = function()
    require('lspsaga.symbol.winbar').toggle()
  end,
}

function command.command_list()
  return vim.tbl_keys(subcommands)
end

function command.load_command(cmd, arg)
  subcommands[cmd](arg)
end

return command
