local api, lsp, util = vim.api, vim.lsp, vim.lsp.util
local window = require('lspsaga.window')
local action = require('lspsaga.action')
local libs = require('lspsaga.libs')
local wrap = require('lspsaga.wrap')
local npcall = vim.F.npcall
local hover = {}

local function find_window_by_var(name, value)
  for _, win in ipairs(api.nvim_list_wins()) do
    if npcall(api.nvim_win_get_var, win, name) == value then
      return win
    end
  end
end

local function open_floating_preview(contents, syntax, opts)
  vim.validate({
    contents = { contents, 't' },
    syntax = { syntax, 's', true },
    opts = { opts, 't', true },
  })
  opts = opts or {}
  opts.wrap = opts.wrap ~= false -- wrapping by default
  opts.stylize_markdown = opts.stylize_markdown ~= false and vim.g.syntax_on ~= nil
  opts.focus = opts.focus ~= false
  opts.close_events = opts.close_events or { 'CursorMoved', 'CursorMovedI', 'InsertCharPre' }

  local bufnr = api.nvim_get_current_buf()

  -- check if this popup is focusable and we need to focus
  if opts.focus_id and opts.focusable ~= false and opts.focus then
    -- Go back to previous window if we are in a focusable one
    local current_winnr = api.nvim_get_current_win()
    if npcall(api.nvim_win_get_var, current_winnr, opts.focus_id) then
      api.nvim_command('wincmd p')
      return bufnr, current_winnr
    end
    do
      local win = find_window_by_var(opts.focus_id, bufnr)
      if win and api.nvim_win_is_valid(win) and vim.fn.pumvisible() == 0 then
        -- focus and return the existing buf, win
        api.nvim_set_current_win(win)
        api.nvim_command('stopinsert')
        return api.nvim_win_get_buf(win), win
      end
    end
  end

  -- check if another floating preview already exists for this buffer
  -- and close it if needed
  local existing_float = npcall(api.nvim_buf_get_var, bufnr, 'lsp_floating_preview')
  if existing_float and api.nvim_win_is_valid(existing_float) then
    api.nvim_win_close(existing_float, true)
  end

  local floating_bufnr = api.nvim_create_buf(false, true)
  local do_stylize = syntax == 'markdown' and opts.stylize_markdown

  -- Clean up input: trim empty lines from the end, pad
  contents = lsp.util._trim(contents, opts)

  if do_stylize then
    -- applies the syntax and sets the lines to the buffer
    contents = lsp.util.stylize_markdown(floating_bufnr, contents, opts)
  else
    if syntax then
      api.nvim_buf_set_option(floating_bufnr, 'syntax', syntax)
    end
    api.nvim_buf_set_lines(floating_bufnr, 0, -1, true, contents)
  end

  -- Compute size of float needed to show (wrapped) lines
  if opts.wrap then
    opts.wrap_at = opts.wrap_at or api.nvim_win_get_width(0)
  else
    opts.wrap_at = nil
  end
  local width, height = lsp.util._make_floating_popup_size(contents, opts)

  local max_float_width = window.get_max_float_width()

  if width > max_float_width then
    width = max_float_width
  end

  local stripped = wrap.wrap_contents(contents, width)

  height = #stripped

  local float_option = lsp.util.make_floating_popup_options(width, height, opts)

  local contents_opt = {
    contents = stripped,
    highlight = 'LspSagaHoverBorder',
    bufnr = floating_bufnr,
  }

  local floating_winnr
  floating_bufnr, floating_winnr = window.create_win_with_border(contents_opt, float_option)

  -- disable folding
  api.nvim_win_set_option(floating_winnr, 'foldenable', false)
  -- soft wrapping
  api.nvim_win_set_option(floating_winnr, 'wrap', false)

  api.nvim_buf_set_keymap(
    floating_bufnr,
    'n',
    'q',
    '<cmd>bdelete<cr>',
    { silent = true, noremap = true, nowait = true }
  )

  local current_buffer = api.nvim_get_current_buf()
  libs.close_preview_autocmd(current_buffer, floating_winnr, opts.close_events)

  -- save focus_id
  if opts.focus_id then
    api.nvim_win_set_var(floating_winnr, opts.focus_id, bufnr)
  end
  api.nvim_buf_set_var(bufnr, 'lsp_floating_preview', floating_winnr)

  return floating_bufnr, floating_winnr
end

hover.handler = function(_, result, ctx, config)
  if not (result and result.contents) then
    return
  end
  config = config or {}
  config.focus_id = ctx.method
  if not (result and result.contents) then
    vim.notify('No information available')
    return
  end
  local markdown_lines = util.convert_input_to_markdown_lines(result.contents)
  markdown_lines = util.trim_empty_lines(markdown_lines)
  if vim.tbl_isempty(markdown_lines) then
    vim.notify('No information available')
    return
  end
  return open_floating_preview(markdown_lines, 'markdown', config)
end

function hover.render_hover_doc()
  --if has diagnostic window close
  window.nvim_win_try_close()
  if hover.has_saga_hover() then
    local winid = api.nvim_win_get_var(0, 'lspsaga_hoverwin_data')[1]
    api.nvim_set_current_win(winid)
    return
  end

  -- see #439
  if vim.bo.filetype == 'help' then
    api.nvim_feedkeys('K', 'ni', true)
    return
  end

  local params = util.make_position_params()
  vim.lsp.buf_request(0, 'textDocument/hover', params, hover.handler)
end

function hover.has_saga_hover()
  local has_hover_win, datas = pcall(api.nvim_win_get_var, 0, 'lspsaga_hoverwin_data')
  if not has_hover_win then
    return false
  end
  if api.nvim_win_is_valid(datas[1]) then
    return true
  end
  return false
end

function hover.close_hover_window()
  if hover.has_saga_hover() then
    local data = npcall(api.nvim_win_get_var, 0, 'lspsaga_hoverwin_data')
    api.nvim_win_close(data[1], true)
  end
end

-- 1 mean down -1 mean up
function hover.scroll_in_hover(direction)
  local has_hover_win, hover_data = pcall(api.nvim_win_get_var, 0, 'lspsaga_hoverwin_data')
  if not has_hover_win then
    return
  end
  local hover_win, height, current_win_lnum, last_lnum =
    hover_data[1], hover_data[2], hover_data[3], hover_data[4]
  if not api.nvim_win_is_valid(hover_win) then
    return
  end
  current_win_lnum = action.scroll_in_win(hover_win, direction, current_win_lnum, last_lnum, height)
  api.nvim_win_set_var(
    0,
    'lspsaga_hoverwin_data',
    { hover_win, height, current_win_lnum, last_lnum }
  )
end

return hover
