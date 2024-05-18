---@diagnostic disable-next-line: deprecated
local api, fn, lsp, uv = vim.api, vim.fn, vim.lsp, vim.loop
local config = require('lspsaga').config
local util = require('lspsaga.util')
local slist = require('lspsaga.slist')
local buf_set_lines = api.nvim_buf_set_lines
local buf_set_extmark = api.nvim_buf_set_extmark
local kind = require('lspsaga.lspkind').kind
local ly = require('lspsaga.layout')
local win = require('lspsaga.window')
local beacon = require('lspsaga.beacon').jump_beacon
local ns = api.nvim_create_namespace('SagaTypehierarchy')

local ch = {}
ch.__index = ch

function ch.__newindex(t, k, v)
  rawset(t, k, v)
end

function ch:clean()
  ly:close()
  slist.list_map(self.list, function(node)
    if node.value.wipe then
      api.nvim_buf_delete(node.value.bufnr, { force = true })
      return
    end
    if node.value.bufnr and api.nvim_buf_is_valid(node.value.bufnr) and node.value.rendered then
      api.nvim_buf_clear_namespace(node.value.bufnr, ns, 0, -1)
      pcall(api.nvim_buf_del_keymap, node.value.bufnr, 'n', config.finder.keys.close)
    end
  end)

  for key, _ in pairs(self) do
    if type(key) ~= 'function' then
      self[key] = nil
    end
  end
end

local function get_method(type)
  local method = {
    'textDocument/prepareTypeHierarchy',
    'typeHierarchy/supertypes',
    'typeHierarchy/subtypes',
  }
  return method[type]
end

---@private
local function pick_type_hierarchy_item(type_hierarchy_items)
  if not type_hierarchy_items then
    return
  end
  if #type_hierarchy_items == 1 then
    return type_hierarchy_items[1]
  end
  local items = {}
  for i, item in pairs(type_hierarchy_items) do
    local entry = item.detail or item.name
    table.insert(items, string.format('%d. %s', i, entry))
  end
  local choice = fn.inputlist(items)
  if choice < 1 or choice > #items then
    return
  end
  return choice
end

function ch:spinner(node)
  if not node then
    return
  end
  local spinner = { '⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷' }
  local frame = 1
  local timer = uv.new_timer()

  local col = node.value.winline == 1 and 0 or node.value.inlevel - 4
  if self.left_bufnr and api.nvim_buf_is_loaded(self.left_bufnr) then
    timer:start(
      0,
      50,
      vim.schedule_wrap(function()
        vim.bo[self.left_bufnr].modifiable = true
        buf_set_extmark(self.left_bufnr, ns, node.value.winline - 1, col, {
          id = node.value.virtid,
          virt_text = { { spinner[frame], 'SagaSpinner' } },
          virt_text_pos = 'overlay',
          hl_mode = 'combine',
        })
        frame = frame + 1 > #spinner and 1 or frame + 1
      end)
    )
  end
  return function()
    if timer and timer:is_active() then
      timer:stop()
      timer:close()
      self:set_toggle_icon(config.ui.expand, node.value.winline - 1, col, node.value.virtid)
    end
  end
end

function ch:set_toggle_icon(icon, row, col, virtid)
  buf_set_extmark(self.left_bufnr, ns, row, col, {
    id = virtid,
    virt_text = { { icon, 'SagaToggle' } },
    virt_text_pos = 'overlay',
  })
end

function ch:set_data_icon(curlnum, data, col)
  buf_set_extmark(self.left_bufnr, ns, curlnum, col, {
    virt_text = { { kind[data.kind][2], 'Saga' .. kind[data.kind][3] } },
    virt_text_pos = 'overlay',
  })
end

