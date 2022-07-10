local ot = {}
local api = vim.api
local cache = require('lspsaga.symbolwinbar').symbol_cache
local kind = require('lspsaga.lspkind')
local hi_prefix = 'LSOutline'

local function nodes_with_icon(tbl, nodes,hi_tbl)
  local icon,hi = '',''

  for _, node in pairs(tbl) do
    icon = kind[node.kind][2]
    hi = hi_prefix ..kind[node.kind][1]
    table.insert(nodes, '  ' ..icon .. node.name)
    table.insert(hi_tbl, hi)

    if node.children ~= nil and next(node.children) ~= nil then
      nodes_with_icon(node.children, nodes,hi_tbl)
    end
  end
end

local function get_all_nodes()
  local symbols, nodes,hi_tbl = {}, {},{}
  local current_buf = api.nvim_get_current_buf()
  if cache[current_buf] ~= nil and next(cache[current_buf][2]) ~= nil then
    symbols = cache[current_buf][2]
  end

  nodes_with_icon(symbols, nodes,hi_tbl)

  return nodes,hi_tbl
end

local function set_local()
  local local_options = {
		bufhidden = "wipe",
    number = false,
    relativenumber = false,
    filetype = 'lspsagaoutline',
    buftype = 'nofile',
    wrap = false,
    signcolumn = "no",
    matchpairs = "",
    buflisted = false,
    list = false,
    spell = false,
    cursorcolumn = false,
    cursorline = false
  }
  for opt, val in pairs(local_options) do
    vim.opt_local[opt] = val
  end
end

local function gen_outline_hi()
  for _,v in pairs(kind) do
    api.nvim_set_hl(0,hi_prefix .. v[1], { fg = v[3] })
  end
end

function ot.render_outline()
  gen_outline_hi()
  local nodes,hi_tbl = get_all_nodes()
  vim.cmd('vsplit')
  vim.cmd('vertical resize 30')
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(true, true)
  api.nvim_win_set_buf(win, buf)

  set_local()

  api.nvim_buf_set_lines(buf, 0, -1, false, nodes)

  for i,hi in pairs(hi_tbl) do
    api.nvim_buf_add_highlight(buf,0, hi , i -1 ,0,-1)
  end

end

return ot
