require('lspsaga').setup({})

local finder = require('lspsaga.finder')

describe('finder module', function()
  local lbufnr
  local rbufnr
  local autocmd

  before_each(function()
    lbufnr = vim.api.nvim_create_buf(false, true)
    rbufnr = vim.api.nvim_create_buf(false, true)
    finder.lbufnr = lbufnr
    finder.rbufnr = rbufnr
    finder.cleaned = false
    finder.clean = function(self)
      self.cleaned = true
    end
    autocmd = vim.api.nvim_create_autocmd('BufEnter', {
      callback = function() end,
    })
  end)

  after_each(function()
    pcall(vim.api.nvim_del_autocmd, autocmd)
    for _, bufnr in ipairs({ lbufnr, rbufnr }) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    finder.lbufnr = nil
    finder.rbufnr = nil
    finder.cleaned = nil
    finder.clean = nil
  end)

  it('keeps the finder open when entering finder buffers', function()
    finder:close_on_bufenter({ buf = lbufnr, id = autocmd })

    assert.is_false(finder.cleaned)
    assert.is_equal(1, #vim.api.nvim_get_autocmds({ id = autocmd }))
  end)

  it('schedules cleanup after entering another buffer', function()
    local other = vim.api.nvim_create_buf(false, true)

    finder:close_on_bufenter({ buf = other, id = autocmd })

    assert.is_equal(0, #vim.api.nvim_get_autocmds({ id = autocmd }))
    vim.wait(100, function()
      return finder.cleaned
    end)
    assert.is_true(finder.cleaned)

    vim.api.nvim_buf_delete(other, { force = true })
  end)
end)
