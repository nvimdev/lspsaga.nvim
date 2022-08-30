local api = vim.api
local window = require('lspsaga.window')
local term = {}

function term:open_float_terminal(command)
  local cmd = command or os.getenv('SHELL')

  -- get dimensions
  local width = api.nvim_get_option('columns')
  local height = api.nvim_get_option('lines')

  -- calculate our floating window size
  local win_height = math.ceil(height * 0.7)
  local win_width = math.ceil(width * 0.7)

  -- and its starting position
  local row = math.ceil((height - win_height) * 0.4)
  local col = math.ceil((width - win_width) * 0.5)

  -- set some options
  local opts = {
    style = 'minimal',
    relative = 'editor',
    width = win_width,
    height = win_height,
    row = row,
    col = col,
  }

  local content_opts = {
    contents = {},
    enter = true,
    winblend = 0,
  }
  if self.term_bufnr then
    content_opts.bufnr = self.term_bufnr
    if api.nvim_buf_is_valid(self.term_bufnr) then
      api.nvim_buf_set_option(self.term_bufnr, 'modified', false)
    end
  end

  self.term_bufnr, self.term_winid, self.shadow_bufnr, self.shadow_winid =
    window.open_shadow_float_win(content_opts, opts)

  if not self.first_open then
    self.first_open = true
    vim.fn.termopen(cmd, {
      on_exit = function(...) end,
    })
  end
  vim.cmd('startinsert!')
end

function term:close_float_terminal()
  if self.term_winid and api.nvim_win_is_valid(self.term_winid) then
    api.nvim_win_hide(self.term_winid)
    api.nvim_win_hide(self.shadow_winid)
  end
end

return term