function ch:toggle_or_request()
  if self.pending_request then
    vim.notify(
      ('[lspsaga] a request for %s has already been sent, please wait.'):format(self.method),
      vim.log.levels.WARN
    )
    return
  end
  local curlnum = api.nvim_win_get_cursor(0)[1]
  local curnode = slist.find_node(self.list, curlnum)
  if not curnode then
    return
  end
  local client = vim.lsp.get_client_by_id(curnode.value.client_id)
  local next = curnode.next
  if not next or next.value.inlevel <= curnode.value.inlevel then
    local timer_close = self:spinner(curnode)
    local item = curnode.value.item
    self:type_hierarchy(item, client, timer_close, curlnum)
    return
  end
  local level = curnode.value.inlevel

  if curnode.value.expand == true then
    local row = curlnum
    while true do
      row = row + 1
      local l = fn.indent(row)
      if l <= level or l == -1 then
        break
      end
    end
    local count = row - curlnum - 1
    self:set_toggle_icon(
      config.ui.expand,
      curlnum - 1,
      curnode.value.inlevel - 4,
      curnode.value.virtid
    )
    vim.bo[self.left_bufnr].modifiable = true
    buf_set_lines(self.left_bufnr, curlnum, curlnum + count, false, {})
    vim.bo[self.left_bufnr].modifiable = false
    curnode.value.expand = false
    slist.update_winline(curnode, -count)
    return
  end

  if curnode.value.expand == false then
    curnode.value.expand = true
    self:set_toggle_icon(
      config.ui.collapse,
      curlnum - 1,
      curnode.value.inlevel - 4,
      curnode.value.virtid
    )
    local tmp = curnode.next
    local count = 0
    vim.bo[self.left_bufnr].modifiable = true
    while tmp do
      local data = tmp.value.item
      local indent = (' '):rep(tmp.value.inlevel)
      buf_set_lines(self.left_bufnr, curlnum, curlnum, false, { indent .. data.name })
      self:set_toggle_icon(config.ui.expand, curlnum, #indent - 4, tmp.value.virtid)
      self:set_data_icon(curlnum, data, #indent - 2)
      self:render_virtline(curlnum, tmp.value.inlevel)
      curlnum = curlnum + 1
      tmp.value.winline = curlnum
      if tmp.value.expand == false then
        tmp.value.expand = true
      end
      count = count + 1
      if not tmp or (tmp.next and tmp.next.value.inlevel <= level) then
        break
      end
      tmp = tmp.next
    end
    vim.bo[self.left_bufnr].modifiable = false

    if tmp then
      slist.update_winline(tmp, count)
    end
  end
end

local function window_shuttle(winid, right_winid)
  local curwin = api.nvim_get_current_win()
  local target
  if curwin == winid then
    target = right_winid
  elseif curwin == right_winid then
    target = winid
  end
  if target then
    api.nvim_set_current_win(target)
  end
end

function ch:keymap()
  util.map_keys(self.left_bufnr, config.typehierarchy.keys.close, function()
    util.close_win({ self.left_winid, self.right_winid })
    self:clean()
  end)

  util.map_keys(self.left_bufnr, config.typehierarchy.keys.quit, function()
    util.close_win({ self.left_winid, self.right_winid })
    self:clean()
  end)

  util.map_keys(self.left_bufnr, config.typehierarchy.keys.toggle_or_req, function()
    self:toggle_or_request()
  end)

  util.map_keys(self.left_bufnr, config.typehierarchy.keys.shuttle, function()
    window_shuttle(self.left_winid, self.right_winid)
  end)

  local tbl = { 'edit', 'vsplit', 'split', 'tabe' }
  for _, action in ipairs(tbl) do
    util.map_keys(self.left_bufnr, config.typehierarchy.keys[action], function()
      local curlnum = api.nvim_win_get_cursor(0)[1]
      local curnode = slist.find_node(self.list, curlnum)
      if not curnode then
        return
      end
      local client = lsp.get_client_by_id(curnode.value.client_id)
      if not client then
        return
      end
      local data = curnode.value.item
      local start = data.selectionRange.start
      self:clean()
      local restore = win:minimal_restore()
      vim.cmd(action)
      local uri = data.uri
      if not string.match(uri, '^[^:]+://') then -- not uri
        uri = vim.uri_from_fname(uri)
      end
      vim.lsp.util.jump_to_location({
        uri = uri,
        range = {
          start = start,
          ['end'] = start,
        },
      }, client.offset_encoding)
      restore()
      beacon({ start.line, 0 }, #api.nvim_get_current_line())
    end)
  end
end

function ch:peek_view()
  api.nvim_create_autocmd('CursorMoved', {
    group = api.nvim_create_augroup('SagaCallhierarchy', { clear = true }),
    buffer = self.left_bufnr,
    callback = function()
      if not self.left_winid or not api.nvim_win_is_valid(self.left_winid) then
        return
      end
      local curlnum, curcol = unpack(api.nvim_win_get_cursor(self.left_winid))
      local textwidth = vim.fn.strwidth(api.nvim_get_current_line())
      local win_width = api.nvim_win_get_width(self.left_winid)
      if textwidth - curcol >= win_width - 5 then
        vim.fn.winrestview({ leftcol = win_width - 5 })
      end

      local curnode = slist.find_node(self.list, curlnum)
      if not curnode then
        return
      end
      local data = curnode.value.item
      curnode.value.bufnr = vim.uri_to_bufnr(data.uri)
      if not api.nvim_buf_is_loaded(curnode.value.bufnr) then
        fn.bufload(curnode.value.bufnr)
        curnode.value.wipe = true
      end
      local range = data.selectionRange
      api.nvim_win_set_buf(self.right_winid, curnode.value.bufnr)
      api.nvim_set_option_value('winhl', 'Normal:SagaNormal,FloatBorder:SagaBorder', {
        scope = 'local',
        win = self.right_winid,
      })
      curnode.value.rendered = true
      vim.bo[curnode.value.bufnr].filetype = vim.bo[self.main_buf].filetype
      local client = vim.lsp.get_client_by_id(curnode.value.client_id)
      if not client then
        return
      end
      local col = lsp.util._get_line_byte_from_position(
        curnode.value.bufnr,
        range.start,
        client.offset_encoding
      )

      local right_bufnr = vim.api.nvim_win_get_buf(self.right_winid)
      local total_lines = vim.api.nvim_buf_line_count(right_bufnr)
      if range.start.line >= 0 and range.start.line < total_lines then
        api.nvim_win_set_cursor(self.right_winid, { range.start.line + 1, col })
      end
      api.nvim_buf_add_highlight(
        curnode.value.bufnr,
        ns,
        'SagaSearch',
        range.start.line,
        col,
        lsp.util._get_line_byte_from_position(
          curnode.value.bufnr,
          range['end'],
          client.offset_encoding
        )
      )
      util.map_keys(curnode.value.bufnr, config.typehierarchy.keys.shuttle, function()
        window_shuttle(self.left_winid, self.right_winid)
      end)

      util.map_keys(curnode.value.bufnr, config.typehierarchy.keys.close, function()
        ly:close()
        self:clean()
      end)
    end,
    desc = '[Lspsaga] typehierarchy peek preview',
  })
end

function ch:render_virtline(row, inlevel)
  for i = 1, inlevel - 4, 2 do
    local virt = {}
    if i + 2 > inlevel - 4 then
      virt = {
        { config.ui.lines[2], 'SagaVirtLine' },
        { config.ui.lines[4], 'SagaVirtLine' },
      }
    else
      virt = {
        { config.ui.lines[3], 'SagaVirtLine' },
      }
    end
    buf_set_extmark(self.left_bufnr, ns, row, i - 1, {
      virt_text = virt,
      virt_text_pos = 'overlay',
    })
  end
end

function ch:type_hierarchy(item, client, timer_close, curlnum)
  self.pending_request = true
  client.request(self.method, { item = item }, function(_, res)
    self.pending_request = false
    curlnum = curlnum or 0
    local inlevel = curlnum == 0 and 2 or fn.indent(curlnum)
    local curnode = slist.find_node(self.list, curlnum)

    if curnode then
      timer_close()
    end

    if not res or vim.tbl_isempty(res) then
      vim.notify('[lspsaga] typehierarchy result is empty', vim.log.levels.WARN)
      return
    end

    if not self.left_winid or not api.nvim_win_is_valid(self.left_winid) then
      local height = bit.rshift(vim.o.lines, 1) - 4
      local win_width = api.nvim_win_get_width(0)
      self.left_bufnr, self.left_winid, self.right_bufnr, self.right_winid = ly:new(self.layout)
        :left(height, math.floor(win_width * config.typehierarchy.left_width))
        :bufopt({
          ['filetype'] = 'sagatypehierarchy',
          ['buftype'] = 'nofile',
          ['bufhidden'] = 'wipe',
        })
        :right()
        :bufopt({
          ['buftype'] = 'nofile',
          ['bufhidden'] = 'wipe',
        })
        :done()
      self:peek_view()
      self:keymap()
    end

    local indent = (' '):rep(inlevel + 2)

    if curnode then
      curnode.value.expand = true
      self:set_toggle_icon(config.ui.collapse, curlnum - 1, inlevel - 4, curnode.value.virtid)
    end
    vim.bo[self.left_bufnr].modifiable = true

    for _, data in ipairs(res) do
      local val = {}
      val.item = data
      val.client_id = client.id
      val.inlevel = #indent
      buf_set_lines(
        self.left_bufnr,
        curlnum,
        curlnum == 0 and -1 or curlnum,
        false,
        { indent .. data.name }
      )
      val.virtid = uv.hrtime()
      self:set_toggle_icon(config.ui.expand, curlnum, #indent - 4, val.virtid)
      self:set_data_icon(curlnum, data, #indent - 2)
      if curlnum ~= 0 then
        self:render_virtline(curlnum, #indent)
      else
        api.nvim_win_set_cursor(self.left_winid, { 1, 4 })
      end
      curlnum = curlnum + 1
      val.winline = curlnum
      val.client_id = client.id
      if not curnode then
        slist.tail_push(self.list, val)
      else
        slist.insert_node(curnode, val)
        curnode = curnode.next
      end
    end
    vim.bo[self.left_bufnr].modifiable = false

    if curnode and curnode.next then
      slist.update_winline(curnode, #res)
    end
  end)
end

function ch:send_prepare_type()
  if self.pending_request then
    vim.notify('[lspsaga] a request has already been sent, please wait.')
    return
  end
  self.main_buf = api.nvim_get_current_buf()
  local clients = util.get_client_by_method(get_method(1))
  if #clients == 0 then
    vim.notify('[lspsaga] typehierarchy is not supported by the clients of the current buffer')
    return
  end
  local client
  if #clients == 1 then
    client = clients[1]
  else
    local client_items = { 'Select client: ' }
    for i, cli in ipairs(clients) do
      table.insert(client_items, string.format('%d. %s', i, cli.name))
    end

    local choice = vim.fn.inputlist(client_items)
    if choice == 0 or choice > #clients then
      api.nvim_err_writeln('[Lspsaga] wrong choice for select client')
      return
    end
    client = clients[choice]
  end
  self.list = slist.new()

  local params = lsp.util.make_position_params()
  client.request(get_method(1), params, function(_, result, ctx)
    if api.nvim_get_current_buf() ~= ctx.bufnr then
      return
    end
    local item = pick_type_hierarchy_item(result)
    self:type_hierarchy(item, client)
  end, self.main_buf)
end

function ch:send_method(t, args)
  self.method = get_method(t)
  self.layout = config.typehierarchy.layout
  if vim.tbl_contains(args, '++normal') then
    self.layout = 'normal'
  elseif vim.tbl_contains(args, '++float') then
    self.layout = 'float'
  end
  self:send_prepare_type()
end

return setmetatable({}, ch)
