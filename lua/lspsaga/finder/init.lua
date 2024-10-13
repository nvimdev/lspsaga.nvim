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
  self.callerwinid = api.nvim_get_current_win()
  local WIDTH = api.nvim_win_get_width(self.callerwinid)
  if self.layout == 'dropdown' then
    self.lbufnr, self.lwinid, _, self.rwinid =
      ly:new(self.layout):dropdown(math.floor(vim.o.lines * config.finder.max_height)):done()
  else
    self.lbufnr, self.lwinid, _, self.rwinid = ly:new(self.layout)
      :left(
        math.floor(vim.o.lines * config.finder.max_height),
        math.floor(WIDTH * config.finder.left_width),
        nil,
        nil,
        self.layout == 'normal' and config.finder.sp_global or nil
      )
      :bufopt({
        ['filetype'] = 'sagafinder',
        ['buftype'] = 'nofile',
        ['bufhidden'] = 'wipe',
        ['modifiable'] = true,
      })
      :winopt('wrap', false)
      :right()
      :bufopt({
        ['buftype'] = 'nofile',
        ['bufhidden'] = 'wipe',
      })
      :done()
    if not self.lwinid then
      return
    end
  end
  self:apply_maps()
  self:event()
end

function fd:set_toggle_icon(icon, virtid, row, col)
  buf_set_extmark(self.lbufnr, ns, row, col, {
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
  local rendered_fname = {}

  for client_id, item in pairs(results) do
    for i, res in ipairs(item.result or {}) do
      if not self.lbufnr then
        spin_close()
        self:init_layout()
      end
      local row = api.nvim_buf_line_count(self.lbufnr)
      row = row == 1 and row - 1 or row

      local uri = res.uri or res.targetUri
      if i == 1 then
        self:method_title(method, row)
        buf_set_extmark(self.lbufnr, ns, row, 0, {
          virt_text = { { ' ' .. vim.tbl_count(item.result) .. ' ', 'SagaCount' } },
          virt_text_pos = 'eol',
        })
        row = row + 1
      end
      local fname = vim.uri_to_fname(uri)
      if config.finder.fname_sub and type(config.finder.fname_sub) == 'function' then
        fname = config.finder.fname_sub(fname)
      end
      local client = lsp.get_client_by_id(client_id)
      if not client then
        return
      end
      if not vim.tbl_contains(rendered_fname, fname) then
        rendered_fname[#rendered_fname + 1] = fname
        local node = {
          count = #item.result,
          expand = true,
          virtid = uv.hrtime(),
          inlevel = 4,
          client_id = client_id,
        }
        node.line = util.path_sub(fname, client.config.root_dir)
        buf_set_lines(self.lbufnr, -1, -1, false, { (' '):rep(4) .. node.line })
        self:set_toggle_icon(config.ui.collapse, node.virtid, row, 2)
        self:set_highlight(node.inlevel, row)
        row = row + 1
        node.winline = row
        slist.tail_push(self.list, node)
      end

      res.bufnr = vim.uri_to_bufnr(uri)
      if not api.nvim_buf_is_loaded(res.bufnr) then
        local events = { 'BufEnter' }
        if not uri:find('jdt://') then
          events[#events + 1] = 'FileType'
        end
        vim.opt.eventignore:append(events)
        fn.bufload(res.bufnr)
        res.wipe = true
        vim.opt.eventignore:remove(events)
      end
      local range = res.range or res.targetSelectionRange or res.selectionRange
      res.line = api.nvim_buf_get_text(
        res.bufnr,
        range.start.line,
        0,
        range['end'].line,
        lsp.util._get_line_byte_from_position(res.bufnr, range['end'], client.offset_encoding),
        {}
      )[1]
      res.line = res.line:gsub('^%s+', '')

      res.client_id = client_id
      res.inlevel = 6
      buf_set_lines(self.lbufnr, -1, -1, false, { (' '):rep(6) .. res.line })
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
      if node.value.wipe then
        vim.bo[node.value.bufnr].filetype = self.ft
      end
      if config.finder.layout ~= 'dropdown' then
        api.nvim_set_option_value('winhl', 'Normal:SagaNormal,FloatBorder:SagaBorder', {
          scope = 'local',
          win = self.rwinid,
        })
      end
      local client = vim.lsp.get_client_by_id(node.value.client_id)
      if not client then
        return
      end
      local range = node.value.selectionRange or node.value.range or node.value.targetSelectionRange
      local col =
        lsp.util._get_line_byte_from_position(node.value.bufnr, range.start, client.offset_encoding)
      api.nvim_win_set_cursor(self.rwinid, { range.start.line + 1, col })
      api.nvim_set_option_value('winbar', '', { scope = 'local', win = self.rwinid })
      local rwin_conf = api.nvim_win_get_config(self.rwinid)
      if self.layout == 'float' and config.ui.title and config.ui.border ~= 'none' then
        rwin_conf.title =
          util.path_sub(api.nvim_buf_get_name(node.value.bufnr), client.config.root_dir)
        rwin_conf.title_pos = 'center'
        api.nvim_win_set_config(self.rwinid, rwin_conf)
      end

      api.nvim_win_call(self.rwinid, function()
        local height = api.nvim_win_get_height(self.rwinid)
        local top = range.start.line + 1 - bit.rshift(height, 2)
        if top <= 0 then
          top = range.start.line
        end
        fn.winrestview({ topline = range.start.line + 1 - bit.rshift(height, 2) })
        api.nvim_set_option_value('number', config.finder.number, {
          scope = 'local',
          win = self.rwinid,
        })
        api.nvim_set_option_value('relativenumber', config.finder.relativenumber, {
          scope = 'local',
          win = self.rwinid,
        })
      end)

      buf_add_highlight(
        node.value.bufnr,
        ns,
        'SagaSearch',
        range.start.line,
        col,
        lsp.util._get_line_byte_from_position(
          node.value.bufnr,
          range['end'],
          client.offset_encoding
        )
      )
      node.value.rendered = true
      util.map_keys(node.value.bufnr, config.finder.keys.close, function()
        self:clean()
      end)
      util.map_keys(node.value.bufnr, config.finder.keys.shuttle, function()
        if api.nvim_get_current_win() ~= self.rwinid then
          return
        end
        vim.opt.eventignore:append('BufEnter')
        api.nvim_set_current_win(self.lwinid)
        vim.opt.eventignore:remove('BufEnter')
      end)
    end,
  })

  api.nvim_create_autocmd('QuitPre', {
    buffer = self.lbufnr,
    callback = function()
      util.close_win(self.rwinid)
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
      local uri = node.value.uri or node.value.targetUri
      local client = lsp.get_client_by_id(node.value.client_id)
      if not client then
        return
      end
      local range = node.value.selectionRange or node.value.range or node.value.targetSelectionRange
      local pos = {
        range.start.line + 1,
        lsp.util._get_line_byte_from_position(
          node.value.bufnr,
          range.start,
          client.offset_encoding
        ),
      }
      local callerwinid = self.callerwinid
      self:clean()
      local restore = win:minimal_restore()
      local bufnr = vim.uri_to_bufnr(uri)
      api.nvim_win_set_buf(callerwinid, bufnr)
      vim.bo[bufnr].buflisted = true
      restore()
      api.nvim_set_current_win(callerwinid)
      api.nvim_win_set_cursor(callerwinid, pos)
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
        local client = lsp.get_client_by_id(curnode.value.client_id)
        if not client then
          return
        end
        local range = curnode.value.range
          or curnode.value.targetSelectionRange
          or curnode.value.selectionRange

        local pos = {
          range.start.line + 1,
          lsp.util._get_line_byte_from_position(
            curnode.value.bufnr,
            range.start,
            client.offset_encoding
          ),
        }
        local inexist = self.inexist
        self:clean()
        local restore = win:minimal_restore()
        if inexist and (action == 'split' or action == 'vsplit') then
          local reuse = box.win_reuse(action)
          if not reuse then
            vim.cmd[action](fname)
          else
            api.nvim_win_set_buf(reuse, fn.bufadd(fname))
            api.nvim_set_current_win(reuse)
          end
        else
          vim.cmd[action](fname)
        end
        restore()
        api.nvim_win_set_cursor(0, pos)
        beacon({ pos[1] - 1, 0 }, #api.nvim_get_current_line())
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
    local curlnum = api.nvim_win_get_cursor(0)[1]
    local curnode = slist.find_node(self.list, curlnum)
    if not curnode then
      return
    end
    vim.opt.eventignore:append('BufEnter')
    api.nvim_set_current_win(self.rwinid)
    vim.opt.eventignore:remove('BufEnter')
    local curbuf = api.nvim_get_current_buf()
    vim.lsp.buf_attach_client(curbuf, curnode.value.client_id)
  end)
end

function fd:new(args)
  local meth, layout, inexist = box.parse_argument(args)
  self.inexist = inexist
  if not self.inexist then
    self.inexist = config.finder.sp_inexist
  end
  self.layout = layout or config.finder.layout
  if #meth == 0 then
    meth = vim.split(config.finder.default, '+', { plain = true })
  end
  local methods = box.get_methods(meth)

  methods = vim.tbl_filter(function(method)
    return #util.get_client_by_method(method) > 0
  end, methods)
  local curbuf = api.nvim_get_current_buf()
  self.ft = vim.bo[curbuf].filetype
  if #methods == 0 then
    vim.notify(
      ('[lspsaga] no servers of buffer %s makes these methods available %s'):format(
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
    includeDeclaration = true,
  }

  local spin_close = box.spinner()
  local count = 0
  coroutine.resume(coroutine.create(function()
    local retval = {}
    local co = coroutine.running()
    for _, method in ipairs(methods) do
      lsp.buf_request_all(curbuf, method, params, function(results)
        count = count + 1
        results = box.filter(method, results)
        if results and not util.res_isempty(results) then
          retval[method] = results
        end
        if count == #methods then
          coroutine.resume(co)
        end
      end)
    end
    coroutine.yield()
    count = 0
    local keys = vim.tbl_keys(retval)
    table.sort(keys, function(a, b)
      return util.tbl_index(methods, a) < util.tbl_index(methods, b)
    end)

    for _, m in pairs(keys) do
      count = count + 1
      self:handler(m, retval[m], spin_close, count == #keys)
    end
    if not self.lwinid then
      spin_close()
      vim.notify('[Lspsaga] finder no any results to show', vim.log.levels.WARN)
    end
  end))
end

return setmetatable(ctx, fd)
