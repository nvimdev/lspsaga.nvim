---@diagnostic disable-next-line: deprecated
local api, fn, lsp, uv = vim.api, vim.fn, vim.lsp, vim.loop
local config = require('lspsaga').config
local util = require('lspsaga.util')
local slist = require('lspsaga.slist')
local buf_set_lines = api.nvim_buf_set_lines
local buf_set_extmark = api.nvim_buf_set_extmark
local kind = require('lspsaga.lspkind').kind
local ly = require('lspsaga.layout')
local ns = api.nvim_create_namespace('SagaCallhierarchy')

local ch = {}
ch.__index = ch

function ch.__newindex(t, k, v)
  rawset(t, k, v)
end

function ch:clean()
  for key, _ in pairs(self) do
    if type(key) ~= 'function' then
      self[key] = nil
    end
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

function ch:spinner(node)
  local spinner = { '⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷' }
  local frame = 0
  local timer = uv.new_timer()

  if self.bufnr and api.nvim_buf_is_loaded(self.bufnr) then
    timer:start(0, 50, function()
      vim.schedule(function()
        buf_set_extmark(self.left_bufnr, ns, node.value.winline, #node.value.inlevle - 4, {
          virt_text = { { spinner[frame], 'SagaSpinner' } },
          virt_text_pos = 'overlay',
          hl_mode = 'combine',
        })
      end)
      frame = frame + 1 > #spinner and 1 or frame + 1
    end)
  end
  return timer
end

function ch:set_toggle_icon(icon, row, col, virtid)
  vim.validate({
    virtid = { virtid, 'n' },
  })
  buf_set_extmark(self.left_bufnr, ns, row, col, {
    id = virtid,
    virt_text = { { icon, 'SagaToggle' } },
    virt_text_pos = 'overlay',
  })
end

function ch:toggle_or_request()
  if self.pending_request then
    vim.notify(('[Lspsaga] already have a request for %s'):format(self.method), vim.log.levels.WARN)
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
    local timer = self:spinner()
    local item = self.method == get_method(2) and curnode.value.from or curnode.value.to
    self:call_hierarchy(item, client, timer, curlnum)
    return
  end
  local level = curnode.value.inlevel
  local row = curlnum
  while true do
    row = row + 1
    local l = fn.indent(row)
    if l <= level or l == -1 then
      break
    end
  end
  local count = row - curlnum - 1

  if type(curnode.value.expand) == 'boolean' and curnode.value.expand then
    self:set_toggle_icon(
      config.ui.expand,
      curlnum - 1,
      curnode.value.inlevel - 4,
      curnode.value.virtid
    )
    buf_set_lines(self.left_bufnr, curlnum, curlnum + count, false, {})
    curnode.value.expand = false
    slist.update_winline(curnode, -1)
    return
  end

  if type(curnode.value.expand) == 'boolean' and not curnode.value.expand then
    curnode.value.expand = true
    self:set_toggle_icon(
      config.ui.collapse,
      curlnum - 1,
      curnode.value.inlevel - 4,
      curnode.value.virtid
    )
    local tmp = curnode.next
    count = 0
    while tmp do
      local data = self.method == get_method(2) and tmp.value.from or tmp.value.to
      local indent = (' '):rep(tmp.value.inlevel)
      buf_set_lines(self.left_bufnr, curlnum, curlnum, false, { indent .. data.name })
      self:set_toggle_icon(config.ui.expand, curlnum, #indent - 4, tmp.value.virtid)
      buf_set_extmark(self.left_bufnr, ns, curlnum, #indent - 2, {
        virt_text = { { kind[data.kind][2], 'Saga' .. kind[data.kind][3] } },
        virt_text_pos = 'overlay',
      })
      curlnum = curlnum + 1
      count = count + 1
      if not tmp.next or tmp.next.value.inlevel <= level then
        break
      end
      tmp = tmp.next
    end
    slist.update_winline(curnode, count)
  end
end

