local ot = {}
local api, lsp, fn = vim.api, vim.lsp, vim.fn
local kind = require('lspsaga.lspkind').kind
local config = require('lspsaga').config
local util = require('lspsaga.util')
local symbol = require('lspsaga.symbol')
local win = require('lspsaga.window')
local buf_set_lines = api.nvim_buf_set_lines
local buf_set_extmark = api.nvim_buf_set_extmark
local outline_conf = config.outline
local ns = api.nvim_create_namespace('SagaOutline')
local ctx = {}

function ot.__newindex(t, k, v)
  rawset(t, k, v)
end

ot.__index = ot

local function clean_ctx()
  for k, _ in pairs(ctx) do
    ctx[k] = nil
  end
end

local function create_outline_window()
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

function ot:parse(symbols)
  local row = 0

  local function recursive_parse(data, level)
    for i, node in ipairs(data) do
      level = level or 0
      local indent = '    ' .. ('  '):rep(level)
      buf_set_lines(self.bufnr, row, -1, false, { indent .. node.name })
      row = row + 1
      if level == 0 then
        node.winline = row
      end
      buf_set_extmark(self.bufnr, ns, row - 1, #indent - 2, {
        virt_text = { { kind[node.kind][2], 'SagaWinbar' .. kind[node.kind][1] } },
        virt_text_pos = 'overlay',
      })
      local inlevel = 4 + 2 * level
      if inlevel > 4 then
        for j = 1, inlevel - 4, 2 do
          local virt = {}
          if not node.children and j + 2 > inlevel - 4 then
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
          virt_text = { { node.detail, 'Comment' } },
        })
      end

      if node.children then
        node.winline = row
        node.expand = true
        buf_set_extmark(self.bufnr, ns, row - 1, #indent - 4, {
          virt_text = { { config.ui.collapse, 'SagaCollapse' } },
          virt_text_pos = 'overlay',
        })
        recursive_parse(node.children, level + 1)
      end
    end
  end

  recursive_parse(symbols)
  api.nvim_set_option_value('modifiable', false, { buf = self.bufnr })
end

local function find_idx_by_lnum(curlnum, symbols)
  local winline
  for i = curlnum, 0, -1 do
    if fn.indent(i) == 4 then
      winline = i
      break
    end
  end

  local left = 1
  local right = #symbols
  local mid
  while left <= right do
    mid = bit.rshift(left + right, 1)
    if symbols[mid].winline == winline then
      return mid
    elseif symbols[mid].winline > winline then
      right = mid - 1
    else
      left = mid + 1
    end
  end
end

local function update_winline(idx, symbols, curlnum, val)
  local node = symbols[idx]
  local function update_children(tbl, change_state)
    for _, item in ipairs(tbl) do
      if item.winline and item.winline > curlnum then
        item.expand = change_state and val < 0 and false or true
        item.winline = item.winline + val
      end
      if item.children then
        update_children(item.children, change_state)
      end
    end
  end

  update_children(node.children, true)

  for i = idx + 1, #symbols do
    if symbols[i].winline then
      symbols[i].winline = symbols[i].winline + val
    end

    if symbols[i].children then
      update_children(symbols[i].children, false)
    end
  end
end

local function find_in_children(node, curlnum)
  for i in ipairs(node) do
    if node[i].winline and node[i].winline == curlnum then
      return node[i]
    end
    if node[i].children then
      local res = find_in_children(node[i].children, curlnum)
      if res then
        return res
      end
    end
  end
end

function ot:collapse(idx, symbols, node, curlnum)
  if not node.children then
    return
  end
  local row = curlnum - 1
  local inlevel = fn.indent(curlnum)
  local count = 0

  local function write_line(tbl, level)
    for i, item in ipairs(tbl) do
      level = level or inlevel + 2
      local icon = kind[item.kind][2]
      buf_set_lines(self.bufnr, row + 1, row + 1, false, { (' '):rep(level) .. item.name })
      count = count + 1
      row = row + 1
      buf_set_extmark(self.bufnr, ns, row, level - 2, {
        virt_text = { { icon, 'SagaWinbar' .. kind[item.kind][3] } },
        virt_text_pos = 'overlay',
      })
      if item.children then
        write_line(item.children, level + 2)
      end
      if level > 4 then
        for j = 1, level - 4, 2 do
          local virt = {}
          if not tbl.children and j + 2 > level - 4 then
            virt[#virt + 1] = i == #tbl and { config.ui.lines[1], 'SagaVirtLine' }
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
      end

      if config.outline.detail then
        buf_set_extmark(self.bufnr, ns, row, 0, {
          virt_text = { { item.detail, 'Comment' } },
        })
      end
    end
  end

  write_line(node.children)
  update_winline(idx, symbols, curlnum, count)
end

function ot:expand_or_jump()
  local curlnum = unpack(api.nvim_win_get_cursor(self.winid))
  local res = symbol:get_buf_symbols(self.main_buf)
  if not res or not res.symbols then
    return
  end
  local idx = find_idx_by_lnum(curlnum, res.symbols)
  if not idx then
    return
  end
  local node = res.symbols[idx]
  if node.winline ~= curlnum then
    node = find_in_children(node.children, curlnum)
  end
  if not node then
    return
  end
  local count = api.nvim_buf_line_count(self.bufnr)
  local inlevel = fn.indent(curlnum)

  if node.expand then
    api.nvim_set_option_value('modifiable', true, { buf = self.bufnr })
    local _end
    for i = curlnum + 1, count do
      if inlevel >= fn.indent(i) then
        _end = i - 1
        break
      end
    end
    buf_set_lines(self.bufnr, curlnum, _end or count, false, {})
    local col = fn.indent(curlnum) - 4
    buf_set_extmark(self.bufnr, ns, curlnum - 1, col, {
      virt_text = { { config.ui.expand, 'SagaExpand' } },
      virt_text_pos = 'overlay',
    })
    if _end then
      update_winline(idx, res.symbols, curlnum, -(_end - curlnum))
    end
    node.expand = false
    api.nvim_set_option_value('modifiable', false, { buf = self.bufnr })
    return
  end

  if node.expand == false then
    node.expand = true
    api.nvim_set_option_value('modifiable', true, { buf = self.bufnr })
    self:collapse(idx, res.symbols, node, curlnum)
    api.nvim_set_option_value('modifiable', false, { buf = self.bufnr })
  end
end

function ot:outline()
  self.main_buf = api.nvim_get_current_buf()
  local res = symbol:get_buf_symbols(self.main_buf)
  if not res or not res.symbols or #res.symbols == 0 then
    return
  end
  self.bufnr, self.winid = create_outline_window()
  self:parse(res.symbols)
  util.map_keys(self.bufnr, 'n', config.outline.keys.expand_or_jump, function()
    self:expand_or_jump()
  end)
end

return setmetatable(ctx, ot)
