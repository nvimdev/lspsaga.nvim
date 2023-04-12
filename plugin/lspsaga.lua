if vim.g.lspsaga_version then
  return
end

vim.g.lspsaga_version = '0.3.0'

vim.api.nvim_create_user_command('Lspsaga', function(args)
  require('lspsaga.command').load_command(args.fargs[1], args.fargs[2])
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

vim.api.nvim_create_user_command('DiagnosticInsertEnable', function()
  require('lspsaga.diagnostic'):on_insert()
end, {})
