local api = vim.api
local saga = {}
saga.saga_augroup = api.nvim_create_augroup('Lspsaga', { clear = true })

local default_config = {
  ui = {
    border = 'single',
    title = true,
    winblend = 0,
    expand = '',
    collapse = '',
    code_action = '💡',
    incoming = ' ',
    outgoing = ' ',
    hover = ' ',
    kind = {},
  },
  diagnostic = {
    on_insert = true,
    on_insert_follow = false,
    insert_winblend = 0,
    show_code_action = true,
    show_source = true,
    jump_num_shortcut = true,
    max_width = 0.7,
    text_hl_follow = false,
    border_follow = true,
    keys = {
      exec_action = 'o',
      quit = 'q',
      go_action = 'g',
    },
  },
  code_action = {
    num_shortcut = true,
    show_server_name = false,
    extend_gitsigns = false,
    keys = {
      quit = 'q',
      exec = '<CR>',
    },
  },
  lightbulb = {
    enable = true,
    enable_in_insert = true,
    -- cache_code_action = true,
    sign = true,
    sign_priority = 40,
    virtual_text = true,
  },
  preview = {
    lines_above = 0,
    lines_below = 10,
  },
  scroll_preview = {
    scroll_down = '<C-f>',
    scroll_up = '<C-b>',
  },
  request_timeout = 2000,
  finder = {
    --percentage
    max_height = 0.5,
    keys = {
      jump_to = 'p',
      edit = { 'o', '<CR>' },
      vsplit = 's',
      split = 'i',
      tabe = 't',
      tabnew = 'r',
      quit = { 'q', '<ESC>' },
      close_in_preview = '<ESC>',
    },
  },
  definition = {
    edit = '<C-c>o',
    vsplit = '<C-c>v',
    split = '<C-c>i',
    tabe = '<C-c>t',
    quit = 'q',
  },
  rename = {
    quit = '<C-c>',
    exec = '<CR>',
    mark = 'x',
    confirm = '<CR>',
    in_select = true,
  },
  symbol_in_winbar = {
    enable = true,
    ignore_patterns = {},
    separator = ' ',
    hide_keyword = true,
    show_file = true,
    folder_level = 2,
    respect_root = false,
    color_mode = true,
  },
  outline = {
    win_position = 'right',
    win_with = '',
    win_width = 30,
    auto_preview = true,
    auto_refresh = true,
    auto_close = true,
    custom_sort = nil,
    keys = {
      jump = 'o',
      expand_collapse = 'u',
      quit = 'q',
    },
  },
  callhierarchy = {
    show_detail = false,
    keys = {
      edit = 'e',
      vsplit = 's',
      split = 'i',
      tabe = 't',
      jump = 'o',
      quit = 'q',
      expand_collapse = 'u',
    },
  },
  beacon = {
    enable = true,
    frequency = 7,
  },
  server_filetype_map = {},
}

function saga.setup(opts)
  opts = opts or {}
  saga.config = vim.tbl_deep_extend('force', default_config, opts)

  require('lspsaga.highlight'):init_highlight()
  require('lspsaga.lspkind').init_kind_hl()
  if saga.config.lightbulb.enable then
    require('lspsaga.lightbulb').lb_autocmd()
  end

  if saga.config.symbol_in_winbar.enable then
    require('lspsaga.symbolwinbar'):symbol_autocmd()
  end

  if saga.config.diagnostic.on_insert then
    require('lspsaga.diagnostic'):on_insert()
  end
end

return saga
