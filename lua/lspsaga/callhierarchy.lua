local api, fn, lsp = vim.api, vim.fn, vim.lsp
local method = {
  'textDocument/prepareCallHierarchy',
  'callHierarchy/incomingCalls',
  'callHierarchy/outgoingCalls',
}

local ch = {}

local function call_hierarchy(meth)
  local params = lsp.util.make_position_params()
  lsp.buf_request(0, method[1], params, function(_, result, ctx)
    local client = lsp.get_client_by_id(ctx.client_id)
    --TODO: choice of result
    client.request(meth, { item = result[1] }, function(_, res)
      print(vim.inspect(res))
    end)
  end)
end

function ch:incoming_calls()
  call_hierarchy(method[2])
end

function ch:outcoming_calls()
  call_hierarchy(method[3])
end

return ch
