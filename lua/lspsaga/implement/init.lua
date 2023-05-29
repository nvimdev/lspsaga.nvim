local api, fn, uv = vim.api, vim.fn, vim.loop
local config = require('lspsaga').config.implement
local ui = require('lspsaga').config.ui
local symbol = require('lspsaga.symbol')
local ns = api.nvim_create_namespace('SagaImp')
local imp = {}

local defined = false
local name = 'SagaImpIcon'

if not defined then
  fn.sign_define(name, { text = ui.imp_sign, texthl = name })
  defined = true
end

local function render_sign(bufnr, row)
  if not config.sign then
    return
  end
  fn.sign_place(row + 1, name, name, bufnr, { lnum = row + 1, priority = config.priority })
end

local function find_client(buf)
  for _, client in ipairs(vim.lsp.get_active_clients({ bufnr = buf })) do
    if client.supports_method('textDocument/implementation') then
      return client
    end
  end
end

local function render_virt(bufnr, range)
  if not config.virtual_text then
    return
  end
  local client = find_client(bufnr)
  if not client then
    return
  end

  local params = {
    position = {
      character = range[2],
      line = range[1],
    },
    textDocument = {
      uri = vim.uri_from_bufnr(bufnr),
    },
  }

  local timer = uv.new_timer()
  timer:start(10, 10, function()
    if next(client.messages.progress) == nil and not timer:is_closing() then
      timer:stop()
      timer:close()
      vim.schedule(function()
        client.request('textDocument/implementation', params, function(err, result)
          print(vim.inspect(result), vim.inspect(err))
          if not result then
            return
          end
          api.nvim_buf_set_extmark(bufnr, ns, range[1], 0, {
            virt_lines = { { { ' ' .. #result .. ' implements', 'Comment' } } },
            virt_lines_above = true,
          })
        end, bufnr)
      end)
    end
  end)
end

local function treesitter(buf)
  local language_parser = {
    ['rust'] = function(node)
      if node:type() == 'trait_item' then
        local range = {}
        range[#range + 1] = node:range()
        for child in node:iter_children() do
          if child:type() == 'type_identifier' then
            local _, col = child:range()
            range[#range + 1] = col
          end
        end
        return range
      end
    end,
    ['go'] = function(node)
      if node:type() == 'type_declaration' then
        for child in node:iter_children() do
          if child:child() then
            for item in child:iter_children() do
              if item:type() == 'interface_type' then
                local row, _, col = item:range()
                return { row, col }
              end
            end
          end
        end
      end
    end,
  }
  if not language_parser[vim.bo[buf].filetype] then
    return
  end

  local topnode = vim.treesitter.get_node({ bufnr = buf, pos = { 0, 1 } })
  if not topnode then
    return
  end
  local root = topnode:parent()

  for node in root:iter_children() do
    local range = language_parser[vim.bo[buf].filetype](node)
    if range then
      render_sign(buf, range[1])
      render_virt(buf, range)
      break
    end
  end
end

local function lspsymbol()
  api.nvim_create_autocmd('User', {
    pattern = 'SagaSymbolUpdate',
    callback = function(opt)
      local symbols = opt.data.symbols
      if not symbols then
        return
      end
    end,
  })
end

function imp:start()
  if config.parser == 'treesitter' then
    local buf = api.nvim_get_current_buf()
    treesitter(buf)
  end
end

return imp
