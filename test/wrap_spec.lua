local wrap = require('lspsaga.wrap')
local test = 'test test test test test test test'
local eq = assert.is_equal

describe('wrap function test', function()
  it('wrap test', function()
    local tbl = wrap.wrap_text(test, 20)
    eq(2, #tbl)
  end)
end)
