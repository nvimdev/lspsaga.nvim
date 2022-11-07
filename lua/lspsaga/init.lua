local api = vim.api

local saga = {}

saga.saga_augroup = api.nvim_create_augroup('Lspsaga', { clear = true })

saga.config_values = {
  debug_print = false,
  border_style = 'single',
  saga_winblend = 0,
  -- when cusor in saga float window
  -- config these keys to move
  move_in_saga = {
    prev = '<C-p>',
    next = '<C-n>',
  },
  -- Error,Warn,Info,Hint
  diagnostic_header = { ' ', ' ', ' ', ' ' },
  -- code action title icon
  code_action_icon = '💡',
  -- if true can press number to execute the codeaction in codeaction window
  code_action_num_shortcut = true,
  code_action_lightbulb = {
    enable = true,
    enable_in_insert = true,
    cache_code_action = true,
    sign = true,
    update_time = 150,
    sign_priority = 40,
    virtual_text = true,
  },
  preview_lines_above = 0,
  max_preview_lines = 15,
  scroll_in_preview = {
    scroll_down = '<C-f>',
    scroll_up = '<C-b>',
  },
  finder_icons = {
    def = ' ',
    imp = ' ',
    ref = ' ',
  },
  finder_request_timeout = 1500,
  finder_action_keys = {
    open = { 'o', '<CR>' },
    vsplit = 's',
    split = 'i',
    tabe = 't',
    quit = { 'q', '<ESC>' },
  },
  code_action_keys = {
    quit = 'q',
    exec = '<CR>',
  },
  definition_action_keys = {
    edit = '<C-c>o',
    vsplit = '<C-c>v',
    split = '<C-c>i',
    tabe = '<C-c>t',
    quit = 'q',
  },
  rename_action_quit = '<C-c>',
  rename_in_select = true,
  -- winbar must nightly
  symbol_in_winbar = {
    in_custom = false,
    enable = false,
    separator = ' ',
    show_file = true,
    click_support = false,
  },
  show_outline = {
    win_position = 'right',
    win_with = '',
    win_width = 30,
    auto_enter = true,
    auto_preview = true,
    virt_text = '┃',
    jump_key = 'o',
    auto_refresh = true,
  },
  custom_kind = {},
  server_filetype_map = {},
}

local extend_config = function(opts)
  opts = opts or {}
  if next(opts) == nil then
    return
  end
  for key, value in pairs(opts) do
    if saga.config_values[key] == nil then
      error(string.format('[LspSaga] Key %s not exist in config values', key))
      return
    end
    if type(saga.config_values[key]) == 'table' then
      for k, v in pairs(value) do
        saga.config_values[key][k] = v
      end
    else
      saga.config_values[key] = value
    end
  end
end

function saga.init_lsp_saga(opts)
  extend_config(opts)
  local conf = saga.config_values

  if conf.code_action_lightbulb.enable then
    require('lspsaga.lightbulb').lb_autocmd()
  end

  local kind = require('lspsaga.lspkind')
  kind.load_custom_kind()

  if conf.symbol_in_winbar.enable or conf.symbol_in_winbar.in_custom then
    kind.gen_symbol_winbar_hi()
    require('lspsaga.symbolwinbar').config_symbol_autocmd()
  end
end

return saga
