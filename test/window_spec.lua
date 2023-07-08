local api = vim.api
require('lspsaga').setup({})
local win = require('lspsaga.window')
local eq = assert.equal
vim.opt.swapfile = false

describe('window module', function()
  local bufnr, winid
  local float_opt = {
    relative = 'editor',
    row = 10,
    col = 10,
    border = 'single',
    height = 10,
    width = 10,
  }

  before_each(function()
    if winid and api.nvim_win_is_valid(winid) then
      api.nvim_win_close(winid, true)
    end
    pcall(api.nvim_delete_buf, bufnr, { force = true })
  end)

  it('can create float window', function()
    assert.equal(1, #api.nvim_list_wins())
    bufnr, winid = win:new_float(float_opt):wininfo()
    eq(2, #api.nvim_list_wins())
  end)

  it('can create float window and enter float window', function()
    bufnr, winid = win:new_float(float_opt, true):wininfo()
    eq(winid, api.nvim_get_current_win())
  end)

  it('can set float window buffer options', function()
    bufnr, winid = win:new_float(float_opt):bufopt('bufhidden', 'wipe'):wininfo()
    eq('wipe', vim.bo[bufnr].bufhidden)
  end)

  it('can set float window buffer options in table param', function()
    bufnr, winid = win
      :new_float(float_opt)
      :bufopt({
        ['bufhidden'] = 'wipe',
        ['filetype'] = 'saga_unitest',
      })
      :wininfo()
    eq('wipe', vim.bo[bufnr].bufhidden)
    eq('saga_unitest', vim.bo[bufnr].filetype)
  end)

  it('can set float window win-local options', function()
    bufnr, winid = win:new_float(float_opt):winopt('number', true):wininfo()
    assert.is_true(vim.wo[winid].number)
  end)

  it('can set float window win-local options by using table param', function()
    bufnr, winid = win
      :new_float(float_opt)
      :winopt({
        ['number'] = true,
        ['signcolumn'] = 'no',
      })
      :wininfo()
    assert.is_true(vim.wo[winid].number)
    eq('no', vim.wo[winid].signcolumn)
  end)

  it('can create normal window', function()
    bufnr, winid = win:new_normal('sp'):wininfo()
    eq(2, #api.nvim_list_wins())
  end)

  it('can set normal win-local options', function()
    bufnr, winid = win:new_normal('sp'):winopt('number', true):wininfo()
    assert.is_true(vim.wo[winid].number)
  end)

  it('can restore options after close ', function()
    vim.opt.number = true
    vim.opt.swapfile = false
    local restore = win:minimal_restore()
    vim.cmd('enew')
    bufnr = vim.api.nvim_get_current_buf()
    local curwin = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(curwin, bufnr)

    bufnr, winid = win
      :new_float({
        relative = 'editor',
        row = 10,
        col = 10,
        height = 20,
        width = 20,
        style = 'minimal',
        bufnr = bufnr,
      }, true)
      :wininfo()

    vim.api.nvim_create_autocmd('WinClosed', {
      callback = function()
        restore()
      end,
    })
    vim.api.nvim_win_close(winid, true)
    vim.api.nvim_set_current_win(curwin)
    assert.is_true(vim.api.nvim_get_option_value('number', { win = curwin }))
  end)
end)
