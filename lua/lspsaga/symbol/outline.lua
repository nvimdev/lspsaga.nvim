local ot = {}
local api, fn = vim.api, vim.fn
---@diagnostic disable-next-line: deprecated
local uv = vim.version().minor >= 10 and vim.uv or vim.loop
local get_kind_icon = require('lspsaga.lspkind').get_kind_icon
local config = require('lspsaga').config
local util = require('lspsaga.util')
local symbol = require('lspsaga.symbol')
local win = require('lspsaga.window')
local buf_set_lines = api.nvim_buf_set_lines
local buf_set_extmark = api.nvim_buf_set_extmark
local outline_conf = config.outline
local ns = api.nvim_create_namespace('SagaOutline')
local beacon = require('lspsaga.beacon').jump_beacon
local slist = require('lspsaga.slist')
local ly = require('lspsaga.layout')
local ctx = {}
local group = api.nvim_create_augroup('outline', { clear = true })

function ot.__newindex(t, k, v)
  rawset(t, k, v)
end

ot.__index = ot

local function clean_ctx()
  for k, _ in pairs(ctx) do
    ctx[k] = nil
  end
  local aus = api.nvim_get_autocmds({
    group = group,
  })
  for _, au in ipairs(aus) do
    api.nvim_del_autocmd(au.id)
  end
end

local function outline_in_float()
  local win_width = api.nvim_win_get_width(0)
  local curbuf = api.nvim_get_current_buf()

  return ly:new('float')
    :left(
      math.floor(vim.o.lines * config.outline.max_height),
      math.floor(win_width * config.outline.left_width),
      nil,
      'outline'
    )
    :bufopt({
      ['filetype'] = 'sagafinder',
      ['buftype'] = 'nofile',
      ['bufhidden'] = 'wipe',
    })
    :winopt('wrap', false)
    :right({ title = 'preview' })
    :bufopt({
      ['buftype'] = 'nofile',
      ['bufhidden'] = 'wipe',
      ['filetype'] = vim.bo[curbuf].filetype,
    })
    :done()
end

local function outline_normal_win()
  local pos = outline_conf.win_position == 'right' and 'botright' or 'topleft'
  vim.cmd(pos .. ' vnew')
  local winid, bufnr = api.nvim_get_current_win(), api.nvim_get_current_buf()
  api.nvim_win_set_width(winid, config.outline.win_width)

  return win
    :from_exist(bufnr, winid)
    :bufopt({
      ['filetype'] = 'sagaoutline',
      ['bufhidden'] = 'wipe',
      ['buflisted'] = false,
      ['buftype'] = 'nofile',
      ['indentexpr'] = 'indent',
    })
    :winopt({
      ['wrap'] = false,
      ['number'] = false,
      ['relativenumber'] = false,
      ['signcolumn'] = 'no',
      ['list'] = false,
      ['spell'] = false,
      ['cursorcolumn'] = false,
      ['cursorline'] = false,
      ['winfixwidth'] = true,
      ['winhl'] = 'Normal:OutlineNormal',
      ['stc'] = '',
    })
    :wininfo()
end

