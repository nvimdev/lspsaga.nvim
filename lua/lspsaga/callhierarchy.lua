local api, fn, lsp, uv = vim.api, vim.fn, vim.lsp, vim.loop
local config = require('lspsaga').config
local libs = require('lspsaga.libs')
local window = require('lspsaga.window')
local call_conf, ui = config.callhierarchy, config.ui

local ctx = {}

local ch = {}
ch.__index = ch

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
        local replace_icon = text:find(ui.expand) and ui.expand or ui.collapse
        if self.pending_request then
          self.pending_request = false
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
    if not res or vim.tbl_isempty(res) then
      return
    end

    local kind = require('lspsaga.lspkind').get_kind()
    if not parent then
      local icons = {}
      for i, v in pairs(res) do
        local target = v.from and v.from or v.to
        icons[#icons + 1] = kind[target.kind]
        local expand_collapse = '  ' .. ui.expand
        local icon = kind[target.kind][2]
        self.data[#self.data + 1] = {
          target = target,
          name = expand_collapse .. icon .. target.name,
          highlights = {
            ['SagaCollapse'] = { 0, #expand_collapse },
            ['SagaWinbar' .. kind[target.kind][1]] = { #expand_collapse, #expand_collapse + #icon },
          },
          winline = i + 1,
          expand = false,
          children = {},
          requested = false,
        }
      end
      self:render_win()
      return
    end

    vim.bo.modifiable = true
    parent.requested = true
    parent.expand = true
    parent.name = parent.name:gsub(ui.expand, ui.collapse)
    api.nvim_buf_set_lines(self.bufnr, parent.winline - 1, parent.winline, false, {
      parent.name,
    })

    local _, level = parent.name:find('%s+')
    local indent = string.rep(' ', level + 1)

    local tbl = {}
    for i, v in pairs(res) do
      local target = v.from and v.from or v.to
      local expand_collapse = indent .. ui.expand
      local icon = kind[target.kind][2]
      parent.children[#parent + 1] = {
        target = target,
        name = expand_collapse .. icon .. target.name,
        highlights = {
          ['SagaCollapse'] = { 0, #expand_collapse },
          ['SagaWinbar' .. kind[target.kind][1]] = { #expand_collapse, #expand_collapse + #icon },
        },
        winline = parent.winline + i,
        expand = false,
        children = {},
        requested = false,
      }
      tbl[#tbl + 1] = expand_collapse .. icon .. target.name
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
  if self.pending_request then
    vim.notify('there is already a request please wait.')
    return
  end
  self.main_buf = api.nvim_get_current_buf()

  local params = lsp.util.make_position_params()
  lsp.buf_request(0, get_method(1), params, function(_, result, data)
    local call_hierarchy_item = pick_call_hierarchy_item(result)
    self.client = lsp.get_client_by_id(data.client_id)
    self:call_hierarchy(call_hierarchy_item)
  end)
end

function ch:expand_collapse()
  local node = self:get_node_at_cursor()
  if not node then
    return
  end

  if not node.expand then
    if not node.requested and not self.pending_request then
      self:call_hierarchy(node.target, node)
    else
      node.name = node.name:gsub(ui.expand, ui.collapse)
      node.highlights['SagaCollapse'] = { unpack(node.highlights['SagaExpand']) }
      node.highlights['SagaExpand'] = nil
      vim.bo.modifiable = true
      api.nvim_buf_set_lines(self.bufnr, node.winline - 1, node.winline, false, {
        node.name,
      })
      local tbl = {}
      for i, v in ipairs(node.children) do
        v.winline = node.winline + i
        tbl[#tbl + 1] = v.name
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
  text = text:gsub(ui.collapse, ui.expand)
  vim.bo[self.bufnr].modifiable = true
  api.nvim_buf_set_lines(self.bufnr, cur_line - 1, cur_line + #node.children, false, { text })
  node.expand = false
  vim.bo[self.bufnr].modifiable = false
  node.highlights['SagaExpand'] = { unpack(node.highlights['SagaCollapse']) }
  node.highlights['SagaCollapse'] = nil

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

  keymap('n', keys.expand_collapse, function()
    self:expand_collapse()
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
  local content = { self.cword }

  for _, v in pairs(self.data) do
    content[#content + 1] = v.name
  end

  local side_char = window.border_chars()['top'][config.ui.border]
  local content_opt = {
    contents = content,
    filetype = 'lspsagacallhierarchy',
    buftype = 'nofile',
    enter = true,
    border_side = {
      ['right'] = ' ',
      ['righttop'] = side_char,
      ['rightbottom'] = side_char,
    },
    highlight = {
      normal = 'CallHierarchyNormal',
      border = 'CallHierarchyBorder',
    },
  }

  local cur_winline = fn.winline()
  local max_height = math.floor(vim.o.lines * 0.4)
  if vim.o.lines - cur_winline - 6 < max_height then
    vim.cmd('normal! zz')
    local keycode = api.nvim_replace_termcodes('5<C-e>', true, false, true)
    api.nvim_feedkeys(keycode, 'x', false)
  end

  local opt = {
    relative = 'editor',
    row = fn.winline() + 1,
    col = 10,
    height = math.floor(vim.o.lines * 0.4),
    width = math.floor(vim.o.columns * 0.3),
    no_size_override = true,
  }

  if fn.has('nvim-0.9') == 1 and config.ui.title then
    local icon = self.method == 'callHierarchy/incomingCalls' and ui.incoming or ui.outgoing
    opt.title = {
      { icon, 'ArrowIcon' },
    }
    opt.title_pos = 'center'
    api.nvim_set_hl(0, 'ArrowIcon', { link = 'CallHierarchyBorder' })
  end

  self.bufnr, self.winid = window.create_win_with_border(content_opt, opt)
  api.nvim_win_set_cursor(self.winid, { 2, 9 })
  api.nvim_create_autocmd('CursorMoved', {
    buffer = self.bufnr,
    callback = function()
      self:preview()
    end,
  })

  api.nvim_create_autocmd('BufWipeOut', {
    buffer = self.bufnr,
    once = true,
    callback = function()
      window.nvim_close_valid_window({ self.winid, self.preview_winid })
      clean_ctx()
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

local function load_jdt_preview(bufnr, uri)
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].buftype = 'nofile'

  -- This triggers FileType event which should fire up the lsp client if not already running.
  vim.bo[bufnr].filetype = 'java'

  vim.wait(config.request_timeout, function()
    return next(lsp.get_active_clients({ name = 'jdtls', bufnr = bufnr})) ~= nil
  end)
  local client = lsp.get_active_clients({ name = 'jdtls', bufnr = bufnr})[1]
  assert(client, 'Must have a `jdtls` client to load class file or jdt uri')

  local content
  local function handler(err, result)
    assert(not err, vim.inspect(err))
    content = result
    api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(result, '\n', { plain = true }))
    vim.bo[bufnr].modifiable = false
  end

  local params = {
    uri = uri,
  }

  client.request('java/classFileContents', params, handler, bufnr)
  -- Need to block. Otherwise logic could run that sets the cursor to a position
  -- that's still missing.
  vim.wait(config.request_timeout, function() 
    return content ~= nil 
  end)
end

local function get_preview_data(node)
  if not node or vim.tbl_count(node) == 0 then
    return
  end

  local uri = node.target.uri
  local range = node.target.range
  local bufnr = vim.uri_to_bufnr(uri)

  if string.sub(uri, 1, 4) == 'jdt:' then
    load_jdt_preview(bufnr, uri)
  end

  if not api.nvim_buf_is_loaded(bufnr) then
    fn.bufload(bufnr)
  end

  return { bufnr = bufnr, range = range }
end

local function create_preview_window(winid)
  local winconfig = api.nvim_win_get_config(winid)
  local opt = {
    relative = 'editor',
    row = winconfig.row[false],
    height = winconfig.height,
    col = winconfig.col[false] + winconfig.width + 2,
    no_size_override = true,
  }
  opt.width = vim.o.columns - opt.col - 6

  local rtop = window.combine_char()['top'][config.ui.border]
  local rbottom = window.combine_char()['bottom'][config.ui.border]
  local content_opt = {
    contents = {},
    border_side = {
      ['lefttop'] = rtop,
      ['leftbottom'] = rbottom,
    },
    enter = false,
    highlight = {
      normal = 'CallHierarchyNormal',
      border = 'CallHierarchyBorder',
    },
  }

  return window.create_win_with_border(content_opt, opt)
end

function ch:preview()
  local node = self:get_node_at_cursor()
  if not node then
    return
  end

  local data = get_preview_data(node)
  if not data or not data.bufnr then
    return
  end

  if not self.preview_winid or not api.nvim_win_is_valid(self.preview_winid) then
    self.preview_bufnr, self.preview_winid = create_preview_window(self.winid)
  end

  api.nvim_win_set_buf(self.preview_winid, data.bufnr)
  if fn.has('nvim-0.9') == 1 and config.ui.title then
    local path = vim.split(api.nvim_buf_get_name(data.bufnr), libs.path_sep, { trimempty = true })
    local icon = libs.icon_from_devicon(vim.bo[self.main_buf].filetype)
    api.nvim_win_set_config(self.preview_winid, {
      title = {
        { icon[1], icon[2] or 'TitleString' },
        { path[#path], 'TitleString' },
      },
      title_pos = 'center',
    })
  end

  api.nvim_set_option_value(
    'winhl',
    'Normal:finderNormal,FloatBorder:finderPreviewBorder',
    { scope = 'local', win = self.preview_winid }
  )

  -- Check if the cursor position is within the buffer's valid range.
  local buf_line_count = api.nvim_buf_line_count(data.bufnr)
  local cursor_row = data.range.start.line + 1
  local cursor_column = data.range.start.character

  if cursor_row >= 1 and cursor_row <= buf_line_count then
    api.nvim_win_set_cursor(self.preview_winid, { cursor_row, cursor_column })
    vim.bo[data.bufnr].filetype = vim.bo[self.main_buf].filetype
  end
  api.nvim_set_option_value('winbar', '', { scope = 'local', win = self.preview_winid })
end

function ch:send_method(type)
  self.cword = fn.expand('<cword>')
  self.method = get_method(type)
  self.data = {}
  self:send_prepare_call()
end

return setmetatable(ctx, ch)
