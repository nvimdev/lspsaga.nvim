local api, fn, lsp, uv = vim.api, vim.fn, vim.lsp, vim.loop
local config = require('lspsaga').config
local util = require('lspsaga.util')
local win = require('lspsaga.window')
local call_conf, ui = config.callhierarchy, config.ui

local ch = {}

function ch.__newindex(t, k, v)
  rawset(t, k, v)
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
function ch:call_hierarchy(client, item, parent)
  local spinner = { '⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷' }
  local frame = 0
  local curline = api.nvim_win_get_cursor(0)[1]
  if self.bufnr and api.nvim_buf_is_loaded(self.bufnr) and parent then
    local timer = uv.new_timer()
    timer:start(0, 50, function()
      if self.pending_request then
        self.pending_request = false
      end

      if not self.pending_request and not timer:is_closing() then
        self.pending_request = false
      end
    end)
  end

  self.pending_request = true
  client.request(self.method, { item = item }, function(_, res)
    self.pending_request = false
    if not res or vim.tbl_isempty(res) then
      return
    end

    self:render_win()
  end)
end

function ch:send_prepare_call()
  if self.pending_request then
    vim.notify('there is already a request please wait.')
    return
  end
  self.main_buf = api.nvim_get_current_buf()
  local clients = util.get_client_by_method()
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

  local params = lsp.util.make_position_params()
  client.request(get_method(1), params, function(_, result, ctx)
    if api.nvim_get_current_buf() ~= ctx.bufnr then
      return
    end
    local call_hierarchy_item = pick_call_hierarchy_item(result)
    self:call_hierarchy(client, call_hierarchy_item)
  end, self.main_buf)
end

function ch:expand_collapse() end

function ch:apply_map() end

function ch:render_win()
  self:apply_map()
end

function ch:clean()
  for key, _ in pairs(self) do
    if type(key) ~= 'function' then
      self[key] = nil
    end
  end
end

function ch:send_method(type)
  self.cword = fn.expand('<cword>')
  self.method = get_method(type)
  self.data = {}
  self:send_prepare_call()
end

return setmetatable({}, ch)
