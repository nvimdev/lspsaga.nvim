local api, fn, lsp, validate = vim.api, vim.fn, vim.lsp, vim.validate
local window = require('lspsaga.window')
local kind = require('lspsaga.lspkind')
local max_preview_lines = require('lspsaga').config_values.max_preview_lines
local call_conf = require('lspsaga').config_values.call_hierarchy
local libs = require('lspsaga.libs')
local insert = table.insert
local method = {
  'textDocument/prepareCallHierarchy',
  'callHierarchy/incomingCalls',
  'callHierarchy/outgoingCalls',
}

local ch = {}

local ctx = {}
function ctx.__newindex(_, k, v)
  rawset(ctx, k, v)
end

local function clean_ctx()
  ctx = {}
end

---@private
local function pick_call_hierarchy_item(call_hierarchy_items)
  if not call_hierarchy_items then
    return
  end
  if #call_hierarchy_items == 1 then
    return call_hierarchy_items[1]
  end
  local items = {}
  for i, item in pairs(call_hierarchy_items) do
    local entry = item.detail or item.name
    table.insert(items, string.format('%d. %s', i, entry))
  end
  local choice = vim.fn.inputlist(items)
  if choice < 1 or choice > #items then
    return
  end
  return choice
end

---@private
local function parse_data(tbl)
  local content = {}
  insert(content, call_conf.collaspe_icon .. fn.expand('<cword>'))
  for _, v in pairs(tbl) do
    insert(content, v.name)
  end
  return content
end

function ch:call_hierarchy(item, parent, level)
  local indent = '  '
  local client = ctx.client
  client.request(ctx.method, { item = item }, function(_, res)
    if not res or next(res) == nil then
      return
    end
    if not parent then
      for i, v in pairs(res) do
        insert(ctx.data, {
          from = v.from,
          name = indent .. call_conf.expand_icon .. kind[v.from.kind][2] .. v.from.name,
          winline = i + 1,
          expand = false,
          children = {},
          requested = false,
        })
      end
      local content = parse_data(ctx.data)
      self:render_win(content)
      return
    end

    vim.bo.modifiable = true
    parent.requested = true
    parent.expand = true
    parent.name = parent.name:gsub(call_conf.expand_icon, call_conf.collaspe_icon)
    api.nvim_buf_set_lines(ctx.winbuf, parent.winline - 1, parent.winline, false, {
      parent.name,
    })

    level = level == 1 and level + 1 or level
    indent = string.rep(indent, level)

    local tbl = {}
    for i, v in pairs(res) do
      local name = indent .. call_conf.expand_icon .. kind[v.from.kind][2] .. v.from.name
      insert(parent.children, {
        from = v.from,
        name = name,
        winline = parent.winline + i,
        expand = false,
        children = {},
        requested = false,
      })
      insert(tbl, name)
    end

    api.nvim_buf_set_lines(ctx.winbuf, parent.winline, parent.winline, false, tbl)
    vim.bo.modifiable = false
  end)
end

function ch:send_prepare_call()
  ctx.main_buf = api.nvim_get_current_buf()

  local params = lsp.util.make_position_params()
  lsp.buf_request(0, method[1], params, function(_, result, data)
    local call_hierarchy_item = pick_call_hierarchy_item(result)
    ctx.client = lsp.get_client_by_id(data.client_id)
    self:call_hierarchy(call_hierarchy_item)
  end)
end

function ch:expand_collaspe()
  local node, level = self:get_node_at_cursor()
  if not node then
    return
  end

  if not node.expand then
    self:call_hierarchy(node.from, node, level)
  end
end

function ch:apply_map()
  local keys = call_conf.keys
  local keymap = vim.keymap.set
  local opt = { buffer = ctx.bufnr, nowait = true }
  keymap('n', keys.quit, function()
    if ctx.winid and api.nvim_win_is_valid(ctx.winid) then
      api.nvim_win_close(ctx.winid, true)
      if ctx.preview_winid and api.nvim_win_is_valid(ctx.preview_winid) then
        api.nvim_win_close(ctx.preview_winid, true)
      end
      clean_ctx()
    end
  end, opt)

  keymap('n', keys.expand_collaspe, function()
    self:expand_collaspe()
  end, opt)
end

function ch:render_win(content)
  validate({
    content = { content, 'table' },
  })
  local content_opt = {
    contents = content,
    enter = true,
    highlight = 'CallHierarchyBorder',
  }

  local opt = {}
  if fn.has('nvim-0.9') == 1 then
    local titles = {
      [method[2]] = 'InComing',
      [method[3]] = 'OutGoing',
    }
    opt.title = {
      { call_conf.incoming_icon, 'CallHierarchyIcon' },
      { ' ' .. titles[ctx.method], 'CallHierarchyTitle' },
    }
    opt.title_pos = 'left'
  end
  opt.height = math.floor(vim.o.lines * 0.2)
  opt.width = math.floor(vim.o.columns * 0.2)
  opt.no_size_override = true
  ctx.winbuf, ctx.winid = window.create_win_with_border(content_opt, opt)
  api.nvim_create_autocmd('CursorMoved', {
    buffer = ctx.winbuf,
    callback = function()
      self:preview()
    end,
  })

  self:apply_map()
end

function ch:get_node_at_cursor()
  local cur_line = api.nvim_win_get_cursor(0)[1]
  if cur_line == 1 then
    return
  end

  local node = {}
  local level = 0

  local function get_node(data)
    for _, v in pairs(data) do
      level = level + 1
      if v.winline == cur_line then
        node = v
        level = level
      end
      if v.children then
        get_node(v.children)
      end
    end
  end

  get_node(ctx.data)

  return node, level
end

function ch:get_preview_content()
  local node, _ = self:get_node_at_cursor()
  if not node or vim.tbl_count(node) == 0 then
    return
  end

  local uri = node.from.uri
  local range = node.from.range
  local bufnr = vim.uri_to_bufnr(uri)

  if not api.nvim_buf_is_loaded(bufnr) then
    fn.bufload(bufnr)
  end

  local lines =
    api.nvim_buf_get_lines(bufnr, range.start.line, range['end'].line + max_preview_lines, false)

  return lines
end

function ch:preview()
  if ctx.preview_winid and api.nvim_win_is_valid(ctx.preview_winid) then
    api.nvim_win_close(ctx.preview_winid, true)
  end

  local opt = {}
  local win_conf = api.nvim_win_get_config(ctx.winid)
  local lines = self:get_preview_content()
  if not lines then
    return
  end
  opt.col = win_conf.col[false]
  opt.width = math.floor(vim.o.columns * 0.7)
  opt.height = math.floor(vim.o.lines * 0.4)
  opt.no_size_override = true
  opt.relative = 'editor'
  opt.row = win_conf.row[false] + win_conf.height + 2 >= vim.o.lines - 6
      and vim.o.lines - win_conf.row[false]
    or win_conf.row[false] + win_conf.height + 2

  local content_opt = {
    contents = lines,
    enter = false,
  }

  if fn.has('nvim-0.9') == 1 then
    opt.title = { { 'Preview' } }
  end

  ctx.preview_bufnr, ctx.preview_winid = window.create_win_with_border(content_opt, opt)
  vim.treesitter.start(ctx.preview_bufnr, vim.bo[ctx.main_buf].filetype)
end

function ch:incoming_calls()
  ctx.method = method[2]
  ctx.data = {}
  self:send_prepare_call()
end

function ch:outgoing_calls()
  ctx.method = method[3]
  ctx.data = {}
  self:send_prepare_call()
end

setmetatable(ch, ctx)

return ch
