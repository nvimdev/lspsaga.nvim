local api = vim.api
local helper = require('test.helper')
require('lspsaga').setup({})

local function create_root()
  local mod_file = helper.join_paths(helper.test_dir(), 'go.mod')
  if vim.fn.filereadable(mod_file) == 0 then
    os.execute('touch go.mod')
  end
end

describe('implement moudle', function()
  local bufnr
  helper.lspconfig_dep()
  before_each(function()
    bufnr = api.nvim_create_buf(true, false)
  end)

  after_each(function()
    local res = vim.fn.delete('./go.mod')
    if res ~= 0 or not res then
      print('delete file failed')
    end
  end)

  it('work as expect', function()
    api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      'package main',
      'type Phone interface {',
      '    Call()',
      '}',
      'type Apple struct {',
      '   name string',
      '}',
    })
    local fname = helper.join_paths(helper.test_dir(), 'main.go')
    api.nvim_buf_set_name(bufnr, fname)
    create_root()
    require('lspsaga.implement').start()
    vim.bo[bufnr].filetype = 'go'
    vim.wait(3000)
  end)
end)
