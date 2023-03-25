local api, fn = vim.api, vim.fn
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local diag = require('lspsaga.diagnostic')
local config = require('lspsaga').config
local ui = config.ui
local diag_conf = config.diagnostic
local nvim_buf_set_keymap = api.nvim_buf_set_keymap
local ns = api.nvim_create_namespace('SagaDiagnostic')
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

function sd:show(opt)
  local cur_buf = api.nvim_get_current_buf()
  local cur_win = api.nvim_get_current_win()
  local icon_data = libs.icon_from_devicon(vim.bo[cur_buf].filetype)
  local fname = api.nvim_buf_get_name(cur_buf)
  fname = fn.fnamemodify(fname, ':t')
  local indent = '   '

  local content = {
    ui.collapse .. icon_data[1] .. fname,
  }

  local hi = {}
  if icon_data[2] then
    hi[1] = {
      { 0, #ui.collapse, 'SagaCollapse' },
      { #ui.collapse, #ui.collapse + #icon_data[1], icon_data[2] },
    }
  end
  hi[1][#hi[1] + 1] =
    { #ui.collapse + #icon_data[1], #ui.collapse + #icon_data[1] + #fname, 'DiagnosticFname' }

  local counts = diag:get_diag_counts(opt.entrys)
  for i, count in ipairs(counts) do
    if count > 0 then
      local sign = diag:get_diagnostic_sign(i)
      local dtype = diag:get_diag_type(i)
      content[1] = content[1] .. ' ' .. sign .. count
      local prev = hi[1][#hi[1]]
      hi[1][#hi[1] + 1] = { prev[2], prev[2] + #sign, 'Diagnostic' .. dtype }
      prev = hi[1][#hi[1]]
      hi[1][#hi[1] + 1] = { prev[2] + 1, prev[2] + 1 + #tostring(count), 'Diagnostic' .. dtype }
    end
  end

  for _, entry in pairs(opt.entrys) do
    local sign = diag:get_diagnostic_sign(entry.severity)

    if entry.message then
      local line = indent
        .. sign
        .. entry.message
        .. (entry.source and '(' .. entry.source .. ')' or nil)
      if opt.buffer then
        line = line .. ' ' .. entry.lnum + 1 .. ':' .. entry.col
      end
      content[#content + 1] = line
      local hi_name = 'Diagnostic' .. diag:get_diag_type(entry.severity)
      hi[#hi + 1] = {
        { #indent, #indent + #sign, hi_name },
        {
          #indent + #sign,
          #indent + #sign + #entry.message,
          diag_conf.text_hl_follow and hi_name or 'DiagnosticText',
        },
        { #indent + #sign + #entry.message, -1, 'Comment' },
      }
    end
  end

  local increase = window.win_height_increase(content)
  local max_len = window.get_max_content_length(content)
  local max_height = math.floor(vim.o.lines * 0.6)
  local actual_height = get_actual_height(content) + increase
  local max_width = math.floor(vim.o.columns * 0.6)
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
    contents = content,
    filetype = 'markdown',
    enter = true,
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

  self.lnum_bufnr, self.lnum_winid = window.create_win_with_border(content_opt, float_opt)
  vim.wo[self.lnum_winid].conceallevel = 2
  vim.wo[self.lnum_winid].concealcursor = 'niv'
  vim.wo[self.lnum_winid].showbreak = ui.lines[3]
  vim.wo[self.lnum_winid].breakindent = true
  vim.wo[self.lnum_winid].breakindentopt = 'shift:2,sbr'

  for i, item in pairs(hi) do
    for _, scope in ipairs(item) do
      api.nvim_buf_add_highlight(self.lnum_bufnr, 0, scope[3], i - 1, scope[1], scope[2])
    end
    if i > 1 then
      local symbol = i ~= #hi and ui.lines[2] or ui.lines[1]
      -- local dtype = diag:get_diag_type(opt.entrys[i - 1].severity)
      -- local symbol_hi = config.diagnostic.text_hl_follow and 'Diagnostic' .. dtype or 'FinderLines'
      api.nvim_buf_set_extmark(self.lnum_bufnr, ns, i - 1, 0, {
        virt_text = { { symbol, 'FinderLines' }, { ui.lines[4]:rep(2), 'FinderLines' } },
        virt_text_pos = 'overlay',
      })
    end
  end

  api.nvim_win_set_cursor(self.lnum_winid, { 2, 7 })
  local nontext = api.nvim_get_hl_by_name('NonText', true)
  api.nvim_set_hl(0, 'NonText', {
    link = 'FinderLines',
  })

  nvim_buf_set_keymap(self.lnum_bufnr, 'n', diag_conf.keys.jump_in_show, '', {
    nowait = true,
    silent = true,
    callback = function()
      local index = api.nvim_win_get_cursor(self.lnum_winid)[1] - 1
      local entry = opt.entrys[index]
      api.nvim_set_hl(0, 'NonText', {
        foreground = nontext.foreground,
        background = nontext.background,
      })

      if entry then
        api.nvim_win_close(self.lnum_winid, true)
        clean_ctx()
        api.nvim_set_current_win(cur_win)
        api.nvim_win_set_cursor(cur_win, { entry.lnum + 1, entry.col })
        local width = #api.nvim_get_current_line()
        libs.jump_beacon({ entry.lnum, entry.col }, width)
      end
    end,
  })

  vim.defer_fn(function()
    libs.close_preview_autocmd(cur_buf, self.lnum_winid, close_autocmds)
  end, 0)
end

function sd:show_diagnostics(opt)
  local entrys = self:get_diagnostic(opt)
  if next(entrys) == nil then
    return
  end
  sort_by_severity(entrys)
  opt.entrys = entrys
  self:show(opt)
end

return setmetatable(ctx, sd)