function ch:keymap(bufnr, winid, _, right_winid)
  util.map_keys(bufnr, 'n', config.callhierarchy.keys.quit, function()
    util.close_win({ winid, right_winid })
    self:clean()
  end)

  util.map_keys(bufnr, 'n', config.callhierarchy.keys.toggle, function()
    self:toggle_or_request()
  end)
end

function ch:peek_view()
  api.nvim_create_autocmd('CursorMoved', {
    group = api.nvim_create_augroup('SagaCallhierarchy', { clear = true }),
    buffer = self.left_bufnr,
    callback = function()
      if not self.left_winid or not api.nvim_win_is_valid(self.left_winid) then
        return
      end
      local curlnum = api.nvim_win_get_cursor(self.left_winid)[1]
      local curnode = slist.find_node(self.list, curlnum)
      if not curnode then
        return
      end
      local data = self.method == get_method(2) and curnode.value.from or curnode.value.to
      local peek_bufnr = vim.uri_to_bufnr(data.uri)
      vim.bo[peek_bufnr].filetype = vim.bo[self.main_buf].filetype
      local range = data.selectionRange
      api.nvim_win_set_buf(self.right_winid, peek_bufnr)
      api.nvim_win_set_cursor(self.right_winid, { range.start.line + 1, range.start.character + 1 })
    end,
    desc = '[Lspsaga] callhierarchy peek preview',
  })
end

function ch:call_hierarchy(item, client, timer, curlnum)
  self.pending_request = true
  client.request(self.method, { item = item }, function(_, res)
    self.pending_request = false
    if timer and timer:is_active() then
      timer:stop()
      timer:close()
    end

    if not res or vim.tbl_isempty(res) then
      return
    end
    if not self.left_winid or not api.nvim_win_is_valid(self.left_winid) then
      local height = bit.rshift(vim.o.lines, 1) - 4
      self.left_bufnr, self.left_winid, self.right_bufnr, self.right_winid = ly:new(self.layout)
        :left(height, 20)
        :right(20)
        :done(function(bufnr, winid, _, right_winid)
          self:keymap(bufnr, winid, _, right_winid)
        end)
      self:peek_view()
    end

    curlnum = curlnum or 0
    local inlevel = curlnum == 0 and 2 or fn.indent(curlnum)
    local curnode = slist.find_node(self.list, curlnum)
    local indent = (' '):rep(inlevel + 2)

    if curnode then
      curnode.value.expand = true
      self:set_toggle_icon(config.ui.collapse, curlnum - 1, inlevel - 4, curnode.value.virtid)
    end

    for _, val in ipairs(res) do
      local data = self.method == get_method(2) and val.from or val.to
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
      buf_set_extmark(self.left_bufnr, ns, curlnum, #indent - 2, {
        virt_text = { { kind[data.kind][2], 'Saga' .. kind[data.kind][3] } },
        virt_text_pos = 'overlay',
      })
      curlnum = curlnum + 1
      val.winline = curlnum
      if not curnode then
        slist.tail_push(self.list, val)
      else
        slist.insert_node(curnode, val)
      end
    end
  end)
end

function ch:send_prepare_call()
  if self.pending_request then
    vim.notify('there is already a request please wait.')
    return
  end
  self.main_buf = api.nvim_get_current_buf()
  local clients = util.get_client_by_method(get_method(1))
  if #clients == 0 then
    vim.notify('[Lspsaga] all clients of this buffer not support callhierarchy')
    return
  end
  local client
  if #clients == 1 then
    client = clients[1]
  else
    local client_name = vim.tbl_map(function(item)
      return item.name
    end, clients)

    local choice = vim.fn.inputlist('select client:', unpack(client_name))
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
    local item = pick_call_hierarchy_item(result)
    self:call_hierarchy(item, client)
  end, self.main_buf)
end

function ch:send_method(t, args)
  self.method = get_method(t)
  self.layout = config.callhierarchy.layout
  if vim.tbl_contains(args, '++normal') then
    self.layout = 'normal'
  elseif vim.tbl_contains(args, '++float') then
    self.layout = 'float'
  end
  self:send_prepare_call()
end

return setmetatable({}, ch)
