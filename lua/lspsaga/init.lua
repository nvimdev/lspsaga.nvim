local api = vim.api
local saga = {}
saga.saga_augroup = api.nvim_create_augroup('Lspsaga', { clear = true })

local default_config = {
  ui = {
    border = 'single',
    devicon = true,
    title = true,
    winblend = 0,
    expand = '',
    collapse = '',
    code_action = '💡',
    incoming = ' ',
    outgoing = ' ',
    actionfix = ' ',
    hover = ' ',
    theme = 'arrow',
    lines = { '┗', '┣', '┃', '━' },
    kind = {},
    imp_sign = '󰳛 ',
  },
  hover = {
    max_width = 0.6,
    open_link = 'gx',
    open_browser = '!chrome',
  },
  diagnostic = {
    on_insert = false,
    on_insert_follow = false,
    insert_winblend = 0,
    show_code_action = true,
    show_source = true,
    jump_num_shortcut = true,
    max_width = 0.7,
    max_height = 0.6,
    max_show_width = 0.9,
    max_show_height = 0.6,
    text_hl_follow = true,
    border_follow = true,
    extend_relatedInformation = true,
    keys = {
      exec_action = 'o',
      quit = 'q',
      expand_or_jump = '<CR>',
      quit_in_show = { 'q', '<ESC>' },
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
    sign = true,
    debounce = 10,
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
    max_height = 0.5,
    min_width = 30,
    force_max_height = false,
    keys = {
      jump_to = 'p',
      expand_or_jump = 'o',
      vsplit = 's',
      split = 'i',
      tabe = 't',
      tabnew = 'r',
      quit = { 'q', '<ESC>' },
      close_in_preview = '<ESC>',
    },
  },
  definition = {
    width = 0.6,
    height = 0.5,
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
    separator = ' › ',
    hide_keyword = true,
    show_file = true,
    folder_level = 1,
    color_mode = true,
    dely = 300,
  },
  outline = {
    win_position = 'right',
    win_width = 30,
    --category
    layout = 'category',
    auto_preview = true,
    auto_refresh = true,
    auto_close = true,
    preview_width = 0.4,
    close_after_jump = false,
    keys = {
      expand_or_jump = 'o',
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
  implement = {
    enable = true,
    interval = 100,
    timeout = 100,
    sign = true,
    virtual_text = true,
    priority = 100,
  },
  beacon = {
    enable = true,
    frequency = 7,
  },
}

function saga.setup(opts)
  opts = opts or {}
  saga.config = vim.tbl_deep_extend('force', default_config, opts)

  require('lspsaga.highlight'):init_highlight()
  if saga.config.lightbulb.enable then
    require('lspsaga.codeaction.lightbulb').lb_autocmd()
  end

  if saga.config.symbol_in_winbar.enable then
    require('lspsaga.symbol'):winbar()
  end

  if saga.config.diagnostic.on_insert then
    require('lspsaga.diagnostic.insert').on_insert()
  end
end

return saga
