local api, fn = vim.api, vim.fn
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local diag = require('lspsaga.diagnostic')
local config = require('lspsaga').config
local ui = config.ui
local diag_conf = config.diagnostic
local nvim_buf_set_keymap = api.nvim_buf_set_keymap
local ns = api.nvim_create_namespace('SagaDiagnostic')
local nvim_buf_set_extmark = api.nvim_buf_set_extmark
local co = coroutine
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
function sd:get_diagnostic(opt)
  local cur_buf = api.nvim_get_current_buf()
  if opt.buffer then
    return vim.diagnostic.get(cur_buf)
  end

  local line, col = unpack(api.nvim_win_get_cursor(0))
  local entrys = vim.diagnostic.get(cur_buf, { lnum = line - 1 })

  if opt.line then
    return entrys
  end

  if opt.cursor then
    local res = {}
    for _, v in pairs(entrys) do
      if v.col <= col and v.end_col >= col then
        res[#res + 1] = v
      end
    end
    return res
  end

  return vim.diagnostic.get()
end

---@private sort table by diagnsotic severity
local function sort_by_severity(entrys)
  table.sort(entrys, function(k1, k2)
    return k1.severity < k2.severity
  end)
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

function sd:create_win(opt, content)
  local curbuf = api.nvim_get_current_buf()
  local increase = window.win_height_increase(content)
  local max_len = window.get_max_content_length(content)
  local max_height = math.floor(vim.o.lines * 0.6)
  local actual_height = get_actual_height(content) + increase
  local max_width = math.floor(vim.o.columns * 0.8)
  local float_opt = {
    width = max_len < max_width and max_len or max_width,
    height = actual_height > max_height and max_height or actual_height,
    no_size_override = true,
  }

  if fn.has('nvim-0.9') == 1 then
    if opt.buffer then
      float_opt.title = 'Buffer'
    elseif opt.line then
      float_opt.title = 'Line'
    else
      float_opt.title = 'Workspace'
    end
    float_opt.title_pos = 'center'
  end

  local content_opt = {
    contents = {},
    filetype = 'markdown',
    enter = true,
    bufnr = self.bufnr,
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
    content_opt.enter = false
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

  _, self.winid = window.create_win_with_border(content_opt, float_opt)
  vim.wo[self.winid].conceallevel = 2
  vim.wo[self.winid].concealcursor = 'niv'
  vim.wo[self.winid].showbreak = ui.lines[3]
  vim.wo[self.winid].breakindent = true
  vim.wo[self.winid].breakindentopt = 'shift:2,sbr'
  vim.wo[self.winid].linebreak = true

  -- api.nvim_win_set_cursor(self.winid, { 2, 7 })
  local nontext = api.nvim_get_hl_by_name('NonText', true)
  api.nvim_set_hl(0, 'NonText', {
    link = 'FinderLines',
  })

  nvim_buf_set_keymap(self.bufnr, 'n', diag_conf.keys.jump_in_show, '', {
    nowait = true,
    silent = true,
    callback = function()
      local index = api.nvim_win_get_cursor(self.winid)[1] - 1
      local entry = opt.entrys[index]
      api.nvim_set_hl(0, 'NonText', {
        foreground = nontext.foreground,
        background = nontext.background,
      })

      if entry then
        api.nvim_win_close(self.winid, true)
        clean_ctx()
        -- api.nvim_set_current_win(cur_win)
        -- api.nvim_win_set_cursor(cur_win, { entry.lnum + 1, entry.col })
        -- local width = #api.nvim_get_current_line()
        -- libs.jump_beacon({ entry.lnum, entry.col }, width)
      end
    end,
  })

  for _, key in ipairs(diag_conf.keys.quit_in_show) do
    nvim_buf_set_keymap(self.bufnr, 'n', key, '', {
      noremap = true,
      nowait = true,
      callback = function()
        local curwin = api.nvim_get_current_win()
        if curwin ~= self.winid then
          return
        end
        if api.nvim_win_is_valid(curwin) then
          api.nvim_win_close(curwin, true)
          clean_ctx()
        end
      end,
    })
  end

  vim.defer_fn(function()
    libs.close_preview_autocmd(curbuf, self.winid, close_autocmds)
  end, 0)
end

function sd:show(opt)
  local indent = '   '
  local line_count = 0
  local content = {}

  self.bufnr = api.nvim_create_buf(false, false)
  for bufnr, items in pairs(opt.entrys) do
    local icon_data = libs.icon_from_devicon(vim.bo[tonumber(bufnr)].filetype)
    ---@diagnostic disable-next-line: param-type-mismatch
    local fname = fn.fnamemodify(api.nvim_buf_get_name(tonumber(bufnr)), ':t')
    local counts = diag:get_diag_counts(items)
    local text = ui.collapse .. ' ' .. icon_data[1] .. fname
    for i, v in ipairs(counts) do
      if v > 0 then
        text = text .. ' ' .. diag:get_diagnostic_sign(i) .. v
      end
    end
    content[#content + 1] = text
    api.nvim_buf_set_lines(self.bufnr, line_count, line_count + 1, false, { text })
    line_count = line_count + 1
    for i, item in ipairs(items) do
      if item.message:find('\n') then
        item.message = item.message:gsub('\n', '')
      end
      text = indent .. item.message
      api.nvim_buf_set_lines(self.bufnr, line_count, line_count + 1, false, { text })
      line_count = line_count + 1
      content[#content + 1] = text
      nvim_buf_set_extmark(self.bufnr, ns, line_count - 1, 0, {
        virt_text = {
          { i == #items and ui.lines[1] or ui.lines[2], 'FinderLines' },
          { ui.lines[4]:rep(2), 'FinderLines' },
        },
        virt_text_pos = 'overlay',
      })
    end
  end

  self:create_win(opt, content)
end

---migreate diagnostic to a table that
---use in show function
local function migrate_diagnostics(entrys)
  local tbl = {}
  for _, item in ipairs(entrys) do
    local key = tostring(item.bufnr)
    if not tbl[key] then
      tbl[key] = {}
    end
    tbl[key][#tbl[key] + 1] = item
  end
  return tbl
end

function sd:show_diagnostics(opt)
  local entrys = self:get_diagnostic(opt)
  if next(entrys) == nil then
    return
  end
  sort_by_severity(entrys)
  opt.entrys = migrate_diagnostics(entrys)
  self:show(opt)
end

return setmetatable(ctx, sd)
