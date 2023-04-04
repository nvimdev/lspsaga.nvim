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
local nvim_buf_add_highlight = api.nvim_buf_add_highlight
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

function sd:create_win(opt, content)
  local curbuf = api.nvim_get_current_buf()
  local increase = window.win_height_increase(content)
  local max_len = window.get_max_content_length(content)
  local max_height = math.floor(vim.o.lines * diag_conf.max_show_height)
  local max_width = math.floor(vim.o.columns * diag_conf.max_show_width)
  local float_opt = {
    width = max_len < max_width and max_len or max_width,
    height = #content + increase > max_height and max_height or #content + increase,
    no_size_override = true,
  }

  if fn.has('nvim-0.9') == 1 and config.ui.title then
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

  local content_opt = {
    contents = {},
    filetype = 'markdown',
    enter = true,
    bufnr = self.bufnr,
    wrap = true,
    highlight = {
      normal = 'DiagnosticShowNormal',
      border = 'DiagnosticShowBorder',
    },
  }

  local close_autocmds =
    { 'CursorMoved', 'CursorMovedI', 'InsertEnter', 'BufDelete', 'WinScrolled' }
  if opt.arg and opt.arg == '++unfocus' then
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

  api.nvim_win_set_cursor(self.winid, { 2, 3 })
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

local function find_node_by_lnum(lnum, entrys)
  for _, items in pairs(entrys) do
    for _, item in ipairs(items.diags) do
      if item.winline == lnum then
        return item
      end
    end
  end
end

local function change_winline(cond, direction, entrys)
  for _, items in pairs(entrys) do
    for _, item in ipairs(items.diags) do
      if cond(item) then
        item.winline = item.winline + direction
      end
    end
  end
end

