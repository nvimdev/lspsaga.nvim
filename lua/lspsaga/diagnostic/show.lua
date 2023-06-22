local api, fn = vim.api, vim.fn
local win = require('lspsaga.window')
local util = require('lspsaga.util')
local diag = require('lspsaga.diagnostic')
local config = require('lspsaga').config
local ui = config.ui
local diag_conf = config.diagnostic
local ns = api.nvim_create_namespace('SagaDiagnostic')
local nvim_buf_set_extmark = api.nvim_buf_set_extmark
local nvim_buf_add_highlight = api.nvim_buf_add_highlight
local nvim_buf_set_lines = api.nvim_buf_set_lines
local ctx = {}
local sd = {}
sd.__index = sd

function sd.__newindex(t, k, v)
  rawset(t, k, v)
end

--- clean ctx
local function clean_ctx()
  for i, _ in pairs(ctx) do
    ctx[i] = nil
  end
end

function sd:create_win(opt)
  local curbuf = api.nvim_get_current_buf()
  local content = api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  local increase = util.win_height_increase(content)
  local max_len = util.get_max_content_length(content)
  local max_height = math.floor(vim.o.lines * diag_conf.max_show_height)
  local max_width = math.floor(vim.o.columns * diag_conf.max_show_width)
  local float_opt = {
    width = math.min(max_width, max_len),
    height = math.min(max_height, #content + increase),
  }

  if config.ui.title then
    if opt.buffer then
      float_opt.title = 'Buffer'
    elseif opt.line then
      float_opt.title = 'Line'
    elseif opt.cursor then
      float_opt.title = 'Cursor'
    else
      float_opt.title = 'Workspace'
    end
    float_opt.title_pos = 'center'
  end

  local close_autocmds =
    { 'CursorMoved', 'CursorMovedI', 'InsertEnter', 'BufDelete', 'WinScrolled' }
  if opt.arg and opt.arg == '++unfocus' then
    opt.focusable = false
    close_autocmds[#close_autocmds] = 'BufLeave'
    float_opt.enter = false
  else
    opt.focusable = true
    api.nvim_create_autocmd('BufEnter', {
      callback = function(args)
        if not self.winid or not api.nvim_win_is_valid(self.winid) then
          pcall(api.nvim_del_autocmd, args.id)
        end
        local cur_buf = api.nvim_get_current_buf()
        if cur_buf ~= self.bufnr and self.winid and api.nvim_win_is_valid(self.winid) then
          api.nvim_win_close(self.winid, true)
          clean_ctx()
          pcall(api.nvim_del_autocmd, args.id)
        end
      end,
    })
  end

  self.bufnr, self.winid = win
    :new_float(float_opt)
    :setlines(content)
    :bufopt({
      ['filetype'] = 'markdown',
      ['modifiable'] = false,
    })
    :winopt({
      ['conceallevel'] = 2,
      ['concealcursor'] = 'niv',
      ['winhl'] = 'NormalFloat:DiagnosticShowNormal,Border:DiagnosticShowBorder',
    })
    :wininfo()

  api.nvim_win_set_cursor(self.winid, { 2, 3 })
  for _, key in ipairs(diag_conf.keys.quit_in_show) do
    util.map_keys(self.bufnr, 'n', key, function()
      local curwin = api.nvim_get_current_win()
      if curwin ~= self.winid then
        return
      end
      if api.nvim_win_is_valid(curwin) then
        api.nvim_win_close(curwin, true)
        clean_ctx()
      end
    end)
  end

  vim.defer_fn(function()
    api.nvim_create_autocmd(close_autocmds, {
      buffer = curbuf,
      once = true,
      callback = function()
        api.nvim_win_close(self.winid, true)
      end,
    })
  end, 0)
end

---@private sort table by diagnsotic severity
local function sort_by_severity(entrys)
  return table.sort(entrys, function(k1, k2)
    return k1.severity < k2.severity
  end)
end

function sd:show(opt)
  local indent = (' '):rep(3)
  self.bufnr = api.nvim_create_buf(false, false)

  local curnode = opt.entrys_list
  while curnode do
    curnode.expand = true
    for i, entry in ipairs(curnode.diags) do
      local line_count = api.nvim_buf_line_count(self.bufnr)
      if i == 1 then
        ---@diagnostic disable-next-line: param-type-mismatch
        local fname = fn.fnamemodify(api.nvim_buf_get_name(tonumber(entry.bufnr)), ':t')
        -- local counts = diag:get_diag_counts(curnode.diags)
        local text = '  ' .. fname .. ' ' .. entry.bufnr
        nvim_buf_set_lines(self.bufnr, line_count - 1, -1, false, { text })
        nvim_buf_set_extmark(self.bufnr, ns, 0, 0, {
          virt_text = {
            { config.ui.collapse, 'SagaCollapse' },
          },
          virt_text_pos = 'overlay',
          hl_mode = 'combine',
        })
      else
        nvim_buf_set_lines(self.bufnr, -1, -1, false, { indent .. entry.message })
        for j = 0, 2 do
          nvim_buf_set_extmark(self.bufnr, ns, 0, j, {
            virt_text = {
              { i == #curnode.diags and config.ui.lines[1] or config.ui.lines[2] },
              { config.ui.lines[4], 'SagaVirtLine' },
            },
            virt_text_pos = 'overlay',
            hl_mode = 'combine',
          })
        end
      end
    end
    curnode = curnode.next
  end
  self:create_win(opt)
  util.map_keys(self.bufnr, 'n', diag_conf.keys.expand_or_jump, function() end)
end

local function new_node()
  return {
    next = nil,
    diags = {},
    expand = false,
  }
end

---single linked list
local function generate_list(entrys)
  local list = new_node()

  local curnode
  for _, item in ipairs(entrys) do
    if #list.diags == 0 then
      curnode = list
    elseif item.bufnr ~= curnode.diags[#curnode.diags].bufnr then
      if not curnode.next then
        curnode.next = new_node()
      end
      curnode = curnode.next
    end
    curnode.diags[#curnode.diags + 1] = item
  end
  return list
end

function sd:show_diagnostics(opt)
  local entrys = diag:get_diagnostic(opt)
  if next(entrys) == nil then
    return
  end
  opt.entrys_list = generate_list(entrys)
  self:show(opt)
end

return setmetatable(ctx, sd)
