local api, fn, lsp, uv = vim.api, vim.fn, vim.lsp, vim.loop
local config = require('lspsaga').config
local libs = require('lspsaga.libs')
local call_conf, ui = config.callhierarchy, config.ui
local insert = table.insert

local ctx = {}

local ch = {}
function ch.__index(_, k, _)
  return ch[k]
end

function ch.__newindex(t, k, v)
  rawset(t, k, v)
end

local function clean_ctx()
  for k, _ in pairs(ctx) do
    ctx[k] = nil
  end
end

local function get_method(type)
  local method = {
    'textDocument/prepareCallHierarchy',
    'callHierarchy/incomingCalls',
    'callHierarchy/outgoingCalls',
  }
  return method[type]
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
function ch:call_hierarchy(item, parent)
  local spinner = { '⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷' }
  local client = self.client
  local frame = 0
  local curline = api.nvim_win_get_cursor(0)[1]
  if self.bufnr and api.nvim_buf_is_loaded(self.bufnr) and parent then
    local timer = uv.new_timer()
    timer:start(
      0,
      50,
      vim.schedule_wrap(function()
        local text = api.nvim_get_current_line()
        local replace_icon = text:find(ui.expand) and ui.expand or ui.collaspe
        if self.pending_request then
          if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
            api.nvim_win_close(self.preview_winid, true)
            self.preview_winid = nil
          end
          self.pending_request = true
          local next = frame + 1 == 9 and 1 or frame + 1
          if text:find(replace_icon) then
            text = text:gsub(replace_icon, spinner[next])
          else
            text = text:gsub(spinner[frame], spinner[next])
          end
          local col_start = text:find(spinner[next])
          vim.bo[self.bufnr].modifiable = true
          api.nvim_buf_set_lines(self.bufnr, curline - 1, curline, false, { text })
          frame = frame + 1 == 9 and 1 or frame + 1
          api.nvim_buf_add_highlight(
            self.bufnr,
            0,
            'FinderSpinner',
            curline - 1,
            col_start,
            col_start + #spinner[next]
          )

          if parent then
            for group, scope in pairs(parent.highlights) do
              if not group:find('Saga') then
                api.nvim_buf_add_highlight(self.bufnr, 0, group, curline - 1, scope[1], scope[2])
                break
              end
            end
          end
        end

        if not self.pending_request and not timer:is_closing() then
          timer:stop()
          timer:close()
          text = text:gsub(spinner[frame], replace_icon)
          if vim.bo[self.bufnr].modifiable then
            api.nvim_buf_set_lines(self.bufnr, curline - 1, curline, false, { text })
          end
          vim.bo[self.bufnr].modifiable = false
          self.pending_request = false
        end
      end)
    )
  end

  self.pending_request = true
  client.request(self.method, { item = item }, function(_, res)
    self.pending_request = false
    if not res or next(res) == nil then
      return
    end
    local kind = require('lspsaga.highlight').get_kind()
    if not parent then
      local icons = {}
      for i, v in pairs(res) do
        local target = v.from and v.from or v.to
        table.insert(icons, kind[target.kind])
        local expand_collaspe = '  ' .. ui.expand
        local icon = kind[target.kind][2]
        insert(self.data, {
          target = target,
          name = expand_collaspe .. icon .. target.name,
          highlights = {
            ['SagaCollaspe'] = { 0, #expand_collaspe },
            ['LSOutline' .. kind[target.kind][1]] = { #expand_collaspe, #expand_collaspe + #icon },
          },
          winline = i + 1,
          expand = false,
          children = {},
          requested = false,
        })
      end
      self:render_win()
      return
    end

    vim.bo.modifiable = true
    parent.requested = true
    parent.expand = true
    parent.name = parent.name:gsub(ui.expand, ui.collaspe)
    api.nvim_buf_set_lines(self.bufnr, parent.winline - 1, parent.winline, false, {
      parent.name,
    })

    local _, level = parent.name:find('%s+')
    local indent = string.rep(' ', level + 1)

    local tbl = {}
    for i, v in pairs(res) do
      local target = v.from and v.from or v.to
      local expand_collaspe = indent .. ui.expand
      local icon = kind[target.kind][2]
      insert(parent.children, {
        target = target,
        name = expand_collaspe .. icon .. target.name,
        highlights = {
          ['SagaCollaspe'] = { 0, #expand_collaspe },
          ['LSOutline' .. kind[target.kind][1]] = { #expand_collaspe, #expand_collaspe + #icon },
        },
        winline = parent.winline + i,
        expand = false,
        children = {},
        requested = false,
      })
      insert(tbl, expand_collaspe .. icon .. target.name)
    end

    api.nvim_buf_set_lines(self.bufnr, parent.winline, parent.winline, false, tbl)
    for group, scope in pairs(parent.highlights) do
      api.nvim_buf_add_highlight(self.bufnr, 0, group, parent.winline - 1, scope[1], scope[2])
    end

    for _, v in pairs(parent.children) do
      for group, scopes in pairs(v.highlights) do
        api.nvim_buf_add_highlight(self.bufnr, 0, group, v.winline - 1, scopes[1], scopes[2])
      end
    end
    vim.bo.modifiable = false
    self:change_node_winline(parent, #res)
  end)
end

function ch:send_prepare_call()
  self.main_buf = api.nvim_get_current_buf()

  local params = lsp.util.make_position_params()
  lsp.buf_request(0, get_method(1), params, function(_, result, data)
    local call_hierarchy_item = pick_call_hierarchy_item(result)
    self.client = lsp.get_client_by_id(data.client_id)
    self:call_hierarchy(call_hierarchy_item)
  end)
end

function ch:expand_collaspe()
  local node = self:get_node_at_cursor()
  if not node then
    return
  end

  if not node.expand then
    if not node.requested then
      if not self.pending_request then
        self:call_hierarchy(node.target, node)
      end
    else
      node.name = node.name:gsub(ui.expand, ui.collaspe)
      node.highlights['SagaCollaspe'] = { unpack(node.highlights['SagaExpand']) }
      node.highlights['SagaExpand'] = nil
      vim.bo.modifiable = true
      api.nvim_buf_set_lines(self.bufnr, node.winline - 1, node.winline, false, {
        node.name,
      })
      local tbl = {}
      for i, v in ipairs(node.children) do
        v.winline = node.winline + i
        insert(tbl, v.name)
      end
      node.expand = true
      api.nvim_buf_set_lines(self.bufnr, node.winline, node.winline, false, tbl)
      for group, scope in pairs(node.highlights) do
        api.nvim_buf_add_highlight(self.bufnr, 0, group, node.winline - 1, scope[1], scope[2])
      end
      vim.bo.modifiable = false
      for _, child in pairs(node.children) do
        for group, scope in pairs(child.highlights) do
          api.nvim_buf_add_highlight(self.bufnr, 0, group, child.winline - 1, scope[1], scope[2])
        end
      end
      self:change_node_winline(node, #node.children)
    end
    return
  end

  local cur_line = api.nvim_win_get_cursor(0)[1]
  local text = api.nvim_get_current_line()
  text = text:gsub(ui.collaspe, ui.expand)
  vim.bo[self.bufnr].modifiable = true
  api.nvim_buf_set_lines(self.bufnr, cur_line - 1, cur_line + #node.children, false, { text })
  node.expand = false
  vim.bo[self.bufnr].modifiable = false
  node.highlights['SagaExpand'] = { unpack(node.highlights['SagaCollaspe']) }
  node.highlights['SagaCollaspe'] = nil

  for group, scope in pairs(node.highlights) do
    api.nvim_buf_add_highlight(self.bufnr, 0, group, cur_line - 1, scope[1], scope[2])
  end

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
    if self.winid and api.nvim_win_is_valid(self.winid) then
      api.nvim_win_close(self.winid, true)
      if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
        api.nvim_win_close(self.preview_winid, true)
      end
      clean_ctx()
    end
  end, opt)

  keymap('n', keys.expand_collaspe, function()
    self:expand_collaspe()
  end, opt)

  keymap('n', keys.jump, function()
    if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
      local node = self:get_node_at_cursor()
      if not node then
        return
      end
      api.nvim_set_current_win(self.preview_winid)
      api.nvim_win_set_cursor(
        self.preview_winid,
        { node.target.selectionRange.start.line + 1, node.target.selectionRange.start.character }
      )
    end
  end, opt)

  for action, key in pairs({
    edit = keys.edit,
    vsplit = keys.vsplit,
    split = keys.split,
    tabe = keys.tabe,
  }) do
    vim.keymap.set('n', key, function()
      local node = self:get_node_at_cursor()
      if not node then
        return
      end
      if api.nvim_buf_is_loaded(self.file_buf) then
        api.nvim_buf_delete(self.file_buf, { force = true })
      end
      if api.nvim_win_is_valid(self.winid) then
        api.nvim_win_close(self.winid, true)
      end
      if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
        api.nvim_win_close(self.preview_winid, true)
      end
      vim.cmd(action .. ' ' .. vim.uri_to_fname(node.target.uri))
      api.nvim_win_set_cursor(
        0,
        { node.target.selectionRange.start.line + 1, node.target.selectionRange.start.character }
      )
      local width = #api.nvim_get_current_line()
      libs.jump_beacon({ node.target.selectionRange.start.line, 0 }, width)
      clean_ctx()
    end, opt)
  end
end

function ch:render_win()
  local content = {}
  insert(content, self.cword)

  for _, v in pairs(self.data) do
    insert(content, v.name)
  end

  local content_opt = {
    contents = content,
    filetype = 'lspsagacallhierarchy',
    buftype = 'nofile',
    enter = true,
    highlight = {
      normal = 'CallHierarchyNormal',
      border = 'CallHierarchyBorder',
    },
  }

  local opt = {
    relative = 'editor',
    row = math.floor(vim.o.lines * 0.2),
    col = math.floor(vim.o.columns * 0.1),
    height = math.floor(vim.o.lines * 0.2),
    width = math.floor(vim.o.columns * 0.4),
    no_size_override = true,
  }

  if fn.has('nvim-0.9') == 1 then
    local theme = require('lspsaga').theme()
    local icon = self.method == 'callHierarchy/incomingCalls' and ui.incoming or ui.outgoing
    opt.title = {
      { theme.left, 'TitleSymbol' },
      { icon, 'TitleIcon' },
      { ' ' .. self.method:match('/(%w+)Calls$'), 'TitleString' },
      { theme.right, 'TitleSymbol' },
    }
  end
  self.bufnr, self.winid = self.window.create_win_with_border(content_opt, opt)
  api.nvim_create_autocmd('CursorMoved', {
    buffer = self.bufnr,
    callback = function()
      if not self.pending_request then
        self:preview()
      end
    end,
  })

  api.nvim_buf_add_highlight(self.bufnr, 0, 'LSOutlinePackage', 0, 0, -1)

  for i, items in pairs(self.data) do
    for group, scope in pairs(items.highlights) do
      api.nvim_buf_add_highlight(self.bufnr, 0, group, i, scope[1], scope[2])
    end
  end

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

  get_node(self.data)
end

function ch:get_node_at_cursor()
  local cur_line = api.nvim_win_get_cursor(0)[1]
  if cur_line == 1 then
    return
  end
  local node

  local function get_node(data)
    for _, v in pairs(data) do
      if v.winline == cur_line then
        node = v
      end
      if v.children then
        get_node(v.children)
      end
    end
  end

  get_node(self.data)
  return node
end

function ch:get_preview_data()
  local node = self:get_node_at_cursor()
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
  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    api.nvim_win_close(self.preview_winid, true)
  end

  local data = self:get_preview_data()
  if not data then
    return
  end

  local opt = {
    relative = 'editor',
    width = math.floor(vim.o.columns * 0.7),
    height = math.floor(vim.o.lines * 0.4),
    no_size_override = true,
  }

  local win_conf = api.nvim_win_get_config(self.winid)
  if vim.o.columns - (4 + win_conf.col[false] + win_conf.width) > opt.width then
    opt.row = win_conf.row[false]
    opt.col = win_conf.col[false] + win_conf.width + 4
  else
    opt.row = win_conf.row[false] + win_conf.height + 4
    opt.col = win_conf.col[false]
  end

  local content_opt = {
    contents = {},
    highlight = {
      border = 'ActionPreviewBorder',
      normal = 'CallHierarchyNormal',
    },
    enter = false,
  }

  if fn.has('nvim-0.9') == 1 then
    local fname_parts = libs.get_path_info(data[1], 2)
    local tbl = libs.icon_from_devicon(vim.bo[self.main_buf].filetype, true)
    local theme = require('lspsaga').theme()
    opt.title = {
      { theme.left, 'TitleSymbol' },
      { (tbl[1] or '') .. ' ', 'TitleFileIcon' },
      { table.concat(fname_parts or {}, libs.path_sep), 'TitleString' },
      { theme.right, 'TitleSymbol' },
    }
    if #tbl == 2 then
      api.nvim_set_hl(0, 'TitleFileIcon', {
        background = config.ui.colors.title_bg,
        foreground = tbl[2],
      })
    end
  end

  self.preview_bufnr, self.preview_winid = self.window.create_win_with_border(content_opt, opt)
  if config.symbol_in_winbar.enable then
    api.nvim_win_set_var(self.preview_winid, 'disable_winbar', true)
  end
  api.nvim_win_set_buf(self.preview_winid, data[1])
  self.file_buf = data[1]
  vim.bo[data[1]].filetype = vim.bo[self.main_buf].filetype
  vim.bo[data[1]].modifiable = true
  api.nvim_win_set_cursor(self.preview_winid, { data[2].start.line, data[2].start.character })
  vim.wo[self.preview_winid].signcolumn = 'no'
end

function ch:incoming_calls()
  self.cword = fn.expand('<cword>')
  self.method = get_method(2)
  self.window = require('lspsaga.window')
  self.data = {}
  self:send_prepare_call()
end

function ch:outgoing_calls()
  self.cword = fn.expand('<cword>')
  self.method = get_method(3)
  self.window = require('lspsaga.window')
  self.data = {}
  self:send_prepare_call()
end

return setmetatable(ctx, ch)
