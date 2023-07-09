local uv = vim.loop

local function handle_request(request)
  if request.method == 'textDocument/completion' then
    local response = {
      jsonrpc = '2.0',
      id = request.id,
      result = {
        items = {
          {
            label = 'example1',
            kind = 1,
          },
          {
            label = 'example2',
            kind = 1,
          },
        },
      },
    }
    vim.schedule(function()
      vim.fn.chansend(request.channel, vim.fn.json_encode(response))
    end)
  elseif request.method == 'textDocument/definition' then
    local response = {
      jsonrpc = '2.0',
      id = request.id,
      result = {
        {
          uri = 'file:///path/to/file.lua',
          range = {
            start = { line = 0, character = 0 },
            ['end'] = { line = 0, character = 5 },
          },
        },
      },
    }
    vim.schedule(function()
      vim.fn.chansend(request.channel, vim.fn.json_encode(response))
    end)
  else
  end
end

local function start_server()
  local channel = uv.new_pipe(false)
  local client = uv.spawn('lua', {
    args = { 'path/to/fake_lsp.lua' },
    stdio = { nil, channel, nil },
  }, function()
    channel:close()
  end)

  uv.read_start(channel, function(err, data)
    if err then
      return
    end

    if data then
      local decoded = vim.fn.json_decode(data)
      handle_request(decoded)
    end
  end)

  vim.api.nvim_set_var('fake_lsp_channel', channel)
  print('Fake LSP server started.')
end

local function stop_server()
  local channel = vim.api.nvim_get_var('fake_lsp_channel')
  if channel then
    channel:shutdown()
    channel:close()
    vim.api.nvim_set_var('fake_lsp_channel', nil)
    print('Fake LSP server stopped.')
  else
    print('Fake LSP server is not running.')
  end
end

return {
  start_server = start_server,
  stop_server = stop_server,
}
