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
local select_ns = api.nvim_create_namespace('SagaSelect')
local win = require('lspsaga.window')
local beacon = require('lspsaga.beacon').jump_beacon

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

function fd:init_layout()
  local win_width = api.nvim_win_get_width(0)
  self.lbufnr, self.lwinid, _, self.rwinid = ly:new(self.layout)
    :left(
      math.floor(vim.o.lines * config.finder.max_height),
      math.floor(win_width * config.finder.left_width)
    )
    :bufopt({
      ['filetype'] = 'sagafinder',
      ['buftype'] = 'nofile',
      ['bufhidden'] = 'wipe',
    })
    :right()
    :bufopt({
      ['buftype'] = 'nofile',
      ['bufhidden'] = 'wipe',
    })
    :done()
  self:apply_maps()
  self:event()
end

function fd:set_toggle_icon(icon, virtid, row, col)
  api.nvim_buf_set_extmark(self.lbufnr, ns, row, col, {
    id = virtid,
    -- virt_text_win_col = col,
    virt_text = { { icon, 'SagaToggle' } },
    virt_text_pos = 'overlay',
  })
end

function fd:set_highlight(inlevel, line)
  local hl_group, col_start
  if inlevel == 2 then
    hl_group = 'SagaTitle'
    col_start = 2
  elseif inlevel == 4 then
    hl_group = 'SagaFinderFname'
    col_start = 4
  else
    hl_group = 'SagaText'
    col_start = 6
  end
  buf_add_highlight(self.lbufnr, ns, hl_group, line, col_start, -1)
end

function fd:method_title(method, row)
  local title = vim.split(method, '/', { plain = true })[2]
  title = title:upper()

  local n = {
    winline = row + 1,
    expand = true,
    virtid = uv.hrtime(),
    inlevel = 2,
  }
  buf_set_lines(self.lbufnr, row, -1, false, { (' '):rep(2) .. title })
  self:set_highlight(n.inlevel, row)
  self:set_toggle_icon(config.ui.collapse, n.virtid, row, 0)
  slist.tail_push(self.list, n)
end

function fd:handler(method, results, spin_close, done)
  if not results or util.res_isempty(results) then
    spin_close()
    vim.notify(('[Lspsaga] no response of %s'):format(method), vim.log.levels.WARN)
    return
  end
  local rendered_fname = {}

  for client_id, item in pairs(results) do
    for i, res in ipairs(item.result or {}) do
      if not self.lbufnr then
        spin_close()
        self:init_layout()
        vim.bo[self.lbufnr].modifiable = true
      end
      local row = api.nvim_buf_line_count(self.lbufnr)
      row = row == 1 and row - 1 or row

      local uri = res.uri or res.targetUri
      if i == 1 then
        self:method_title(method, row)
        row = row + 1
      end
      local fname = vim.uri_to_fname(uri)
      if not vim.tbl_contains(rendered_fname, fname) then
        local node = {
          count = #item.result,
          expand = true,
          virtid = uv.hrtime(),
          inlevel = 4,
          client_id = client_id,
        }
        local client = lsp.get_client_by_id(client_id)
        node.line = fname:sub(#client.config.root_dir + 2)
        buf_set_lines(self.lbufnr, -1, -1, false, { (' '):rep(4) .. node.line })
        self:set_toggle_icon(config.ui.collapse, node.virtid, row, 2)
        self:set_highlight(node.inlevel, row)
        row = row + 1
        node.winline = row
        slist.tail_push(self.list, node)
      end

      res.bufnr = vim.uri_to_bufnr(uri)
      if not api.nvim_buf_is_loaded(res.bufnr) then
        fn.bufload(res.bufnr)
        res.wipe = true
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
      res.client_id = client_id
      res.inlevel = 6
      buf_set_lines(self.lbufnr, -1, -1, false, { (' '):rep(6) .. res.line })
      rendered_fname[#rendered_fname + 1] = fname
      self:set_highlight(res.inlevel, row)
      row = row + 1
      res.winline = row
      slist.tail_push(self.list, res)
    end
  end

  if not done then
    buf_set_lines(self.lbufnr, -1, -1, false, {})
  end

  if done then
    vim.bo[self.lbufnr].modifiable = false
    spin_close()
    api.nvim_win_set_cursor(self.lwinid, { 3, 6 })
    box.indent(ns, self.lbufnr, self.lwinid)
    api.nvim_create_autocmd('BufEnter', {
      callback = function(args)
        if args.buf ~= self.lbufnr or args.buf ~= self.rbufnr then
          self:clean()
          api.nvim_del_autocmd(args.id)
        end
      end,
    })
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
      api.nvim_buf_clear_namespace(self.lbufnr, select_ns, 0, -1)
      local inlevel = fn.indent(curlnum)
      if inlevel == 6 then
        buf_add_highlight(self.lbufnr, select_ns, 'String', curlnum - 1, 6, -1)
      end
      box.indent_current(inlevel)
      local node = slist.find_node(self.list, curlnum)
      if not node or not node.value.bufnr then
        return
      end
      api.nvim_win_set_buf(self.rwinid, node.value.bufnr)
      local range = node.value.range or node.value.targetSelectionRange or node.value.selectionRange
      api.nvim_win_set_cursor(self.rwinid, { range.start.line + 1, range.start.character })
      api.nvim_set_option_value('winbar', '', { scope = 'local', win = self.rwinid })
      local rwin_conf = api.nvim_win_get_config(self.rwinid)
      local client = vim.lsp.get_client_by_id(node.value.client_id)
      rwin_conf.title =
        util.path_sub(api.nvim_buf_get_name(node.value.bufnr), client.config.root_dir)
      rwin_conf.title_pos = 'center'
      api.nvim_win_set_config(self.rwinid, rwin_conf)

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
      node.value.rendered = true
      util.map_keys(node.value.bufnr, config.finder.keys.close, function()
        self:clean()
      end)
      util.map_keys(node.value.bufnr, config.finder.keys.shuttle, function()
        if api.nvim_get_current_win() ~= self.rwinid then
          return
        end
        api.nvim_set_current_win(self.lwinid)
      end)
    end,
  })
