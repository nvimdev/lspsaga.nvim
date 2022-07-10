local ot = {}
local api = vim.api
local cache = require('lspsaga.symbolwinbar').symbol_cache
local kind = require('lspsaga.lspkind')

local function nodes_with_icon(tbl, nodes)
  for _, node in pairs(tbl) do
    local icon = kind[node.kind][2]
    table.insert(nodes, icon .. node.name)

    if node.children ~= nil and next(node.children) ~= nil then
      nodes_with_icon(node.children, nodes)
    end
  end
end

local function get_all_nodes()
  local symbols, nodes = {}, {}
  local current_buf = api.nvim_get_current_buf()
  if cache[current_buf] ~= nil and next(cache[current_buf][2]) ~= nil then
    symbols = cache[current_buf][2]
  end

  nodes_with_icon(symbols, nodes)

  return nodes
end

function ot.render_outline()
  local nodes = get_all_nodes()
  vim.cmd('vsplit')
  vim.cmd('vertical resize 30')
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(true, true)
  api.nvim_win_set_buf(win, buf)
  api.nvim_win_set_option(win, 'number', false)
  api.nvim_buf_set_option(buf, 'filetype', 'lspsagaoutline')
  api.nvim_buf_set_lines(buf, 0, -1, false, nodes)
end

return ot