function sd:show(opt)
  local indent = '   '
  local line_count = 0
  local content = {}
  local curbuf = api.nvim_get_current_buf()
  local icon_data = libs.icon_from_devicon(vim.bo[curbuf].filetype)
  self.bufnr = api.nvim_create_buf(false, false)
  vim.bo[self.bufnr].buftype = 'nofile'

  local titlehi = {}
  for bufnr, items in pairs(opt.entrys) do
    ---@diagnostic disable-next-line: param-type-mismatch
    local fname = fn.fnamemodify(api.nvim_buf_get_name(tonumber(bufnr)), ':t')
    local counts = diag:get_diag_counts(items.diags)
    local text = ui.collapse .. ' ' .. icon_data[1] .. fname .. ' Bufnr[[' .. bufnr .. ']]'

    local diaghi = {}
    for i, v in ipairs(counts) do
      local sign = diag:get_diagnostic_sign(i)
      if v > 0 then
        local start = #text
        text = text .. ' ' .. sign .. v
        diaghi[#diaghi + 1] = {
          'Diagnostic' .. diag:get_diag_type(i),
          start,
          #text,
        }
      end
    end

    content[#content + 1] = text
    api.nvim_buf_set_lines(self.bufnr, line_count, line_count + 1, false, { text })
    line_count = line_count + 1
    titlehi[tostring(line_count - 1)] = {
      { 'SagaCollapse', 0, #ui.collapse },
      icon_data[2] and {
        icon_data[2],
        #ui.collapse + 1,
        #ui.collapse + 1 + #icon_data[1],
      } or nil,
      {
        'DiagnosticFname',
        #ui.collapse + 1 + (icon_data[2] and #icon_data[1] or 0),
        #ui.collapse + 1 + (icon_data[2] and #icon_data[1] or 0) + #fname,
      },
      {
        'DiagnosticBufnr',
        #ui.collapse + 2 + (icon_data[2] and #icon_data[1] or 0) + #fname,
        #ui.collapse + 14 + (icon_data[2] and #icon_data[1] or 0) + #fname,
      },
      unpack(diaghi),
    }

    for _, v in ipairs(titlehi[tostring(line_count - 1)]) do
      nvim_buf_add_highlight(self.bufnr, 0, v[1], line_count - 1, v[2], v[3])
    end

    items.expand = true
    for i, item in ipairs(items.diags) do
      if item.message:find('\n') then
        item.message = item.message:gsub('\n', '')
      end
      text = indent .. item.message
      api.nvim_buf_set_lines(self.bufnr, line_count, line_count + 1, false, { text })
      line_count = line_count + 1
      nvim_buf_add_highlight(
        self.bufnr,
        0,
        diag_conf.text_hl_follow and 'Diagnostic' .. diag:get_diag_type(item.severity)
          or 'DiagnosticText',
        line_count - 1,
        3,
        -1
      )
      item.winline = line_count
      content[#content + 1] = text
      nvim_buf_set_extmark(self.bufnr, ns, line_count - 1, 0, {
        virt_text = {
          { i == #items.diags and ui.lines[1] or ui.lines[2], 'FinderLines' },
          { ui.lines[4]:rep(2), 'FinderLines' },
        },
        virt_text_pos = 'overlay',
      })
    end
    api.nvim_buf_set_lines(self.bufnr, line_count, line_count + 1, false, { '' })
    line_count = line_count + 1
  end

  vim.bo[self.bufnr].modifiable = false

  local nontext = api.nvim_get_hl_by_name('NonText', true)
  api.nvim_set_hl(ns, 'NonText', {
    link = 'FinderLines',
  })

  local function expand_or_collapse(text)
    local change = text:find(ui.expand) and { ui.expand, ui.collapse } or { ui.collapse, ui.expand }
    text = text:gsub(change[1], change[2])
    local curline = api.nvim_win_get_cursor(self.winid)[1]
    vim.bo[self.bufnr].modifiable = true
    local bufnr = text:match('%[%[(.+)%]%]')
    local data = opt.entrys[tostring(bufnr)]
    local hi = titlehi[tostring(curline - 1)]
    if data.expand then
      api.nvim_buf_clear_namespace(self.bufnr, ns, curline - 1, curline + #data.diags)
      api.nvim_buf_set_lines(self.bufnr, curline - 1, curline + #data.diags, false, { text })
      for _, v in ipairs(hi) do
        nvim_buf_add_highlight(self.bufnr, 0, v[1], curline - 1, v[2], v[3])
      end
      for _, v in ipairs(data.diags) do
        v.winline = -1
      end
      change_winline(function(item)
        return item.winline > curline + #data.diags
      end, -#data.diags, opt.entrys)
      data.expand = false
    else
      local lines = {}
      vim.tbl_map(function(k)
        lines[#lines + 1] = indent .. k.message
      end, data.diags)
      api.nvim_buf_set_lines(self.bufnr, curline - 1, curline, false, { text, unpack(lines) })
      for _, v in ipairs(hi) do
        nvim_buf_add_highlight(self.bufnr, 0, v[1], curline - 1, v[2], v[3])
      end

      for i, v in ipairs(data.diags) do
        v.winline = curline + i
        nvim_buf_add_highlight(
          self.bufnr,
          0,
          diag_conf.text_hl_follow and 'Diagnostic' .. diag:get_diag_type(v.severity)
            or 'DiagnosticText',
          v.winline - 1,
          3,
          -1
        )
        nvim_buf_set_extmark(self.bufnr, ns, curline + i - 1, 0, {
          virt_text = {
            { i == #data.diags and ui.lines[1] or ui.lines[2], 'FinderLines' },
            { ui.lines[4]:rep(2), 'FinderLines' },
          },
          virt_text_pos = 'overlay',
        })
      end
      data.expand = true
    end
    vim.bo[self.bufnr].modifiable = false
  end

  nvim_buf_set_keymap(self.bufnr, 'n', diag_conf.keys.expand_or_jump, '', {
    nowait = true,
    silent = true,
    callback = function()
      local text = api.nvim_get_current_line()
      if text:find(ui.expand) or text:find(ui.collapse) then
        expand_or_collapse(text)
        return
      end
      local winline = api.nvim_win_get_cursor(self.winid)[1]
      api.nvim_set_hl(0, 'NonText', {
        foreground = nontext.foreground,
        background = nontext.background,
      })

      local entry = find_node_by_lnum(winline, opt.entrys)

      if entry then
        api.nvim_win_close(self.winid, true)
        clean_ctx()
        local winid = fn.bufwinid(entry.bufnr)
        if winid == -1 then
          winid = api.nvim_get_current_win()
        end
        api.nvim_set_current_win(winid)
        api.nvim_win_set_cursor(winid, { entry.lnum + 1, entry.col })
        local width = #api.nvim_get_current_line()
        libs.jump_beacon({ entry.lnum, entry.col }, width)
      end
    end,
  })

  self:create_win(opt, content)
end

---migreate diagnostic to a table that
---use in show function
local function migrate_diagnostics(entrys)
  local tbl = {}
  for _, item in ipairs(entrys) do
    local key = tostring(item.bufnr)
    if not tbl[key] then
      tbl[key] = {
        diags = {},
      }
    end
    tbl[key].diags[#tbl[key].diags + 1] = item
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
