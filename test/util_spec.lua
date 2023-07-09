local helper = require('test.helper')
local api = vim.api
local util = require('lspsaga.util')
local eq, is_true = assert.equal, assert.is_true

---util module unit test
describe('lspsaga util', function()
  local bufnr
  before_each(function()
    bufnr = api.nvim_create_buf(true, false)
    api.nvim_win_set_buf(0, bufnr)
  end)

  it('util.path_itera', function()
    api.nvim_buf_set_name(bufnr, 'test.lua')
    local result = {}
    for part in util.path_itera(bufnr) do
      result[#result + 1] = part
    end
    eq('test.lua', result[1])
  end)

  it('util.tbl_index', function()
    local case = { 1, 2, 3, 8 }
    eq(4, util.tbl_index(case, 8))
  end)

  it('util.close_win', function()
    vim.cmd.split()
    util.close_win(api.nvim_get_current_win())
    assert.is_true(true, #api.nvim_list_wins() == 1)
  end)

  it('util.as_table', function()
    assert.same({ 10 }, util.as_table(10))
    assert.same({ 10 }, util.as_table({ 10 }))
  end)

  it('util.map_keys', function()
    util.map_keys(bufnr, 'gq', function()
      return '<Nop>'
    end)
    local maps = api.nvim_buf_get_keymap(bufnr, 'n')
    local created = false
    for _, item in ipairs(maps) do
      if item.lhs == 'gq' then
        created = true
        break
      end
    end
    is_true(true, created)
  end)

  it('util.res_isempty', function()
    local client_results = { { result = {} } }
    assert.is_true(util.res_isempty(client_results))
  end)
end)
