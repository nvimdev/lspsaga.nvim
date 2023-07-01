local api, lsp, fn = vim.api, vim.lsp, vim.fn
---@diagnostic disable-next-line: deprecated
local uv = vim.version().minor >= 10 and vim.uv or vim.loop
local ly = require('lspsaga.layout')
local slist = require('lspsaga.slist')
local box = require('lspsaga.finder.box')
local util = require('lspsaga.util')
local buf_set_lines, buf_set_extmark = api.nvim_buf_set_lines, api.nvim_buf_set_extmark
local buf_add_highlight = api.nvim_buf_add_highlight
local config = require('lspsaga').config

local fd = {}
local ctx = {}

fd.__index = fd
fd.__newindex = function(t, k, v)
  rawset(t, k, v)
end

local function clean_ctx()
  for key, _ in pairs(ctx) do
    if type(ctx) ~= 'function' then
      ctx[key] = nil
    end
  end
end

local ns = api.nvim_create_namespace('SagaFinder')

function fd:method_title(method)
  local title = vim.split(method, '/', { plain = true })[2]
  title = title:upper()

  local total = api.nvim_buf_line_count(self.lbufnr)
  local n = {
    winline = total,
    expand = true,
    virtid = uv.hrtime(),
  }
  buf_set_lines(self.lbufnr, total == 1 and 0 or total, -1, false, { (' '):rep(2) .. title })
  buf_set_extmark(self.lbufnr, ns, total == 1 and 0 or total, 0, {
    id = n.virtid,
    virt_text = { { config.ui.expand, 'SagaToggle' } },
    virt_text_pos = 'overlay',
    hl_mode = 'combine',
  })
  slist.tail_push(self.list, n)
end

function fd:init_layout()
  local win_width = api.nvim_win_get_width(0)
  self.lbufnr, self.lwinid, _, self.rwinid = ly:new(self.layout)
    :left(
      math.floor(vim.o.lines * config.finder.max_height),
      math.floor(win_width * config.finder.left_width)
    )
    :right()
    :done(function()
      self:event()
    end)
end

function fd:handler(method, results, spin_close, done)
  if not results or vim.tbl_isempty(results) then
    return
  end
  for client_id, item in ipairs(results) do
    for i, res in ipairs(item.result or {}) do
      if not self.lbufnr then
        spin_close()
        self:init_layout()
      end

      local total = api.nvim_buf_line_count(self.lbufnr)
      if i == 1 then
        self:method_title(method)

        local node = {
          count = #item.result,
          expand = true,
          virtid = uv.hrtime(),
        }
        local fname = vim.uri_to_fname(res.uri)
        local client = lsp.get_client_by_id(client_id)
        fname = fname:sub(#client.config.root_dir + 2)
        buf_set_lines(self.lbufnr, -1, -1, false, { (' '):rep(4) .. fname })
        total = total + 1
        node.winline = total
        buf_set_extmark(self.lbufnr, ns, total - 1, 2, {
          id = node.virtid,
          virt_text = { { config.ui.expand, 'SagaToggle' } },
          virt_text_pos = 'overlay',
          hl_mode = 'combine',
        })
        slist.tail_push(self.list, node)
      end
      res.bufnr = vim.uri_to_bufnr(res.uri)
      if not api.nvim_buf_is_loaded(res.bufnr) then
        fn.bufload(res.bufnr)
        res.wipe = true
        api.nvim_set_option_value('bufhidden', 'wipe', { buf = res.bufnr })
        slist.tail_push(self.list, res)
      end
      local range = res.range or res.targetSelectionRange or res.selectionRange
      res.line = api.nvim_buf_get_text(
        res.bufnr,
        range.start.line,
        range.start.character,
        range['end'].line,
        range['end'].character,
        {}
      )[1]
      buf_set_lines(self.lbufnr, -1, -1, false, { (' '):rep(6) .. res.line })
      buf_add_highlight(self.lbufnr, ns, 'SagaFinderText', total, 0, -1)
      total = total + 1
      res.winline = total
      slist.tail_push(self.list, res)
    end
  end

  if self.lbufnr and api.nvim_buf_line_count(self.lbufnr) > 1 then
    buf_set_lines(self.lbufnr, -1, -1, false, { '' })
  end

  if done then
    spin_close()
    api.nvim_win_set_cursor(self.lwinid, { 3, 6 })
  end
end

function fd:event()
  api.nvim_create_autocmd('CursorMoved', {
    buffer = self.lbufnr,
    callback = function()
      if not self.lwinid or not api.nvim_win_is_valid(self.lwinid) then
        return
      end
      local curlnum = api.nvim_win_get_cursor(self.lwinid)[1]
      local node = slist.find_node(self.list, curlnum)
      if not node or not node.value.bufnr then
        return
      end
      api.nvim_win_set_buf(self.rwinid, node.value.bufnr)
      local range = node.value.range or node.value.targetSelectionRange or node.value.selectionRange
      api.nvim_win_set_cursor(self.rwinid, { range.start.line + 1, range.start.character })
      api.nvim_set_option_value('winbar', '', { scope = 'local', win = self.rwinid })
      api.nvim_win_call(self.rwinid, function()
        fn.winrestview({ topline = range.start.line + 1 })
      end)
      buf_add_highlight(
        node.value.bufnr,
        ns,
        'SagaSearch',
        range.start.line,
        range.start.character,
        range['end'].character
      )
    end,
  })
end

function fd:apply_maps()
  for action, key in pairs(config.finder.keys) do
    util.map_keys(self.lbufnr, key, function()
      if action ~= 'peek_close_all' and action ~= 'expand_or_jump' and action ~= 'go_peek' then
        vim.cmd[action]()
        return
      end
    end)
  end
end

function fd:new(args)
  local meth, layout = box.parse_argument(args)
  self.layout = layout or config.finder.layout
  if not meth then
    meth = vim.split(config.finder.default, '+', { plain = true })
  end
  local methods = box.get_methods(meth)
  methods = vim.tbl_filter(function(method)
    return #util.get_client_by_method(method) > 0
  end, methods)
  local curbuf = api.nvim_get_current_buf()
  if #methods == 0 then
    vim.notify(
      ('[Lspsaga] all server of %s buffer does not these methods %s'):format(
        curbuf,
        table.concat(args, ' ')
      ),
      vim.log.levels.WARN
    )
    return
  end

  self.list = slist.new()
  local params = lsp.util.make_position_params()
  params.context = {
    includeDeclaration = false,
  }

  local spin_close = box.spinner()
  local count = 0
  for _, method in ipairs(methods) do
    lsp.buf_request_all(curbuf, method, params, function(results)
      count = count + 1
      self:handler(method, results, spin_close, count == #methods)
    end)
  end
end

return setmetatable(ctx, fd)
