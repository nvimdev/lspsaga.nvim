local api, fn = vim.api, vim.fn
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local diag = require('lspsaga.diagnostic')
local ui = require('lspsaga').config.ui
local nvim_buf_set_keymap = api.nvim_buf_set_keymap
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

---get the line or cursor diagnostics
---@param opt table
local function get_diagnostic(opt)
  local cur_buf = api.nvim_get_current_buf()
  if opt.buffer then
    return vim.diagnostic.get(cur_buf)
  end

  local line, col = unpack(api.nvim_win_get_cursor(0))
  local entrys = vim.diagnostic.get(cur_buf, { lnum = line - 1 })

  if opt.line then
    return entrys
  end

  local res = {}
  for _, v in pairs(entrys) do
    if v.col <= col and v.end_col >= col then
      res[#res + 1] = v
    end
  end
  return res
end

---@private sort table by diagnsotic severity
local function sort_by_severity(entrys)
  table.sort(entrys, function(k1, k2)
    return k1.severity < k2.severity
  end)
end

---@private append table 2 to table1
local function tbl_append(t1, t2)
  for _, v in ipairs(t2) do
    t1[#t1 + 1] = v
  end
end

local function generate_title(counts, content, width)
  local fname = fn.fnamemodify(api.nvim_buf_get_name(0), ':t')
  local title_count = ' ' .. fname
  local title_hi_scope = {}
  title_hi_scope[#title_hi_scope + 1] = { 'DiagnosticHead', 0, #title_count }

  for _, i in ipairs(vim.tbl_keys(vim.diagnostic.serverity)) do
    if counts[i] ~= 0 then
      local start = #title_count
      title_count = title_count .. ' ' .. i .. ': ' .. counts[i]
      title_hi_scope[#title_hi_scope + 1] = { 'Diagnostic' .. i, start + 1, #title_count }
    end
  end
  local title = {
    title_count,
    libs.gen_truncate_line(width),
  }

  tbl_append(content, title)

  return function(bufnr)
    for _, item in pairs(title_hi_scope) do
      api.nvim_buf_add_highlight(bufnr, 0, item[1], 0, item[2], item[3])
    end
  end
end

---@private get the actual window height when wrap is enable
local function get_actual_height(content)
  local height = 0
  for _, v in pairs(content) do
    if v:find('\n.') then
      height = height + #vim.split(v, '\n')
    else
      height = height + 1
    end
  end
  return height
end

function sd:show(entrys, dtype, arg)
  local cur_buf = api.nvim_get_current_buf()
  local cur_win = api.nvim_get_current_win()
  local content = {}
  local len = {}
  local counts = {
    Error = 0,
    Warn = 0,
    Info = 0,
    Hint = 0,
  }
  for _, entry in pairs(entrys) do
    local type = diag:get_diag_type(entry.severity)
    counts[type] = counts[type] + 1
    local start_col = entry.end_col > entry.col and entry.col or entry.end_col
    local end_col = entry.end_col > entry.col and entry.end_col or entry.col
    local code_source =
      api.nvim_buf_get_text(entry.bufnr, entry.lnum, start_col, entry.lnum, end_col, {})
    len[#len + 1] = #code_source[1]
    local line = ui.diagnostic
      .. ' '
      .. code_source[1]
      .. ' |'
      .. (dtype == 'buf' and entry.lnum + 1 or 'Col')
      .. ':'
      .. entry.col
      .. '|'
      .. '\n'
    if entry.message then
      line = line .. '  ' .. entry.message
    end
    if entry.source then
      line = line .. '(' .. entry.source .. ')'
    end
    content[#content + 1] = line
  end

  local increase = window.win_height_increase(content)
  local max_len = window.get_max_content_length(content)
  local max_height = math.floor(vim.o.lines * 0.6)
  local actual_height = get_actual_height(content) + increase
  local max_width = math.floor(vim.o.columns * 0.6)
  local opt = {
    width = max_len < max_width and max_len or max_width,
    height = actual_height > max_height and max_height or actual_height,
    no_size_override = true,
  }

  local func
  if dtype == 'buf' then
    func = generate_title(counts, content, opt.width)
  end

  local content_opt = {
    contents = content,
    filetype = 'markdown',
    wrap = true,
    highlight = {
      normal = 'DiagnosticNormal',
      border = 'DiagnosticBorder',
    },
  }

  local close_autocmds =
    { 'CursorMoved', 'CursorMovedI', 'InsertEnter', 'BufDelete', 'WinScrolled' }
  if arg and arg == '++unfocus' then
    opt.focusable = false
    close_autocmds[#close_autocmds] = 'BufLeave'
  else
    opt.focusable = true
    api.nvim_create_autocmd('BufEnter', {
      callback = function(args)
        if not self.lnum_winid or not api.nvim_win_is_valid(self.lnum_winid) then
          pcall(api.nvim_del_autocmd, args.id)
        end
        local curbuf = api.nvim_get_current_buf()
        if
          curbuf ~= self.lnum_bufnr
          and self.lnum_winid
          and api.nvim_win_is_valid(self.lnum_winid)
        then
          api.nvim_win_close(self.lnum_winid, true)
          clean_ctx()
          pcall(api.nvim_del_autocmd, args.id)
        end
      end,
    })
  end

  self.lnum_bufnr, self.lnum_winid = window.create_win_with_border(content_opt, opt)
  vim.wo[self.lnum_winid].conceallevel = 2
  vim.wo[self.lnum_winid].concealcursor = 'niv'
  vim.wo[self.lnum_winid].showbreak = 'NONE'
  vim.wo[self.lnum_winid].breakindent = true
  vim.wo[self.lnum_winid].breakindentopt = ''

  if func then
    func(self.lnum_bufnr)
  end

  api.nvim_buf_add_highlight(self.lnum_bufnr, 0, 'Comment', 1, 0, -1)

  local function get_color(hi_name)
    local color = api.nvim_get_hl_by_name(hi_name, true)
    return color.foreground
  end

  local index = func and 2 or 0
  for k, item in pairs(entrys) do
    local diag_type = diag:get_diag_type(item.severity)
    local hi = 'Diagnostic' .. diag_type
    local fg = get_color(hi)
    local col_end = 4
    api.nvim_buf_add_highlight(self.lnum_bufnr, 0, 'DiagnosticType' .. k, index, 0, col_end)
    api.nvim_set_hl(0, 'DiagnosticType' .. k, { fg = fg })
    api.nvim_buf_add_highlight(
      self.lnum_bufnr,
      0,
      'DiagnosticWord',
      index,
      col_end,
      col_end + len[k]
    )
    api.nvim_buf_add_highlight(self.lnum_bufnr, 0, 'DiagnosticPos', index, col_end + len[k] + 1, -1)
    api.nvim_buf_add_highlight(self.lnum_bufnr, 0, hi, index + 1, 2, -1)
    index = index + 2
  end

  nvim_buf_set_keymap(self.lnum_bufnr, 'n', '<CR>', '', {
    nowait = true,
    silent = true,
    callback = function()
      local text = api.nvim_get_current_line()
      local data = text:match('%d+:%d+')
      if data then
        local lnum, col = unpack(vim.split(data, ':', { trimempty = true }))
        if lnum and col then
          api.nvim_win_close(self.lnum_winid, true)
          clean_ctx()
          api.nvim_set_current_win(cur_win)
          api.nvim_win_set_cursor(cur_win, { tonumber(lnum), tonumber(col) })
          local width = #api.nvim_get_current_line()
          libs.jump_beacon({ tonumber(lnum) - 1, tonumber(col) }, width)
        end
      end
    end,
  })

  vim.defer_fn(function()
    libs.close_preview_autocmd(cur_buf, self.lnum_winid, close_autocmds)
  end, 0)
end

function sd:show_diagnostics(opt)
  local entrys = get_diagnostic(opt)
  if next(entrys) == nil then
    return
  end
  sort_by_severity(entrys)
  self:show(entrys, type, arg)
end

return setmetatable(ctx, sd)
