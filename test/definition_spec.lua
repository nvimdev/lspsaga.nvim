local fake_lsp = require('test.fake_lsp')

describe('definition module', function()
  it('can work', function()
    fake_lsp.start_server()
  end)
end)
