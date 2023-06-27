local api, fn, lsp, uv = vim.api, vim.fn, vim.lsp, vim.loop
local config = require('lspsaga').config
local util = require('lspsaga.util')
local slist = require('lspsaga.slist')
local buf_set_lines = api.nvim_buf_set_lines
local buf_set_extmark = api.nvim_buf_set_extmark
local kind = require('lspsaga.lspkind').kind
local ly = require('lspsaga.layout')
local call_conf, ui = config.callhierarchy, config.ui
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

function ch:spinner()
  -- local spinner = { '⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷' }
  -- local frame = 0
  -- local curline = api.nvim_win_get_cursor(0)[1]
  -- if self.bufnr and api.nvim_buf_is_loaded(self.bufnr) and parent then
  --   local timer = uv.new_timer()
  --   timer:start(0, 50, function()
  --     if self.pending_request then
  --       self.pending_request = false
  --     end
  --
  --     if not self.pending_request and not timer:is_closing() then
  --       self.pending_request = false
  --     end
  --   end)
  -- end
end

function ch:call_hierarchy(item, client)
  self.pending_request = true
  client.request(self.method, { item = item }, function(_, res)
    self.pending_request = false
    if not res or vim.tbl_isempty(res) then
      return
    end

    local cword = fn.expand('<cword>')
    if not self.left_winid then
      local height = bit.rshift(vim.o.lines, 1) - 4
      self.left_bufnr, self.left_winid = ly:new(self.layout):left(height, 20)
      buf_set_lines(self.left_bufnr, 0, -1, false, { cword })
    end

    local curlnum = api.nvim_win_get_cursor(0)[1]
    local inlevel = fn.indent(curlnum)
    local curnode = slist.find_node(self.list, curlnum)
    local indent = (' '):rep(inlevel + 4)
    local row = curlnum - 1
    for _, val in ipairs(res) do
      local data = self.method == get_method(2) and val.from or val.to
      if not curnode then
        buf_set_lines(self.left_bufnr, -1, -1, false, { indent .. data.name })
        row = row + 1
        buf_set_extmark(self.left_bufnr, ns, row, #indent - 4, {
          virt_text = { { config.ui.expand, 'SagaExpand' } },
          virt_text_pos = 'overlay',
          hl_mode = 'combine',
        })
        buf_set_extmark(self.left_bufnr, ns, row, #indent - 2, {
          virt_text = { { kind[data.kind][2], 'SagaWinbar' .. kind[data.kind][3] } },
          virt_text_pos = 'overlay',
          hl_mode = 'combine',
        })
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

function ch:toggle_or_request() end

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
