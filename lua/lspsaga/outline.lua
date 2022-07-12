local ot = {}
local api = vim.api
local cache = require('lspsaga.symbolwinbar').symbol_cache
local kind = require('lspsaga.lspkind')
local hi_prefix = 'LSOutline'
local fold_prefix = 'LSOutlinePrefix'
local space = '  '
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local group = require('lspsaga').saga_group
local max_preview_lines = require('lspsaga').config_values.max_preview_lines
local outline_width = 30

local function nodes_with_icon(tbl,nodes,hi_tbl,level)
  local current_buf = api.nvim_get_current_buf()
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
      if ot[current_buf].preview_contents == nil then
        ot[current_buf].preview_contents = {}
      end
      local range = node.location ~= nil and node.location.range or node.range
      local _end_line = range['end'].line + 1
      local content = api.nvim_buf_get_lines(current_buf,range.start.line,_end_line,false)
      table.insert(ot[current_buf].preview_contents,content)
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
    cursorline = false,
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

function ot.set_foldtext()
  local line = vim.fn.getline(vim.v.foldstart)
  return line
end

function ot.set_fold()
  local cur_indent = vim.fn.indent(vim.v.lnum)
  local next_indent = vim.fn.indent(vim.v.lnum + 1)
  if cur_indent == next_indent then
    return (cur_indent/vim.bo.shiftwidth) - 1
  elseif next_indent < cur_indent then
    return (cur_indent/vim.bo.shiftwidth) - 1
  elseif next_indent > cur_indent then
    return '>' .. (next_indent/vim.bo.shiftwidth) - 1
  end
end

function ot:auto_preview(bufnr)
  if self[bufnr] == nil and next(self[bufnr]) == nil then
    return
  end

  local ok,preview_data = pcall(api.nvim_win_get_var,0,'outline_preview_win')
  if ok then
    window.nvim_close_valid_window(preview_data[2])
  end

  local current_line = api.nvim_win_get_cursor(0)[1]
  local content = self[bufnr].preview_contents[current_line]

  local WIN_WIDTH = api.nvim_get_option('columns')
  local max_width = math.floor(WIN_WIDTH * 0.5)
  local max_height = #content

  if max_height > max_preview_lines then
    max_height = max_preview_lines
  end

  local opts = {
    relative = 'editor',
    style = 'minimal',
    height = max_height,
    width = max_width,
    row = current_line - 1,
    col = WIN_WIDTH - outline_width,
    anchor = 'NE'
  }

  local content_opts = {
    contents = content,
    filetype = self[bufnr].ft,
    highlight = 'LSOutlinePreview',
  }

  local preview_bufnr,preview_winid = window.create_win_with_border(content_opts,opts)
  api.nvim_win_set_var(0,'outline_preview_win',{preview_bufnr,preview_winid})

  local events = {'CursorMoved','BufLeave'}
  local outline_bufnr = api.nvim_get_current_buf()
  vim.defer_fn(function()
    libs.close_preview_autocmd(outline_bufnr,preview_winid,events)
  end,0)
end

function ot.render_outline()
  local current_buf = api.nvim_get_current_buf()
  ot[current_buf] = { ft = vim.bo.filetype}

  gen_outline_hi()
  local nodes,hi_tbl = get_all_nodes()
  vim.cmd('vsplit')
  vim.cmd('vertical resize '.. outline_width)
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(true, true)
  api.nvim_win_set_buf(win, buf)

  set_local()

  api.nvim_buf_set_lines(buf, 0, -1, false, nodes)

  api.nvim_buf_set_option(buf,'modifiable',false)

  for i,hi in pairs(hi_tbl) do
    api.nvim_buf_add_highlight(buf,0, hi , i -1 ,0,-1)
  end

  api.nvim_create_autocmd('CursorMoved',{
    group = group,
    buffer = buf,
    callback = function()
      ot:auto_preview(current_buf)
    end,
  })

end

return ot
