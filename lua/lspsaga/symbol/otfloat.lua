local api, fn = vim.api, vim.fn
local ly = require('lspsaga.layout')
local config = require('lspsaga').config
local ot = require('lspsaga.symbol.outline')
local symbol = require('lspsaga.symbol')
local slist = require('lspsaga.slist')
local ns = api.nvim_create_namespace('SagaFloatOutline')
local beacon = require('lspsaga.beacon').jump_beacon
local kind = require('lspsaga.lspkind').kind
local util = require('lspsaga.util')
local of = {}
local ctx = {}
of.__index = of
function of.__newindex(t, k, v)
  rawset(t, k, v)
end

local function clean_ctx()
  for k, _ in pairs(ctx) do
    ctx[k] = nil
  end
end

local function outline_in_float()
  local win_width = api.nvim_win_get_width(0)
  local curbuf = api.nvim_get_current_buf()

  return ly:new('float')
    :left(
      math.floor(vim.o.lines * config.outline.max_height),
      math.floor(win_width * config.outline.left_width),
      _,
      'outline'
    )
    :bufopt({
      ['filetype'] = 'sagafinder',
      ['buftype'] = 'nofile',
      ['bufhidden'] = 'wipe',
    })
    :right('preview')
    :bufopt({
      ['buftype'] = 'nofile',
      ['bufhidden'] = 'wipe',
      ['filetype'] = vim.bo[curbuf].filetype,
    })
    :done()
end

function of:preview(bufnr)
  api.nvim_create_autocmd('CursorMoved', {
    buffer = self.lbufnr,
    callback = function()
      local curlnum = api.nvim_win_get_cursor(self.lwinid)[1]
      local curnode = slist.find_node(self.list, curlnum)
      if not curnode then
        return
      end
      local range = curnode.value.range
      local start = range.start.line
      local erow = range['end'].line
      if start == erow then
        erow = erow + 1
      end
      local lines = api.nvim_buf_get_lines(bufnr, start, erow, false)
      api.nvim_buf_set_lines(self.rbufnr, 0, -1, false, lines)
    end,
  })
end

function of:collapse(node, curlnum)
  local row = curlnum - 1
  local inlevel = fn.indent(curlnum)
  local tmp = node.next

  while tmp do
    local icon = kind[tmp.value.kind][2]
    local level = tmp.value.inlevel
    api.nvim_buf_set_lines(
      self.lbufnr,
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
    api.nvim_buf_set_extmark(self.lbufnr, ns, row, level - 2, {
      virt_text = { { icon, 'Saga' .. kind[tmp.value.kind][1] } },
      virt_text_pos = 'overlay',
    })
    local has_child = tmp.next and tmp.next.value.inlevel > level
    if has_child then
      api.nvim_buf_set_extmark(self.lbufnr, ns, row, level - 4, {
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

      api.nvim_buf_set_extmark(self.lbufnr, ns, row, j - 1, {
        virt_text = virt,
        virt_text_pos = 'overlay',
      })
    end

    if config.outline.detail then
      api.nvim_buf_set_extmark(self.lbufnr, ns, row, 0, {
        virt_text = { { tmp.value.detail or ' ', 'Comment' } },
      })
    end
    if not tmp or (tmp.next and tmp.next.value.inlevel <= inlevel) then
      break
    end
    tmp = tmp.next
  end

  if tmp then
    slist.update_winline(tmp, row - curlnum + 1, curlnum)
  end
end

function of:toggle_or_jump(curbuf, curwin)
  local curlnum = unpack(api.nvim_win_get_cursor(self.lwinid))
  local node = slist.find_node(self.list, curlnum)
  if not node then
    return
  end

  local count = api.nvim_buf_line_count(self.lbufnr)
  local inlevel = fn.indent(curlnum)

  if node.value.expand then
    api.nvim_set_option_value('modifiable', true, { buf = self.lbufnr })
    local _end
    for i = curlnum + 1, count do
      if inlevel >= fn.indent(i) then
        _end = i - 1
        break
      end
    end
    _end = _end or count
    api.nvim_buf_set_lines(self.lbufnr, curlnum, _end, false, {})
    api.nvim_buf_set_extmark(self.lbufnr, ns, curlnum - 1, inlevel - 4, {
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
    api.nvim_buf_set_extmark(self.lbufnr, ns, curlnum - 1, inlevel - 4, {
      id = node.value.virtid,
      virt_text = { { config.ui.collapse, 'SagaToggle' } },
      virt_text_pos = 'overlay',
    })
    self:collapse(node, curlnum)
    api.nvim_set_option_value('modifiable', false, { buf = self.bufnr })
    return
  end
  local pos =
    { node.value.selectionRange.start.line + 1, node.value.selectionRange.start.character }

  ly:close()
  clean_ctx()
  api.nvim_set_current_win(curwin)
  api.nvim_win_set_cursor(curwin, pos)
  local width = #api.nvim_get_current_line()
  beacon({ pos[1] - 1, 0 }, width)
end

function of:keymap(curbuf, curwin)
  util.map_keys(self.lbufnr, config.outline.keys.toggle_or_jump, function()
    self:toggle_or_jump(curbuf, curwin)
  end)

  util.map_keys(self.lbufnr, config.outline.keys.jump, function()
    local curlnum = unpack(api.nvim_win_get_cursor(self.lwinid))
    local node = slist.find_node(self.list, curlnum)
    if not node then
      return
    end
    local pos =
      { node.value.selectionRange.start.line + 1, node.value.selectionRange.start.character }

    ly:close()
    clean_ctx()

    api.nvim_set_current_win(curwin)
    api.nvim_win_set_cursor(curwin, pos)
    local width = #api.nvim_get_current_line()
    beacon({ pos[1] - 1, 0 }, width)
  end)

  util.map_keys(self.lbufnr, config.outline.keys.quit, function()
    ly:close()
    clean_ctx()
  end)
end

function of:render()
  local curwin = api.nvim_get_current_win()
  local curbuf = api.nvim_get_current_buf()
  local res = symbol:get_buf_symbols(curbuf)
  if not res or not res.symbols or #res.symbols == 0 then
    vim.notify(
      '[lspsaga] get symbols failed server may not initialed try again later',
      vim.log.levels.INFO
    )
    return
  end
  self.lbufnr, self.lwinid, self.rbufnr, self.rwinid = outline_in_float()
  self.list = slist.new()
  ot:parse(res.symbols, self.lbufnr, self.list)
  self:preview(curbuf)
  self:keymap(curbuf, curwin)
end

return setmetatable(ctx, of)
