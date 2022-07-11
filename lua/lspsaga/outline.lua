local ot = {}
local api = vim.api
local group = require('lspsaga').saga_augroup
local cache = require('lspsaga.symbolwinbar').symbol_cache
local kind = require('lspsaga.lspkind')
local hi_prefix = 'LSOutline'
local fold_prefix = 'LSOutlinePrefix'
local space = '  '
local prefix = '  '

local function nodes_with_icon(tbl,nodes,hi_tbl,level)
  local icon,hi = '',''

  for _, node in pairs(tbl) do
    level = level or 1
    icon = kind[node.kind][2]
    hi = hi_prefix ..kind[node.kind][1]
    local indent = string.rep(space,level)

    -- I think no need to show function param
    if node.kind ~= 14 then
      table.insert(nodes, indent ..icon .. node.name)
      table.insert(hi_tbl, hi)
    end

    if node.children ~= nil and next(node.children) ~= nil then
      nodes_with_icon(node.children, nodes,hi_tbl,level + 1)
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
    foldmethod = 'expr',
    foldexpr = 'v:lua.require("lspsaga.outline").set_fold()',
    foldtext = 'v:lua.require("lspsaga.outline").set_foldtext()',
    fillchars = { eob = "-", fold = " " },
  }
  for opt, val in pairs(local_options) do
    vim.opt_local[opt] = val
  end
end


local function gen_outline_hi()
  for _,v in pairs(kind) do
    api.nvim_set_hl(0,hi_prefix .. v[1], { fg = v[3] })
  end
  api.nvim_set_hl(0,fold_prefix,{fg = '#FF8700'})
end

function ot:cache_cursorline_hi()
  if self.cursorline == nil then
    self.cursorline = api.nvim_get_hl_by_name('CursorLine')
  end
end

function ot.set_foldtext()
  local line = vim.fn.getline(vim.v.foldstart)
  return " ⚡" ..line
end

function ot.set_fold()
  local current_line = api.nvim_win_get_cursor(0)[1]
  local line = vim.fn.getline(current_line)
  local _,cur_indent = line:find('%s+')
  local _,next_indent = vim.fn.getline(current_line + 1):find('%s+')

  if cur_indent < next_indent then
    return '>'..next_indent
  else
    return cur_indent
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

  api.nvim_buf_set_option(buf,'modifiable',false)

  for i,hi in pairs(hi_tbl) do
    api.nvim_buf_add_highlight(buf,0, hi , i -1 ,0,-1)
  end

  api.nvim_create_autocmd({'BufDelete','WinLeave','BufLeave','BufWinLeave'},{
    group = group,
    buffer = buf,
    callback = function()
      if ot.cursorline ~= nil then
        api.nvim_set_hl(0,'CursorLine',ot.cursorline)
      end
    end
  })

  api.nvim_create_autocmd('TextChanged',{
    group = group,
    buffer = buf,
    callback = function()
      print('')
    end
  })

end

return ot
