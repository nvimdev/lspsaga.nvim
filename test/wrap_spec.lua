local wrap = require('lspsaga.wrap')
local test = 'test test test test test test test'
local eq = assert.is_equal

describe('wrap function test', function()
  describe('if text too long split by max width', function()
    it('wrap test', function()
      local tbl = wrap.wrap_text(test, 20)
      eq(2, #tbl)
    end)
  end)

  describe('test table', function()
    it('wrap table', function()
      local test_tbl = { test, test }
      local tbl = wrap.wrap_contents(test_tbl, 15)
      eq(4, #tbl)
    end)
  end)
end)