end

function fd:clean()
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
  clean_ctx()
end

function fd:toggle_or_open()
  util.map_keys(self.lbufnr, config.finder.keys['toggle_or_open'], function()
    local curlnum = api.nvim_win_get_cursor(self.lwinid)[1]
    local node = slist.find_node(self.list, curlnum)
    if not node then
      return
    end
    if node.value.expand == nil then
      local fname = vim.uri_to_fname(node.value.uri)
      local pos = { node.value.range.start.line + 1, node.value.range.start.character }
      self:clean()
      local restore = win:minimal_restore()
      vim.cmd.edit(fname)
      restore()
      api.nvim_win_set_cursor(0, pos)
      beacon({ pos[1] - 1, 0 }, #api.nvim_get_current_line())
      return
    end

    vim.bo[self.lbufnr].modifiable = true
    if node.value.expand == true then
      local row = curlnum + 1
      while true do
        local l = fn.indent(row)
        if l <= node.value.inlevel or l == 0 or l == -1 then
          break
        end
        row = row + 1
      end

      local count = row - curlnum - 1

      self:set_toggle_icon(config.ui.expand, node.value.virtid, curlnum - 1, node.value.inlevel - 2)
      buf_set_lines(self.lbufnr, curlnum, curlnum + count, false, {})
      node.value.expand = false
      vim.bo[self.lbufnr].modifiable = false
      slist.update_winline(node, -count)
      return
    end

    local count = 0
    node.value.expand = true
    self:set_toggle_icon(config.ui.collapse, node.value.virtid, curlnum - 1, node.value.inlevel - 2)
    local tmp = node.next
    while tmp do
      buf_set_lines(
        self.lbufnr,
        curlnum,
        curlnum,
        false,
        { (' '):rep(tmp.value.inlevel) .. tmp.value.line }
      )
      self:set_highlight(tmp.value.inlevel, curlnum)
      local islast = (not tmp.next or tmp.next.value.inlevel <= tmp.value.inlevel) and true or false
      if tmp.value.expand == false then
        self:set_toggle_icon(config.ui.collapse, tmp.value.virtid, curlnum, tmp.value.inlevel - 2)
        tmp.value.expand = true
      end
      count = count + 1
      curlnum = curlnum + 1
      tmp.value.winline = curlnum
      if not tmp or (tmp.next and tmp.next.value.inlevel <= node.value.inlevel) then
        break
      end
      tmp = tmp.next
    end
    vim.bo[self.lbufnr].modifiable = false
    if tmp then
      slist.update_winline(tmp, count)
    end
  end)
end

function fd:apply_maps()
  local black = { 'close', 'toggle_or_open', 'go_peek', 'quit', 'shuttle' }
  for action, key in pairs(config.finder.keys) do
    util.map_keys(self.lbufnr, key, function()
      if not vim.tbl_contains(black, action) then
        local curlnum = api.nvim_win_get_cursor(0)[1]
        local curnode = slist.find_node(self.list, curlnum)
        if not curnode then
          return
        end
        local fname = api.nvim_buf_get_name(curnode.value.bufnr)
        local pos = { curnode.value.range.start.line + 1, curnode.value.range.start.character }
        self:clean()
        local restore = win:minimal_restore()
        vim.cmd[action](fname)
        restore()
        api.nvim_win_set_cursor(0, pos)
        beacon({ pos[1], 0 }, #api.nvim_get_current_line())
        return
      end

      if action == 'quit' then
        self:clean()
        return
      end

      if action == 'go_peek' then
        api.nvim_set_current_win(self.rwinid)
        return
      end
    end)
  end
  self:toggle_or_open()

  util.map_keys(self.lbufnr, config.finder.keys.shuttle, function()
    if api.nvim_get_current_win() ~= self.lwinid then
      return
    end
    api.nvim_set_current_win(self.rwinid)
  end)
end

function fd:new(args)
  local meth, layout = box.parse_argument(args)
  self.layout = layout or config.finder.layout
  if #meth == 0 then
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
      results = box.filter(method, results)
      self:handler(method, results, spin_close, count == #methods)
    end)
  end
end

return setmetatable(ctx, fd)
