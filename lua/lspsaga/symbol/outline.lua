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

local function get_hi_prefix()
  return 'SagaWinbar'
end

local function find_node(data, line)
  for _, node in pairs(data or {}) do
    if node.winline == line then
      return node
    end
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
      node.winline = row
      buf_set_extmark(self.bufnr, ns, row - 1, #indent - 2, {
        virt_text = { { kind[node.kind][2], 'SagaWinbar' .. kind[node.kind][1] } },
        virt_text_pos = 'overlay',
      })
      local inlevel = fn.indent(row)
      if inlevel > 4 then
        for j = 1, inlevel - 4, 2 do
          local virt = {}
          if not node.children and j + 2 > inlevel - 4 then
            virt = i == #data
                and {
                  { config.ui.lines[1], 'SagaVirtLine' },
                  { config.ui.lines[4]:rep(2), 'SagaVirtLine' },
                }
              or {
                { config.ui.lines[2], 'SagaVirtLine' },
                { config.ui.lines[4]:rep(2), 'SagaVirtLine' },
              }
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
end

local function binary_search(bufnr, winid)
  local curlnum = unpack(api.nvim_win_get_cursor(winid))
  local res = symbol:get_buf_symbols(bufnr)
  if not res or not res.symbols then
    return
  end
  local left = 1
  local right = #res.symbols
  local mid
  while left < right do
    mid = bit.rshift(left + right, 1)
    local node = res.symbols[mid]
    if node.winline == curlnum then
      return mid
    elseif node.winline > curlnum then
      right = mid
    else
      left = mid
    end
  end
end

function ot:expand_or_jump() end

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
