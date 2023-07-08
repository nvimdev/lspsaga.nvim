require('lspsaga').setup({})
local eq = assert.is_equal
local ly = require('lspsaga.layout')
vim.opt.swapfile = false

describe('layout module', function()
  local lbufnr, lwinid, rbufnr, rwinid
  it('can create float layout', function()
    lbufnr, lwinid, rbufnr, rwinid = ly:new('float'):left(20, 20):right():done()
    assert.is_true(lbufnr ~= nil)
    assert.is_true(lwinid ~= nil)
    assert.is_true(rbufnr ~= nil)
    assert.is_true(rwinid ~= nil)
  end)

  after_each(function()
    for _, id in ipairs({ lwinid, rwinid }) do
      if vim.api.nvim_win_is_valid(id) then
        vim.api.nvim_win_close(id, true)
      end
    end
  end)

  it('can close float layout', function()
    ly:close()
    local wins = vim.api.nvim_list_wins()
    assert.is_equal(1, #wins)
  end)

  it('can create normal layout', function()
    lbufnr, lwinid, rbufnr, rwinid = ly:new('normal'):left(20, 20):right():done()
    assert.is_true(lbufnr ~= nil)
    assert.is_true(lwinid ~= nil)
    assert.is_true(rbufnr ~= nil)
    assert.is_true(rwinid ~= nil)

    local wins = vim.api.nvim_list_wins()
    local has_float = false
    for _, win in ipairs(wins) do
      local conf = vim.api.nvim_win_get_config(win)
      if #conf.relative ~= 0 then
        has_float = true
      end
    end

    assert.is_false(has_float)
  end)

  it('can close normal layout', function()
    ly:close()
    local wins = vim.api.nvim_list_wins()
    assert.is_equal(1, #wins)
  end)

  it('can set buffer options', function()
    lbufnr, lwinid, rbufnr, rwinid = ly:new('float')
      :left(20, 20)
      :bufopt({
        ['filetype'] = 'lspsaga_test',
        ['buftype'] = 'nofile',
        ['bufhidden'] = 'wipe',
      })
      :right()
      :bufopt({
        ['filetype'] = 'lspsaga_test',
        ['buftype'] = 'nofile',
        ['bufhidden'] = 'wipe',
      })
      :done()

    eq('lspsaga_test', vim.api.nvim_get_option_value('filetype', { buf = lbufnr }))
    eq('nofile', vim.api.nvim_get_option_value('buftype', { buf = lbufnr }))
    eq('wipe', vim.api.nvim_get_option_value('bufhidden', { buf = lbufnr }))
    --right
    eq('lspsaga_test', vim.api.nvim_get_option_value('filetype', { buf = rbufnr }))
    eq('nofile', vim.api.nvim_get_option_value('buftype', { buf = rbufnr }))
    eq('wipe', vim.api.nvim_get_option_value('bufhidden', { buf = rbufnr }))
  end)

  it('can wipe out a wipe layout buffer', function()
    ly:close()
    assert.is_true(vim.api.nvim_buf_is_valid(lbufnr) == false)
    assert.is_true(vim.api.nvim_buf_is_valid(rbufnr) == false)
  end)

  it('can set window local options', function()
    lbufnr, lwinid, rbufnr, rwinid = ly:new('flaot')
      :left(20, 20)
      :winopt({
        ['number'] = false,
      })
      :right()
      :done()
  end)

  assert.is_false(vim.api.nvim_get_option_value('number', { scope = 'local', win = lwinid }))
end)
