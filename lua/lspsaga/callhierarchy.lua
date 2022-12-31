local api, fn, lsp, validate = vim.api, vim.fn, vim.lsp, vim.validate
local window = require('lspsaga.window')
local kind = require('lspsaga.lspkind')
local libs = require('lspsaga.libs')
local ui = require('lspsaga').config_values.ui
local call_conf = require('lspsaga').config_values.call_hierarchy
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
  for k, _ in pairs(ctx) do
    ctx[k] = nil
  end
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
  local choice = fn.inputlist(items)
  if choice < 1 or choice > #items then
    return
  end
  return choice
end

---@private
local function parse_data(tbl)
  local content = {}
  insert(content, ui.collaspe .. fn.expand('<cword>'))
  for _, v in pairs(tbl) do
    insert(content, v.name)
  end
  return content
end

function ch:call_hierarchy(item, parent, level)
  local spinner = { '⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷' }
  local indent = '  '
  local client = ctx.client
  local pending_request = true
  local frame = 0
  if ctx.winbuf and api.nvim_buf_is_loaded(ctx.winbuf) and parent then
    local uv = vim.loop
    local timer = uv.new_timer()
    timer:start(
      0,
      50,
      vim.schedule_wrap(function()
        local text = api.nvim_get_current_line()
        local curline = api.nvim_win_get_cursor(0)[1]
        local replace_icon = text:find(ui.expand) and ui.expand or ui.collaspe
        if pending_request then
          local next = frame + 1 == 9 and 1 or frame + 1
          if text:find(replace_icon) then
            text = text:gsub(replace_icon, spinner[next])
          else
            text = text:gsub(spinner[frame], spinner[next])
          end
          vim.bo[ctx.winbuf].modifiable = true
          api.nvim_buf_set_lines(ctx.winbuf, curline - 1, curline, false, { text })
          frame = frame + 1 == 9 and 1 or frame + 1
        end

        if not pending_request and not timer:is_closing() then
          timer:close()
          text = text:gsub(spinner[frame], replace_icon)
          if vim.bo[ctx.winbuf].modifiable then
            api.nvim_buf_set_lines(ctx.winbuf, curline - 1, curline, false, { text })
          end
          vim.bo[ctx.winbuf].modifiable = false
        end
      end)
    )
  end

  client.request(ctx.method, { item = item }, function(_, res)
    if not res or next(res) == nil then
      return
    end
    if not parent then
      for i, v in pairs(res) do
        local target = v.from and v.from or v.to
        insert(ctx.data, {
          target = target,
          name = indent .. ui.expand .. kind[target.kind][2] .. target.name,
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
    parent.name = parent.name:gsub(ui.expand, ui.collaspe)
    api.nvim_buf_set_lines(ctx.winbuf, parent.winline - 1, parent.winline, false, {
      parent.name,
    })

    level = level == 1 and level + 1 or level
    indent = string.rep(indent, level)

    local tbl = {}
    for i, v in pairs(res) do
      local target = v.from and v.from or v.to
      local name = indent .. ui.expand .. kind[target.kind][2] .. target.name
      insert(parent.children, {
        target = target,
        name = name,
        winline = parent.winline + i,
        expand = false,
        children = {},
        requested = false,
      })
      insert(tbl, name)
    end

    pending_request = false
    api.nvim_buf_set_lines(ctx.winbuf, parent.winline, parent.winline, false, tbl)
    vim.bo.modifiable = false
    self:change_node_winline(parent, #res)
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
    if not node.requested then
      self:call_hierarchy(node.target, node, level)
    else
      node.name = node.name:gsub(ui.expand, ui.collaspe)
      vim.bo.modifiable = true
      api.nvim_buf_set_lines(ctx.winbuf, node.winline - 1, node.winline, false, {
        node.name,
      })
      local tbl = {}
      for i, v in ipairs(node.children) do
        v.winline = node.winline + i
        insert(tbl, v.name)
      end
      node.expand = true
      api.nvim_buf_set_lines(ctx.winbuf, node.winline, node.winline, false, tbl)
      vim.bo.modifiable = false
      self:change_node_winline(node, #node.children)
    end
    return
  end

  local cur_line = api.nvim_win_get_cursor(0)[1]
  local text = api.nvim_get_current_line()
  text = text:gsub(ui.collaspe, ui.expand)
  vim.bo[ctx.winbuf].modifiable = true
  api.nvim_buf_set_lines(ctx.winbuf, cur_line - 1, cur_line + #node.children, false, { text })
  node.expand = false
  vim.bo[ctx.winbuf].modifiable = false
  for _, v in pairs(node.children) do
    v.winline = -1
  end
  self:change_node_winline(node, -#node.children)
end

function ch:apply_map()
  local keys = call_conf.keys
  local keymap = vim.keymap.set
  local opt = { buffer = true, nowait = true }
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

  keymap('n', keys.jump_to_preview, function()
    if ctx.preview_winid and api.nvim_win_is_valid(ctx.preview_winid) then
      api.nvim_set_current_win(ctx.preview_winid)
    end
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
    local icon = ctx.method == method[2] and ui.incoming or ui.outgoing
    opt.title = {
      { icon, 'CallHierarchyIcon' },
      { ' ' .. titles[ctx.method], 'CallHierarchyTitle' },
    }
    opt.title_pos = 'left'
  end
  opt.height = math.floor(vim.o.lines * 0.2)
  opt.width = math.floor(vim.o.columns * 0.4)
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

---@private
local function node_in_parent(parent, node)
  for _, v in pairs(parent.children) do
    if v.name == node.name then
      return true
    end
  end
  return false
end

function ch:change_node_winline(node, factor)
  local found = false
  local function get_node(data)
    for _, v in pairs(data) do
      if found and not node_in_parent(node, v) then
        v.winline = v.winline + factor
      end
      if v.name == node.name then
        found = true
      end
      if v.children then
        get_node(v.children)
      end
    end
  end

  get_node(ctx.data)
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

function ch:get_preview_data()
  local node, _ = self:get_node_at_cursor()
  if not node or vim.tbl_count(node) == 0 then
    return
  end

  local uri = node.target.uri
  local range = node.target.range
  local bufnr = vim.uri_to_bufnr(uri)

  if not api.nvim_buf_is_loaded(bufnr) then
    fn.bufload(bufnr)
  end

  return { bufnr, range }
end

function ch:preview()
  if ctx.preview_winid and api.nvim_win_is_valid(ctx.preview_winid) then
    api.nvim_win_close(ctx.preview_winid, true)
  end

  local opt = {}
  local win_conf = api.nvim_win_get_config(ctx.winid)
  local data = self:get_preview_data()
  if not data then
    return
  end

  opt.col = win_conf.col[false]
  opt.width = math.floor(vim.o.columns * 0.7)
  opt.height = math.floor(vim.o.lines * 0.4)
  opt.no_size_override = true
  opt.relative = 'editor'
  if win_conf.anchor:find('^N') then
    opt.row = win_conf.row[false] - opt.height - 2
  else
    opt.row = win_conf.row[false]
  end

  local content_opt = {
    contents = {},
    enter = false,
  }

  if fn.has('nvim-0.9') == 1 then
    local fname = api.nvim_buf_get_name(data[1])
    local fname_parts = vim.split(fname, libs.path_sep)
    fname_parts = { unpack(fname_parts, #fname_parts - 1, #fname_parts) }
    opt.title = { { table.concat(fname_parts, libs.path_sep) } }
  end

  ctx.preview_bufnr, ctx.preview_winid = window.create_win_with_border(content_opt, opt)
  api.nvim_win_set_buf(ctx.preview_winid, data[1])
  vim.bo[data[1]].filetype = vim.bo[ctx.main_buf].filetype
  vim.bo[data[1]].modifiable = true
  api.nvim_win_set_cursor(ctx.preview_winid, { data[2].start.line, data[2].start.character })
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
