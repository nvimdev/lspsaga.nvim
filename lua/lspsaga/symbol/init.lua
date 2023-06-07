local api = vim.api
local util = require('lspsaga.util')
local symbol = {}

local cache = {}
symbol.__index = symbol

function symbol.__newindex(t, k, v)
  rawset(t, k, v)
end

local function clean_buf_cache(buf)
  buf = buf or api.nvim_get_current_buf()
  if buf and cache[buf] then
    for k, _ in pairs(cache[buf]) do
      cache[buf][k] = nil
    end
    cache[buf] = nil
  end
end

local buf_changedtick = {}

function symbol:buf_watcher(buf, callback)
  local function spawn_request()
    vim.defer_fn(function()
      self[buf].pending_request = true
      self:do_request(buf, function(_, symbols)
        self[buf].pending_request = false
        if callback then
          callback(buf, symbols)
        end
        local tick_now = api.nvim_buf_get_changedtick(buf)
        if tick_now ~= buf_changedtick[buf] then
          spawn_request()
        end
      end)
    end, 500)
  end

  api.nvim_buf_attach(buf, false, {
    on_lines = function(_, b, changedtick)
      if b ~= buf then
        return
      end
      buf_changedtick[buf] = changedtick
      if not self[buf].pending_request then
        spawn_request()
      end
    end,
    on_detach = function()
      clean_buf_cache(buf)
    end,
  })
end

function symbol:do_request(buf, callback)
  local params = { textDocument = {
    uri = vim.uri_from_bufnr(buf),
  } }

  local client = util.get_client_by_cap('documentSymbolProvider')
  if not client then
    return
  end

  local register_watcher = false
  if not self[buf] then
    self[buf] = {}
    register_watcher = true
  end

  self[buf].pending_request = true
  client.request('textDocument/documentSymbol', params, function(err, result, ctx)
    self[ctx.bufnr].pending_request = false
    if err then
      return
    end
    self[ctx.bufnr].symbols = result
    if result then
      if callback then
        callback(buf, result)
      end

      if self.queue and #self.queue > 0 then
        for _, fn in ipairs(self.queue) do
          fn(buf, result)
        end
        self.queue = {}
      end
    end

    api.nvim_exec_autocmds('User', {
      pattern = 'SagaSymbolUpdate',
      modeline = false,
      data = { symbols = result },
    })
  end, buf)

  if register_watcher then
    self:buf_watcher(buf, callback)
  end
end

function symbol:get_buf_symbols(buf)
  buf = buf or api.nvim_get_current_buf()
  local res = {}
  if not self[buf] then
    return
  end

  if self[buf].pending_request then
    res.pending_request = self[buf].pending_request
    return res
  end

  res.symbols = self[buf].symbols
  res.pending_request = self[buf].pending_request
  return res
end

function symbol:push_cb_queue(fn)
  if not self.queue then
    self.queue = {}
  end
  self.queue[#self.queue + 1] = fn
end

function symbol:node_is_keyword(buf, node)
  if not node.selectionRange then
    return false
  end
  local captures = vim.treesitter.get_captures_at_pos(
    buf,
    node.selectionRange.start.line,
    node.selectionRange.start.character
  )
  for _, v in pairs(captures) do
    if v.capture == 'keyword' or v.capture == 'conditional' or v.capture == 'repeat' then
      return true
    end
  end
  return false
end

function symbol:winbar()
  require('lspsaga.symbol.winbar').symbol_autocmd()
end

function symbol:outline()
  require('lspsaga.symbol.outline'):outline()
end

--@return table
function symbol:category(buf, symbols)
  local res = {}

  local tmp_node = function(node)
    local tmp = {}
    tmp.winline = -1
    for k, v in pairs(node) do
      if k ~= 'children' then
        tmp[k] = v
      end
    end
    return tmp
  end

  local function recursive_parse(tbl)
    for _, v in ipairs(tbl) do
      if not res[v.kind] then
        res[v.kind] = {
          expand = true,
          data = {},
        }
      end
      if not self:node_is_keyword(buf, v) then
        local tmp = tmp_node(v)
        res[v.kind].data[#res[v.kind].data + 1] = tmp
      end
      if v.children then
        recursive_parse(v.children)
      end
    end
  end
  recursive_parse(symbols)
  return res
end

return setmetatable(cache, symbol)
