local api, fn, lsp, validate = vim.api, vim.fn, vim.lsp, vim.validate
local window = require('lspsaga.window')
local kind = require('lspsaga.lspkind')
local call_conf = require('lspsaga').config_values.call_hierarchy
local insert = table.insert
local method = {
  'textDocument/prepareCallHierarchy',
  'callHierarchy/incomingCalls',
  'callHierarchy/outgoingCalls',
}

local ch = {}

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

function ch:call_hierarchy(bufnr, item)
  local client = self[bufnr].client
  client.request(self.method, { item = item }, function(_, res)
    if not res or next(res) == nil then
      return
    end
    for i, v in pairs(res) do
      insert(self[bufnr].data, {
        from = v.from,
        name = '    ' .. kind[v.from.kind][2] .. v.from.name,
        winline = i + 1,
      })
    end
    local content = parse_data(self[bufnr].data)
    self:render_win(content)
  end)
end

function ch:send_prepare_call()
  local current_buf = api.nvim_get_current_buf()
  if not self[current_buf] then
    self[current_buf] = {
      data = {},
    }
  end

  local params = lsp.util.make_position_params()
  lsp.buf_request(0, method[1], params, function(_, result, ctx)
    local call_hierarchy_item = pick_call_hierarchy_item(result)
    self[current_buf].client = lsp.get_client_by_id(ctx.client_id)
    self:call_hierarchy(current_buf, call_hierarchy_item)
  end)
end

function ch:expand_collaspe() end

function ch:render_win(content)
  validate({
    content = { content, 'table' },
  })
  local content_opt = {
    contents = content,
    highlight = 'callHierarchyBorder',
  }

  local opt = {}
  if fn.has('nvim-0.9') == 1 then
    local titles = {
      [method[2]] = 'InComing Call',
      [method[3]] = 'OutGoing Call',
    }
    opt.title = call_conf.incoming_icon .. titles[self.method]
    opt.title_pos = 'left'
  end
  self.winbuf, self.winid = window.create_win_with_border(content_opt, opt)
end

function ch:incoming_calls()
  self.method = method[2]
  self:send_prepare_call()
end

function ch:outgoing_calls()
  self.method = method[3]
end

return ch