function ot:parse(symbols, curline)
  local row = 0
  if not vim.bo[self.bufnr].modifiable then
    api.nvim_set_option_value('modifiable', true, { buf = self.bufnr })
  end
  local pos = {}

  local function recursive_parse(data, level)
    for i, node in ipairs(data) do
      level = level or 0
      local indent = '    ' .. ('  '):rep(level)
      node.name = node.name == ' ' and '_' or node.name
      buf_set_lines(self.bufnr, row, -1, false, { indent .. node.name:gsub('\n', '') })

      row = row + 1
      if level == 0 then
        node.winline = row
      end

      local range = node.range or node.selectionRange or node.targetRange
      if node.location then
        range = node.location.range
      end
      if curline then
        if
          range.start.line == curline - 1
          or (curline - 1 >= range.start.line and curline - 1 <= range['end'].line)
        then
          pos = { row, #indent }
        end
      end

      local hl, icon = unpack(get_kind_icon(node.kind))
      buf_set_extmark(self.bufnr, ns, row - 1, #indent - 2, {
        virt_text = { { icon, 'Saga' .. hl } },
        virt_text_pos = 'overlay',
      })
      local inlevel = 4 + 2 * level
      if inlevel == 4 and not node.children then
        local virt = {
          { row == 1 and config.ui.lines[5] or config.ui.lines[2], 'SagaVirtLine' },
          { config.ui.lines[4]:rep(2), 'SagaVirtLine' },
        }
        buf_set_extmark(self.bufnr, ns, row - 1, 0, {
          virt_text = virt,
          virt_text_pos = 'overlay',
        })
      else
        for j = 1, inlevel - 4, 2 do
          local virt = {}
          if (not node.children or #node.children == 0) and j + 2 > inlevel - 4 then
            virt[#virt + 1] = i == #data and { config.ui.lines[1], 'SagaVirtLine' }
              or { config.ui.lines[2], 'SagaVirtLine' }
            virt[#virt + 1] = { config.ui.lines[4]:rep(2), 'SagaVirtLine' }
          else
            virt = { { config.ui.lines[3], 'SagaVirtLine' } }
          end
          buf_set_extmark(self.bufnr, ns, row - 1, j - 1, {
            virt_text = virt,
            virt_text_pos = 'overlay',
          })
        end
      end

      if config.outline.detail then
        buf_set_extmark(self.bufnr, ns, row - 1, 0, {
          virt_text = { { node.detail or '', 'SagaDetail' } },
        })
      end

      local copy = vim.deepcopy(node)
      copy.children = nil
      copy.winline = row
      copy.inlevel = #indent

      if node.children and #node.children > 0 then
        copy.expand = true
        copy.virtid = uv.hrtime()
        buf_set_extmark(self.bufnr, ns, row - 1, #indent - 4, {
          id = copy.virtid,
          virt_text = { { config.ui.collapse, 'SagaToggle' } },
          virt_text_pos = 'overlay',
        })
        slist.tail_push(self.list, copy)
        recursive_parse(node.children, level + 1)
      else
        slist.tail_push(self.list, copy)
      end
    end
  end

  recursive_parse(symbols)
  if #pos > 0 then
    api.nvim_win_set_cursor(self.winid, pos)
    if config.outline.layout == 'normal' then
      api.nvim_win_call(self.winid, function()
        beacon({ pos[1] - 1, pos[2] }, #api.nvim_get_current_line())
      end)
    end
  end
  api.nvim_set_option_value('modifiable', false, { buf = self.bufnr })
  if config.outline.layout ~= 'float' then
    api.nvim_buf_attach(self.main_buf, false, {
      on_detach = function()
        local data = vim.version().minor > 10 and require('lspsaga.symbol.head')
          or require('lspsaga.symbol')
        if vim.tbl_count(data) == 0 and api.nvim_win_is_valid(self.winid) then
          vim.defer_fn(function()
            api.nvim_buf_delete(self.bufnr, { force = true })
            pcall(api.nvim_win_close, self.winid, true)
          end, 0)
        end
      end,
    })
  end
end

function ot:collapse(node, curlnum)
  local row = curlnum - 1
  local inlevel = fn.indent(curlnum)
  local tmp = node.next

  while tmp do
    local hl, icon = unpack(get_kind_icon(tmp.value.kind))
    local level = tmp.value.inlevel
    buf_set_lines(
      self.bufnr,
      row + 1,
      row + 1,
      false,
      { (' '):rep(tmp.value.inlevel) .. tmp.value.name }
    )
    row = row + 1
    tmp.value.winline = row + 1
    if tmp.value.expand == false then
      tmp.value.expand = true
    end
    buf_set_extmark(self.bufnr, ns, row, level - 2, {
      virt_text = { { icon, 'Saga' .. hl } },
      virt_text_pos = 'overlay',
    })
    local has_child = tmp.next and tmp.next.value.inlevel > level
    if has_child then
      buf_set_extmark(self.bufnr, ns, row, level - 4, {
        virt_text = { { config.ui.collapse, 'SagaToggle' } },
        virt_text_pos = 'overlay',
      })
    end
    local islast = not tmp.next or tmp.next.value.inlevel < level
    for j = 1, level - 4, 2 do
      local virt = {}
      if j + 2 > level - 4 and not has_child then
        virt[#virt + 1] = islast and { config.ui.lines[1], 'SagaVirtLine' }
          or { config.ui.lines[2], 'SagaVirtLine' }
        virt[#virt + 1] = { config.ui.lines[4]:rep(2), 'SagaVirtLine' }
      else
        virt = { { config.ui.lines[3], 'SagaVirtLine' } }
      end

      buf_set_extmark(self.bufnr, ns, row, j - 1, {
        virt_text = virt,
        virt_text_pos = 'overlay',
      })
    end

    if config.outline.detail then
      buf_set_extmark(self.bufnr, ns, row, 0, {
        virt_text = { { tmp.value.detail or ' ', 'SagaDetail' } },
      })
    end
    if not tmp or (tmp.next and tmp.next.value.inlevel <= inlevel) then
      break
    end
    tmp = tmp.next
  end

  if tmp then
    slist.update_winline(tmp, row - curlnum + 1)
  end
end

function ot:toggle_or_jump()
  local curlnum = unpack(api.nvim_win_get_cursor(self.winid))
  local node = slist.find_node(self.list, curlnum)
  if not node then
    return
  end

  local count = api.nvim_buf_line_count(self.bufnr)
  local inlevel = fn.indent(curlnum)

  if node.value.expand then
    api.nvim_set_option_value('modifiable', true, { buf = self.bufnr })
    local _end
    for i = curlnum + 1, count do
      if inlevel >= fn.indent(i) then
        _end = i - 1
        break
      end
    end
    _end = _end or count
    buf_set_lines(self.bufnr, curlnum, _end, false, {})
    buf_set_extmark(self.bufnr, ns, curlnum - 1, inlevel - 4, {
      id = node.value.virtid,
      virt_text = { { config.ui.expand, 'SagaToggle' } },
      virt_text_pos = 'overlay',
    })

    slist.update_winline(node, -(_end - curlnum))
    node.value.expand = false
    api.nvim_set_option_value('modifiable', false, { buf = self.bufnr })
    return
  end

  if node.value.expand == false then
    node.value.expand = true
    api.nvim_set_option_value('modifiable', true, { buf = self.bufnr })
    buf_set_extmark(self.bufnr, ns, curlnum - 1, inlevel - 4, {
      id = node.value.virtid,
      virt_text = { { config.ui.collapse, 'SagaToggle' } },
      virt_text_pos = 'overlay',
    })
    self:collapse(node, curlnum)
    api.nvim_set_option_value('modifiable', false, { buf = self.bufnr })
    return
  end
  local range = node.value.selectionRange or node.value.location.range
  local pos = { range.start.line + 1, range.start.character }

  local callerwinid = self.callerwinid
  if config.outline.layout == 'normal' and config.outline.close_after_jump then
    util.close_win({ self.winid, self.preview_winid })
    clean_ctx()
  elseif config.outline.layout == 'float' then
    ly:close()
    clean_ctx()
  end

  api.nvim_set_current_win(callerwinid)
  api.nvim_win_set_cursor(callerwinid, pos)
  local width = #api.nvim_get_current_line()
  beacon({ pos[1] - 1, 0 }, width)
end

function ot:calc_preview_win_spec(lines)
  local max_height = vim.o.lines - fn.winline()
  local max_width = math.floor(vim.o.columns * 0.7)

  return {
    height = math.min(max_height, #lines),
    width = math.min(max_width, util.get_max_content_length(lines)),
  }
end

function ot:create_preview_win(lines)
  local win_spec = self:calc_preview_win_spec(lines)

  local float_opt = {
    relative = 'editor',
    style = 'minimal',
    height = win_spec.height,
    width = win_spec.width,
    focusable = false,
    noautocmd = true,
  }

  local row = fn.screenrow()

  if outline_conf.win_position == 'right' then
    float_opt.anchor = 'NE'
    float_opt.col = vim.o.columns - outline_conf.win_width - 1
    float_opt.row = row + 2
    float_opt.row = fn.winline()
  else
    float_opt.anchor = 'NW'
    float_opt.col = outline_conf.win_width + 1
    float_opt.row = row - 1
  end

  self.preview_bufnr, self.preview_winid = win
    :new_float(float_opt, false, true)
    :setlines(lines)
    :bufopt({
      ['bufhidden'] = 'wipe',
      ['filetype'] = vim.bo[self.main_buf].filetype,
      ['buftype'] = 'nofile',
    })
    :winopt({
      ['winhl'] = 'NormalFloat:SagaNormal,FloatBorder:SagaBorder',
      ['sidescrolloff'] = 5,
    })
    :wininfo()
end

function ot:update_preview_win(lines)
  local win_spec = self:calc_preview_win_spec(lines)

  local win_config = api.nvim_win_get_config(self.preview_winid)

  win
    :from_exist(self.preview_bufnr, self.preview_winid)
    :setlines(lines)
    :winsetconf(vim.tbl_extend('force', win_config, {
      row = fn.winline(),
      height = win_spec.height,
      width = win_spec.width,
    }))
end

function ot:refresh()
  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'SagaSymbolUpdate',
    callback = function(args)
      if
        not self.bufnr
        or not api.nvim_buf_is_valid(self.bufnr)
        or api.nvim_get_current_buf() ~= args.data.bufnr
      then
        return
      end
      api.nvim_set_option_value('modifiable', true, { buf = self.bufnr })
      vim.schedule(function()
        self:parse(args.data.symbols)
        self.main_buf = args.data.bufnr
      end)
    end,
  })

  api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function(args)
      if args.buf == self.main_buf then
        return
      end
      local res = not util.nvim_ten() and symbol:get_buf_symbols(args.buf)
        or require('lspsaga.symbol.head'):get_buf_symbols(args.buf)

      if not res or not res.symbols or #res.symbols == 0 then
        return
      end
      local curline = api.nvim_win_get_cursor(0)[1]
      self.main_buf = args.buf
      self:parse(res.symbols, curline)
    end,
  })
end

function ot:preview()
  api.nvim_create_autocmd('CursorMoved', {
    group = group,
    buffer = self.bufnr,
    callback = function()
      local curlnum = unpack(api.nvim_win_get_cursor(self.winid))
      local node = slist.find_node(self.list, curlnum)
      if not node then
        if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
          api.nvim_win_close(self.preview_winid, true)
          self.preview_winid = nil
          self.preview_bufnr = nil
        end
        return
      end
      local range = node.value.range or node.value.location.range
      local lines =
        api.nvim_buf_get_lines(self.main_buf, range.start.line, range['end'].line + 1, false)
      if not self.preview_winid or not api.nvim_win_is_valid(self.preview_winid) then
        self:create_preview_win(lines)
      else
        self:update_preview_win(lines)
      end
    end,
  })

  api.nvim_create_autocmd('BufLeave', {
    buffer = self.bufnr,
    callback = function()
      if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
        api.nvim_win_close(self.preview_winid, true)
        self.preview_winid = nil
        self.preview_bufnr = nil
      end
    end,
  })
end

function ot:float_preview()
  api.nvim_create_autocmd('CursorMoved', {
    group = group,
    buffer = self.bufnr,
    callback = function()
      local curlnum = api.nvim_win_get_cursor(self.winid)[1]
      local curnode = slist.find_node(self.list, curlnum)
      if not curnode then
        return
      end
      local range = curnode.value.range
      local start = range.start.line
      local erow = range['end'].line
      erow = start == erow and erow + 1 or erow
      local lines = api.nvim_buf_get_lines(self.main_buf, start, erow, false)
      api.nvim_buf_set_lines(self.rbufnr, 0, -1, false, lines)
    end,
  })
end

function ot:auto_close()
  api.nvim_create_autocmd('WinEnter', {
    group = group,
    callback = function()
      if api.nvim_get_current_win() == self.winid and #api.nvim_list_wins() == 1 then
        api.nvim_win_set_buf(self.winid, api.nvim_create_buf(true, true))
        api.nvim_del_augroup_by_id(group)
        clean_ctx()
      end
    end,
    desc = '[Lspsaga] auto close the outline window when is last',
  })
end

function ot:clean_after_close()
  api.nvim_create_autocmd('BufDelete', {
    buffer = self.bufnr,
    callback = function(args)
      if args.buf == self.bufnr then
        clean_ctx()
      end
    end,
  })
end

function ot:normal_fn()
  self:clean_after_close()
  self:refresh()

  if config.outline.auto_preview then
    self:preview()
  end

  if outline_conf.auto_close then
    self:auto_close()
  end
end

function ot:keymap()
  util.map_keys(self.bufnr, config.outline.keys.toggle_or_jump, function()
    self:toggle_or_jump()
  end)

  util.map_keys(self.bufnr, config.outline.keys.jump, function()
    local curlnum = unpack(api.nvim_win_get_cursor(self.winid))
    local node = slist.find_node(self.list, curlnum)
    if not node then
      return
    end
    local pos =
      { node.value.selectionRange.start.line + 1, node.value.selectionRange.start.character }
    local callerwinid = self.callerwinid

    if config.outline.layout == 'normal' and config.outline.close_after_jump then
      util.close_win({ self.winid, self.rwinid })
      clean_ctx()
    elseif config.outline.layout == 'float' then
      ly:close()
      clean_ctx()
    end

    api.nvim_set_current_win(callerwinid)
    api.nvim_win_set_cursor(callerwinid, pos)
    local width = #api.nvim_get_current_line()
    beacon({ pos[1] - 1, 0 }, width)
  end)

  util.map_keys(self.bufnr, config.outline.keys.quit, function()
    util.close_win({ self.winid, self.rwinid })
    clean_ctx()
  end)
end

function ot:outline(buf)
  if self.winid and api.nvim_win_is_valid(self.winid) then
    util.close_win({ self.winid, self.rwinid })
    clean_ctx()
    return
  end

  self.main_buf = buf or api.nvim_get_current_buf()
  self.callerwinid = api.nvim_get_current_win()
  local curline = api.nvim_win_get_cursor(0)[1]
  local res = not util.nvim_ten() and symbol:get_buf_symbols(buf)
    or require('lspsaga.symbol.head'):get_buf_symbols(buf)

  if not res or not res.symbols or #res.symbols == 0 then
    vim.notify(
      '[lspsaga] failed finding symbols - server may not be initialized, try again later.',
      vim.log.levels.INFO
    )
    return
  end

  if not self.winid or not api.nvim_win_is_valid(self.winid) then
    if config.outline.layout == 'normal' then
      self.bufnr, self.winid = outline_normal_win()
      self:normal_fn()
    else
      self.bufnr, self.winid, self.rbufnr, self.rwinid = outline_in_float()
      self:float_preview()
    end
  end

  self.list = slist.new()
  self:parse(res.symbols, curline)
  self:keymap()
  -- clean autocmd
  api.nvim_create_autocmd('BufWipeout', {
    buffer = self.bufnr,
    callback = function()
      clean_ctx()
    end,
  })
end

return setmetatable(ctx, ot)
