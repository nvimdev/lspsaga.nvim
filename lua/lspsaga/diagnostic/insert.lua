local api, fn = vim.api, vim.fn
local window = require('lspsaga.window')
local config = require('lspsaga').config
local diag_conf = config.diagnostic
local diag = require('lspaga.diagnostic')

local function on_top_right(content)
  local width = window.get_max_content_length(content)
  if width >= math.floor(vim.o.columns * 0.75) then
    width = math.floor(vim.o.columns * 0.5)
  end
  local opt = {
    relative = 'editor',
    row = 1,
    col = vim.o.columns - width,
    height = #content,
    width = width,
    focusable = false,
  }
  return opt
end

local function get_row_col(content)
  local res = {}
  local curwin = api.nvim_get_current_win()
  local max_len = window.get_max_content_length(content)
  local current_col = api.nvim_win_get_cursor(curwin)[2]
  local end_col = api.nvim_strwidth(api.nvim_get_current_line())
  local winwidth = api.nvim_win_get_width(curwin)
  if current_col < end_col then
    current_col = end_col
  end

  if winwidth - max_len > current_col + 20 then
    res.row = fn.winline() - 1
    res.col = current_col + 20
  else
    res.row = fn.winline() + 1
    res.col = current_col + 20
  end
  return res
end

local function theme_bg()
  local conf = api.nvim_get_hl_by_name('Normal', true)
  if conf.background then
    return conf.background
  end
  return 'NONE'
end

local function on_insert()
  local winid, bufnr

  local function max_width(content)
    local width = window.get_max_content_length(content)
    if width == vim.o.columns - 10 then
      width = vim.o.columns * 0.6
    end
    return width
  end

  local function create_window(content, buf)
    local float_opt
    if not config.diagnostic.on_insert_follow then
      float_opt = on_top_right(content)
    else
      local res = get_row_col(content)
      float_opt = {
        relative = 'win',
        win = api.nvim_get_current_win(),
        width = max_width(content),
        height = #content,
        row = res.row,
        col = res.col,
        focusable = false,
      }
    end

    return window.create_win_with_border({
      contents = content,
      bufnr = buf or nil,
      winblend = config.diagnostic.insert_winblend,
      highlight = {
        normal = 'DiagnosticInsertNormal',
      },
      noborder = true,
    }, float_opt)
  end

  local function set_lines(content)
    if bufnr and api.nvim_buf_is_loaded(bufnr) then
      api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
    end
  end

  local function reduce_width()
    if not winid or not api.nvim_win_is_valid(winid) then
      return
    end
    api.nvim_win_hide(winid)
  end

  local group = api.nvim_create_augroup('Lspsaga Diagnostic on insert', { clear = true })
  api.nvim_create_autocmd('DiagnosticChanged', {
    group = group,
    callback = function(opt)
      if api.nvim_get_mode().mode ~= 'i' then
        set_lines({})
        return
      end

      local content = {}
      local hi = {}
      local diagnostics = opt.data.diagnostics
      local lnum = api.nvim_win_get_cursor(0)[1] - 1
      for _, item in pairs(diagnostics) do
        if item.lnum == lnum then
          hi[#hi + 1] = 'Diagnostic' .. diag:get_diag_type(item.severity)
          if item.message:find('\n') then
            item.message = item.message:gsub('\n', '')
          end
          content[#content + 1] = item.message
        end
      end

      if #content == 0 then
        set_lines({})
        reduce_width()
        return
      end

      if not winid or not api.nvim_win_is_valid(winid) then
        bufnr, winid =
          create_window(content, (bufnr and api.nvim_buf_is_valid(bufnr)) and bufnr or nil)
        vim.bo[bufnr].modifiable = true
        vim.wo[winid].wrap = true
      end
      set_lines(content)
      if bufnr and api.nvim_buf_is_loaded(bufnr) then
        for i = 1, #hi do
          api.nvim_buf_add_highlight(bufnr, 0, hi[i], i - 1, 0, -1)
        end
      end

      api.nvim_set_hl(0, 'DiagnosticInsertNormal', {
        background = theme_bg(),
        default = true,
      })

      if not diag_conf.on_insert_follow then
        api.nvim_win_set_config(winid, on_top_right(content))
        return
      end

      local curwin = api.nvim_get_current_win()
      local res = get_row_col(content)
      api.nvim_win_set_config(winid, {
        relative = 'win',
        win = curwin,
        height = #content,
        width = max_width(content),
        row = res.row,
        col = res.col,
      })
    end,
  })

  api.nvim_create_autocmd('ModeChanged', {
    group = group,
    callback = function()
      if winid and api.nvim_win_is_valid(winid) then
        set_lines({})
        reduce_width()
      end
    end,
  })

  api.nvim_create_user_command('DiagnosticInsertDisable', function()
    if winid and api.nvim_win_is_valid(winid) then
      api.nvim_win_close(winid, true)
      winid = nil
      bufnr = nil
    end
    api.nvim_del_augroup_by_id(group)
  end, {})
end

return {
  on_insert = on_insert,
}
