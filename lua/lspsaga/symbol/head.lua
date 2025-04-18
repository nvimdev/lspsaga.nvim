--this module using LspNotify just for neovim 0.10
local api, lsp = vim.api, vim.lsp
local config = require('lspsaga').config
---@diagnostic disable-next-line: deprecated
local uv = vim.version().minor >= 10 and vim.uv or vim.loop
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

local function timer_clear(t)
  t:stop()
  t:close()
end

function symbol:buf_watcher(bufnr, group)
  local bufstate = {}

  api.nvim_create_autocmd('LspNotify', {
    group = group,
    buffer = bufnr,
    callback = function(args)
      if
        args.data.method ~= 'textDocument/didChange'
        or not self[args.buf]
        or args.data.client_id ~= self[args.buf].client_id
      then
        return
      end
      local client = lsp.get_client_by_id(args.data.client_id)
      if not client then
        return
      end
      if bufstate[args.buf] then
        timer_clear(bufstate[args.buf])
        bufstate[args.buf] = nil
      end
      bufstate[args.buf] = uv.new_timer()
      bufstate[args.buf]:start(500, 0, function()
        timer_clear(bufstate[args.buf])
        bufstate[args.buf] = nil
        vim.schedule(function()
          self:do_request(args.buf, args.data.client_id)
        end)
      end)
    end,
  })

  api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    buffer = bufnr,
    callback = function()
      clean_buf_cache(bufnr)
    end,
  })
end

function symbol:do_request(buf, client_id)
  local params = { textDocument = {
    uri = vim.uri_from_bufnr(buf),
  } }

  local client = vim.lsp.get_client_by_id(client_id)
  if not client then
    return
  end

  if not self[buf] then
    self[buf] = {
      client_id = client_id,
      pending_request = true,
    }
  end

  client.request('textDocument/documentSymbol', params, function(err, result, ctx)
    if not api.nvim_buf_is_loaded(ctx.bufnr) or not self[ctx.bufnr] then
      return
    end
    self[ctx.bufnr].pending_request = false
    if not result or err then
      return
    end
    self[ctx.bufnr].symbols = result
    api.nvim_exec_autocmds('User', {
      pattern = 'SagaSymbolUpdate',
      modeline = true,
      data = {
        symbols = result or {},
        client_id = ctx.client_id,
        bufnr = ctx.bufnr,
      },
    })
  end, buf)
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
  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
  local ok = pcall(vim.treesitter.get_parser, buf, lang)
  if not ok then
    return
  end

  if not node.selectionRange then
    return false
  end
  local tnode = vim.treesitter.get_node({
    bufnr = buf,
    pos = {
      node.selectionRange.start.line,
      node.selectionRange.start.character,
    },
  })

  if not tnode then
    return
  end

  local keylist = {
    'if_statement',
    'for_statement',
    'while_statement',
    'repeat_statement',
    'do_statement',
  }
  if vim.tbl_contains(keylist, tnode:type()) then
    return true
  end

  return false
end

function symbol:register_module()
  local group = api.nvim_create_augroup('LspsagaSymbols', { clear = true })
  api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(args)
      if self[args.buf] then
        return
      end

      local client = lsp.get_client_by_id(args.data.client_id)
      if not client or not client.supports_method('textDocument/documentSymbol') then
        return
      end

      self:do_request(args.buf, args.data.client_id)

      local winbar
      if config.symbol_in_winbar.enable then
        winbar = require('lspsaga.symbol.winbar')
        winbar.init_winbar(args.buf)
      end
      self:buf_watcher(args.buf, group)

      if config.implement.enable and client.supports_method('textDocument/implementation') then
        require('lspsaga.implement').start()
      end
    end,
  })

  api.nvim_create_autocmd('LspDetach', {
    group = group,
    callback = function(args)
      if self[args.buf] then
        self[args.buf] = nil
        if config.symbol_in_winbar.enable then
          pcall(api.nvim_del_augroup_by_name, 'SagaWinbar' .. args.buf)
        end
      end
    end,
  })
end

function symbol:outline()
  require('lspsaga.symbol.outline'):outline()
end

return setmetatable(cache, symbol)
