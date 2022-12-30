local api = vim.api

if vim.g.lspsaga_version then
  return
end

vim.g.lspsaga_version = '0.2.3'

api.nvim_create_user_command('Lspsaga', function(args)
  require('lspsaga.command').load_command(unpack(args.fargs))
end, {
  range = true,
  nargs = '+',
  complete = function(arg)
    local list = require('lspsaga.command').command_list()
    return vim.tbl_filter(function(s)
      return string.match(s, '^' .. arg)
    end, list)
  end,
})

api.nvim_create_user_command('LSoutlineToggle', function()
  require('lspsaga.outline'):render_outline()
end, {})
