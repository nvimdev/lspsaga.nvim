local api, lsp = vim.api, vim.lsp
local util = require('lspsaga.util')
local config = require('lspsaga').config
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

function symbol:buf_watcher(buf, client)
  local function spawn_request(changedtick)
    vim.defer_fn(function()
      self[buf].pending_request = true
      self:do_request(buf, client, function()
        self[buf].pending_request = false
        if changedtick ~= buf_changedtick[buf] then
          changedtick = api.nvim_buf_get_changedtick(buf)
          spawn_request(changedtick)
        end
      end)
    end, 1000)
  end

  api.nvim_buf_attach(buf, false, {
    on_lines = function(_, b, changedtick)
      if b ~= buf then
        return
      end
      buf_changedtick[buf] = changedtick
      if not self[buf].pending_request then
        spawn_request(changedtick)
      end
    end,
    on_detach = function()
      clean_buf_cache(buf)
    end,
  })
end

function symbol:do_request(buf, client, callback)
  local params = { textDocument = {
    uri = vim.uri_from_bufnr(buf),
  } }

  local register = false
  if not self[buf] then
    self[buf] = {}
    register = true
  end

  self[buf].pending_request = true
  client.request('textDocument/documentSymbol', params, function(err, result, ctx)
    self[ctx.bufnr].pending_request = false
    if err then
      if callback then
        callback()
      end
      return
    end

    if callback then
      callback()
    end

    self[ctx.bufnr].symbols = result
    api.nvim_exec_autocmds('User', {
      pattern = 'SagaSymbolUpdate',
      modeline = false,
      data = { symbols = result },
    })
  end, buf)
  if register then
    self:buf_watcher(buf, client)
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
  api.nvim_create_autocmd('LspAttach', {
    group = api.nvim_create_augroup('LspsagaSymbols', { clear = false }),
    callback = function(args)
      local client = lsp.get_client_by_id(args.data.client_id)
      if not client.supports_method('textDocument/documentSymbol') then
        return
      end

      util.server_ready(args.buf, function()
        vim.schedule(function()
          self:do_request(args.buf, client, function()
            require('lspsaga.symbol.winbar').init_winbar(args.buf)
            if
              config.implement.enable and client.supports_method('textDocument/implementation')
            then
              require('lspsaga.implement').start(args.buf, client)
            end
          end)
        end)
      end)
    end,
  })
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
