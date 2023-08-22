local api = vim.api
local win = require('lspsaga.window')
local config = require('lspsaga').config
local term = {}

local ctx = {}

function term:open_float_terminal(args)
  local cur_buf = api.nvim_get_current_buf()
  if not vim.tbl_isempty(ctx) and ctx.term_bufnr == cur_buf then
    api.nvim_win_close(ctx.term_winid, true)
    ctx.term_winid = nil
    if ctx.cur_win and ctx.pos then
      api.nvim_set_current_win(ctx.cur_win)
      api.nvim_win_set_cursor(0, ctx.pos)
      ctx.cur_win = nil
      ctx.pos = nil
    end
    return
  end

  local cmd = (#args > 0 and args[1]) and args[1]
    or (require('lspsaga.util').iswin and 'cmd.exe' or os.getenv('SHELL'))
  local dir = (#args > 1 and args[2]) and args[2] or vim.fn.getcwd()
  -- calculate our floating window size
  local win_height = math.ceil(vim.o.lines * config.floaterm.height)
  local win_width = math.ceil(vim.o.columns * config.floaterm.width)

  -- and its starting position
  local row = math.ceil((vim.o.lines - win_height) * 0.4)
  local col = math.ceil((vim.o.columns - win_width) * 0.5)

  -- set some options
  local float_opt = {
    style = 'minimal',
    relative = 'editor',
    width = win_width,
    height = win_height,
    row = row,
    col = col,
  }

  local spawn_new = vim.tbl_isempty(ctx) and true or false

  if not spawn_new then
    float_opt.bufnr = ctx.term_bufnr
    api.nvim_buf_set_option(ctx.term_bufnr, 'modified', false)
  end
  ctx.cur_win = api.nvim_get_current_win()
  ctx.pos = api.nvim_win_get_cursor(0)

  ctx.term_bufnr, ctx.term_winid = win
    :new_float(float_opt, true, true)
    :bufopt('bufhidden', 'hide')
    :winhl('TerminalNormal', 'TerminalBorder')
    :wininfo()

  if spawn_new then
    local termopen_opts = {
      on_exit = function()
        if ctx.term_winid and api.nvim_win_is_valid(ctx.term_winid) then
          api.nvim_win_close(ctx.term_winid, true)
        end
        if ctx.shadow_winid and api.nvim_win_is_valid(ctx.shadow_winid) then
          api.nvim_win_close(ctx.shadow_winid, true)
        end
        ctx = {}
      end,
    }
    if dir then
      termopen_opts.cwd = dir
    end
    vim.fn.termopen(cmd, termopen_opts)
  end

  vim.cmd('startinsert!')

  api.nvim_create_autocmd('WinClosed', {
    buffer = ctx.term_bufnr,
    callback = function()
      if ctx.shadow_winid and api.nvim_win_is_valid(ctx.shadow_winid) then
        api.nvim_win_close(ctx.shadow_winid, true)
        ctx.shadow_winid = nil
      end
    end,
  })
end

return term
