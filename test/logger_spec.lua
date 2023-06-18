local log = require('lspsaga.logger')
local eq = assert.equal

describe('logger module ', function()
  after_each(function()
    log:open()
    local curbuf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(curbuf, 0, -1, false, {})
    vim.cmd.write()
  end)

  it('should work as expect', function()
    local params = {
      position = {
        character = 10,
        line = 10,
      },
      textDocument = {
        uri = 'file://logger_spec.lua',
      },
    }

    local method = 'textDocument/definition'
    local results = {
      {
        result = {
          {
            originSelectionRange = {
              ['end'] = {
                character = 20,
                line = 4,
              },
              start = {
                character = 6,
                line = 4,
              },
            },
            targetRange = {
              ['end'] = {
                character = 20,
                line = 4,
              },
              start = {
                character = 6,
                line = 4,
              },
            },
            targetSelectionRange = {
              ['end'] = {
                character = 20,
                line = 4,
              },
              start = {
                character = 6,
                line = 4,
              },
            },
            targetUri = 'file:///home/test.lua',
          },
        },
      },
    }

    log:new(method, params, results):write()
    log:open()
    local bufnr = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1]
    local part = vim.split(line, '%s')
    eq('[Lspsaga]', part[1])
    eq('[textDocument/definition]', part[3])
    local decode = vim.json.decode(part[7])
    assert.same(results, decode)
  end)
end)
