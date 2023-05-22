local api = vim.api
local util = require('lspsaga.util')
local eq = assert.equal

describe('lspsaga util', function()
  local bufnr
  before_each(function()
    bufnr = api.nvim_create_buf(true, false)
    api.nvim_win_set_buf(0, bufnr)
  end)

  it('util.get_path_info', function()
    api.nvim_buf_set_name(bufnr, 'test.lua')
    local tbl = util.get_path_info(bufnr)
    eq(1, #tbl)
    eq('test.lua', tbl[#tbl])
  end)
end)
