local log = require('lspsaga.logger')
local eq = assert.equal

describe('logger module ', function()
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

  log:new(method, results):write()
  log:open()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1]
  local part = vim.split(line, '%s')
  eq('[Lspsaga]', part[1])
  eq('[textDocument/definition]', part[3])
  local decode = vim.json.decode(part[4])
  assert.same(results, decode)
end)
