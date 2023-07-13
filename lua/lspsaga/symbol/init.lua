local api, lsp = vim.api, vim.lsp
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

function symbol:buf_watcher(buf, client_id)
  local function defer_request(changedtick)
    vim.defer_fn(function()
      if not self[buf] or not api.nvim_buf_is_valid(buf) then
        return
      end
      self[buf].pending_request = true
      self:do_request(buf, client_id, function()
        if not api.nvim_buf_is_valid(buf) then
          return
        end
        self[buf].pending_request = false
        if changedtick < buf_changedtick[buf] then
          changedtick = api.nvim_buf_get_changedtick(buf)
          defer_request(changedtick)
        else
          self[buf].changedtick = changedtick
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
      if self[buf] and not self[buf].pending_request then
        defer_request(changedtick)
      end
    end,
  })

  api.nvim_create_autocmd('BufDelete', {
    buffer = buf,
    callback = function()
      clean_buf_cache(buf)
    end,
  })
end

function symbol:do_request(buf, client_id, callback)
  local params = { textDocument = {
    uri = vim.uri_from_bufnr(buf),
  } }

  local client = vim.lsp.get_client_by_id(client_id)
  if not client then
    return
  end

  if not self[buf] then
    self[buf] = {}
    self:buf_watcher(buf, client.id)
  end

  self[buf].pending_request = true

  ---@diagnostic disable-next-line: invisible
  client.request('textDocument/documentSymbol', params, function(err, result, ctx)
    if not api.nvim_buf_is_loaded(ctx.bufnr) or not self[ctx.bufnr] then
      return
    end
    self[ctx.bufnr].pending_request = false

    if callback then
      callback(result)
    end

    if err then
      return
    end

    self[ctx.bufnr].symbols = result

    api.nvim_exec_autocmds('User', {
      pattern = 'SagaSymbolUpdate',
      modeline = false,
      data = { symbols = result or {}, client_id = ctx.client_id, bufnr = ctx.bufnr },
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
      if self[args.buf] or api.nvim_get_current_buf() ~= args.buf then
        return
      end

      local client = lsp.get_client_by_id(args.id)
      if not client then
        return
      end
      if not client.supports_method('textDocument/documentSymbol') then
        return
      end

      local winbar
      if config.symbol_in_winbar.enable then
        winbar = require('lspsaga.symbol.winbar')
        local curwin_conf = api.nvim_win_get_config(0)
        if curwin_conf.relative == 0 then
          winbar.file_bar(args.buf)
        end
      end

      self:do_request(args.buf, args.data.client_id, function(result)
        if api.nvim_get_current_buf() ~= args.buf then
          return
        end

        if winbar then
          winbar.init_winbar(args.buf)
        end

        if config.implement.enable and client.supports_method('textDocument/implementation') then
          require('lspsaga.implement').start(args.buf, args.data.client_id, result)
        end
      end)
    end,
  })

  api.nvim_create_autocmd('LspDetach', {
    group = group,
    callback = function(args)
      if self[args.buf] then
        self[args.buf] = nil
      end
    end,
  })
end

function symbol:outline()
  require('lspsaga.symbol.outline'):outline()
end

return setmetatable(cache, symbol)
