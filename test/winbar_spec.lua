-- Define a table simulating LSP (Language Server Protocol) symbol responses
local lsp_symbols = {
  pending_request = false,
  symbols = {
    {
      detail = '',
      kind = 19,
      name = 'command',
      range = {
        ['end'] = {
          character = 18,
          line = 0,
        },
        start = {
          character = 6,
          line = 0,
        },
      },
      selectionRange = {
        ['end'] = {
          character = 13,
          line = 0,
        },
        start = {
          character = 6,
          line = 0,
        },
      },
    },
  },
}

-- Function to get symbols, returns the simulated lsp_symbols table
function lsp_symbols.get_symbols(_bufnr)
  return lsp_symbols
end

-- Configuration for the lspsaga plugin
local lspsaga_opts = {
  ui = {
    winbar_prefix = '  ',
  },
  symbol_in_winbar = {
    enable = true,
    separator = '|',
  },
}

-- Require the lspsaga module and configure it with the defined options
local lspsaga = require('lspsaga')
lspsaga.setup(lspsaga_opts)

describe('winbar', function()
  local api = vim.api
  local lspsaga_symbols__get_buf_symbols, lspsaga_head__get_buf_symbols
  local lspsaga_symbol = require('lspsaga.symbol')
  local lspsaga_head = require('lspsaga.symbol.head')
  local lspsaga_winbar = require('lspsaga.symbol.winbar')
  local helper = require('test.helper')

  before_each(function()
    -- Create a new buffer and set it as the current buffer
    local buf = api.nvim_create_buf(false, true)
    api.nvim_set_current_buf(buf)
    api.nvim_command('vsplit')
    api.nvim_set_current_win(api.nvim_get_current_win())

    -- Store original functions
    lspsaga_symbols__get_buf_symbols = lspsaga_symbol.get_buf_symbols
    lspsaga_head__get_buf_symbols = lspsaga_symbol.get_buf_symbols

    -- Replace real LSP interaction with the mock
    lspsaga_symbol.get_buf_symbols = lsp_symbols.get_symbols
    lspsaga_head.get_buf_symbols = lsp_symbols.get_symbols
  end)

  after_each(function()
    -- Close the current window and buffer
    local current_win = api.nvim_get_current_win()
    local current_buf = api.nvim_get_current_buf()

    -- Close the current window
    if current_win ~= 0 then
      api.nvim_win_close(current_win, true)
    end

    -- Optionally, close the buffer if it's not the last buffer
    -- This might be necessary if `vsplit` creates additional windows
    -- and you want to ensure that the buffer is not left open.
    if current_buf ~= 0 and api.nvim_buf_is_valid(current_buf) then
      local buf_list = api.nvim_list_bufs()
      if #buf_list > 1 then
        -- Close the buffer if there are multiple buffers open
        api.nvim_buf_delete(current_buf, { force = true })
      end
    end

    -- Restore original functions after each test
    lspsaga_symbol.get_buf_symbols = lspsaga_symbols__get_buf_symbols
    lspsaga_head.get_buf_symbols = lspsaga_head__get_buf_symbols
  end)

  it('should correctly extract components from the winbar', function()
    -- Initialize the winbar for the current buffer
    lspsaga_winbar.init_winbar(api.nvim_get_current_buf())

    -- Define a winbar value large enough to exceed the window width
    local winbar_value = lspsaga_winbar.get_bar() or ''

    -- Extract the components of the winbar
    local saga_prefix = helper.extract_winbar_value(winbar_value, 'Prefix')
    local saga_sep = helper.extract_winbar_value(winbar_value, 'SagaSep')
    local saga_object = helper.extract_winbar_value(winbar_value, 'SagaObject')

    -- Verify that components were extracted correctly
    assert(saga_prefix, 'Prefix not found in winbar_value')
    assert(saga_sep, 'Separator not found in winbar_value')
    assert(saga_object, 'Symbol not found in winbar_value')

    -- Optionally, check individual presence of prefix, separator, and symbol
    assert(saga_prefix == '  ', 'Prefix does not match expected value')
    assert(saga_sep == '|', 'Separator does not match expected value')
    assert(saga_object == ' command', 'Symbol does not match expected value')
  end)
end)
