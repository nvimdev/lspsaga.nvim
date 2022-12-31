local api = vim.api

local saga = {}
saga.saga_augroup = api.nvim_create_augroup('Lspsaga', { clear = true })

local default_config = {
  ui = {
    theme = 'capsule',
    border = 'solid',
    winblend = 0,
    expand = ' ',
    collaspe = ' ',
    finder_def = ' ',
    finder_imp = ' ',
    finder_ref = ' ',
    code_action = '💡',
    incoming = ' ',
    outgoing = ' ',
    background = '#1d1536',
  },
  diagnostic = {
    twice_into = true,
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
    in_select = true,
  },
  -- winbar must nightly
  symbol_in_winbar = {
    in_custom = false,
    enable = false,
    separator = ' ',
    show_file = true,
    click_support = false,
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
  call_hierarchy = {
    show_detail = false,
    keys = {
      jump_to_preview = 'o',
      quit = 'q',
      expand_collaspe = 'u',
    },
  },
  custom_kind = {},
  server_filetype_map = {},
}

function saga.theme()
  local theme = {
    ['capsule'] = {
      left = '',
      right = '',
    },
  }

  return theme[saga.config.ui.theme]
end

function saga.init_lsp_saga(opts)
  saga.config = vim.tbl_deep_extend('force', default_config, opts)

  require('lspsaga.highlight').init_highlight()
  if saga.config.lightbulb.enable then
    require('lspsaga.lightbulb').lb_autocmd()
  end

  local kind = require('lspsaga.lspkind')
  kind.load_custom_kind()

  if saga.config.symbol_in_winbar.enable or saga.config.symbol_in_winbar.in_custom then
    kind.gen_symbol_winbar_hi()
    require('lspsaga.symbolwinbar').config_symbol_autocmd()
  end
end

return saga
