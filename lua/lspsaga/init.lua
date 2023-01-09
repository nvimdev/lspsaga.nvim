local api = vim.api
local saga = {}
saga.saga_augroup = api.nvim_create_augroup('Lspsaga', { clear = true })

local default_config = {
  ui = {
    theme = 'round',
    border = 'solid',
    winblend = 0,
    expand = '',
    collaspe = '',
    preview = ' ',
    code_action = '💡',
    diagnostic = '🐞',
    incoming = ' ',
    outgoing = ' ',
    colors = {
      --float window normal bakcground color
      normal_bg = '#1d1536',
      --title background color
      title_bg = '#afd700',
    },
    kind = {},
  },
  diagnostic = {
    twice_into = false,
    beacon = true,
    show_code_action = true,
    show_source = true,
    keys = {
      exec_action = 'o',
      quit = 'q',
    },
  },
  code_action = {
    num_shortcut = true,
    keys = {
      quit = 'q',
      exec = '<CR>',
    },
  },
  lightbulb = {
    enable = true,
    enable_in_insert = true,
    cache_code_action = true,
    sign = true,
    update_time = 150,
    sign_priority = 40,
    virtual_text = true,
  },
  preview = {
    lines_above = 0,
    lines_below = 15,
  },
  scroll_preview = {
    scroll_down = '<C-f>',
    scroll_up = '<C-b>',
  },
  finder = {
    request_timeout = 1500,
    keys = {
      open = { 'o', '<CR>' },
      vsplit = 's',
      split = 'i',
      tabe = 't',
      quit = { 'q', '<ESC>' },
    },
  },
  definition = {
    keys = {
      edit = '<C-c>o',
      vsplit = '<C-c>v',
      split = '<C-c>i',
      tabe = '<C-c>t',
      quit = 'q',
      close = '<Esc>',
    },
  },
  rename = {
    quit = '<C-c>',
    exec = '<CR>',
    in_select = true,
  },
  symbol_in_winbar = {
    enable = true,
    separator = ' ',
    hide_keyword = true,
    show_file = true,
    folder_level = 2,
  },
  outline = {
    win_position = 'right',
    win_with = '',
    win_width = 30,
    show_detail = true,
    auto_enter = true,
    auto_preview = true,
    auto_refresh = true,
    auto_close = true,
    keys = {
      jump = 'o',
      expand_collaspe = 'u',
      quit = 'q',
    },
  },
  callhierarchy = {
    show_detail = false,
    keys = {
      jump_to_preview = 'o',
      quit = 'q',
      expand_collaspe = 'u',
    },
  },
  server_filetype_map = {},
}

function saga.theme()
  local theme = {
    ['round'] = {
      left = '',
      right = '',
    },
  }

  return theme[saga.config.ui.theme]
end

function saga.init_lsp_saga(opts)
  saga.config = vim.tbl_deep_extend('force', default_config, opts)

  require('lspsaga.highlight'):init_highlight()
  if saga.config.lightbulb.enable then
    require('lspsaga.lightbulb').lb_autocmd()
  end

  if saga.config.symbol_in_winbar.enable or saga.config.symbol_in_winbar.in_custom then
    require('lspsaga.symbolwinbar').config_symbol_autocmd()
  end
end

return saga
