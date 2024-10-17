local api = vim.api
local saga = {}
saga.saga_augroup = api.nvim_create_augroup('Lspsaga', { clear = true })

local default_config = {
  ui = {
    winbar_prefix = '',
    border = 'rounded',
    devicon = true,
    foldericon = true,
    title = true,
    expand = '⊞',
    collapse = '⊟',
    code_action = '💡',
    lines = { '┗', '┣', '┃', '━', '┏' },
    kind = nil,
    button = { '', '' },
    imp_sign = '󰳛 ',
    use_nerd = true,
  },
  hover = {
    max_width = 0.9,
    max_height = 0.8,
    open_link = 'gx',
    open_cmd = '!chrome',
  },
  diagnostic = {
    show_layout = 'float',
    show_normal_height = 10,
    jump_num_shortcut = true,
    auto_preview = false,
    max_width = 0.8,
    max_height = 0.6,
    max_show_width = 0.9,
    max_show_height = 0.6,
    wrap_long_lines = true,
    extend_relatedInformation = false,
    diagnostic_only_current = false,
    keys = {
      exec_action = 'o',
      quit = 'q',
      toggle_or_jump = '<CR>',
      quit_in_show = { 'q', '<ESC>' },
    },
  },
  code_action = {
    num_shortcut = true,
    show_server_name = false,
    extend_gitsigns = false,
    only_in_cursor = true,
    max_height = 0.3,
    cursorline = true,
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
    enable_in_insert = true,
    ignore = {
      clients = {},
      ft = {},
    },
  },
  scroll_preview = {
    scroll_down = '<C-f>',
    scroll_up = '<C-b>',
  },
  request_timeout = 2000,
  finder = {
    max_height = 0.5,
    left_width = 0.4,
    methods = {},
    default = 'ref+imp',
    layout = 'float',
    silent = false,
    filter = {},
    fname_sub = nil,
    sp_inexist = false,
    sp_global = false,
    ly_botright = false,
    number = vim.o.number,
    relativenumber = vim.o.relativenumber,
    keys = {
      shuttle = '[w',
      toggle_or_open = 'o',
      vsplit = 's',
      split = 'i',
      tabe = 't',
      tabnew = 'r',
      quit = 'q',
      close = '<C-c>k',
    },
  },
  definition = {
    width = 0.6,
    height = 0.5,
    save_pos = false,
    number = vim.o.number,
    relativenumber = vim.o.relativenumber,
    keys = {
      edit = '<C-o>',
      vsplit = '<C-v>',
      split = '<C-x>',
      tabe = '<C-t>',
      tabnew = '<C-c>n',
      quit = 'q',
      close = '<ESC>',
    },
  },
  rename = {
    in_select = true,
    auto_save = false,
    project_max_width = 0.5,
    project_max_height = 0.5,
    keys = {
      quit = '<C-k>',
      exec = '<CR>',
      select = 'x',
    },
  },
  symbol_in_winbar = {
    enable = true,
    separator = ' › ',
    hide_keyword = false,
    ignore_patterns = nil,
    show_file = true,
    folder_level = 1,
    color_mode = true,
    delay = 300,
  },
  outline = {
    win_position = 'right',
    win_width = 30,
    auto_preview = true,
    detail = true,
    auto_close = true,
    close_after_jump = false,
    layout = 'normal',
    max_height = 0.5,
    left_width = 0.3,
    keys = {
      toggle_or_jump = 'o',
      quit = 'q',
      jump = 'e',
    },
  },
  callhierarchy = {
    layout = 'float',
    left_width = 0.2,
    keys = {
      edit = 'e',
      vsplit = 's',
      split = 'i',
      tabe = 't',
      close = '<C-c>k',
      quit = 'q',
      shuttle = '[w',
      toggle_or_req = 'u',
    },
  },
  typehierarchy = {
    layout = 'float',
    left_width = 0.2,
    keys = {
      edit = 'e',
      vsplit = 's',
      split = 'i',
      tabe = 't',
      close = '<C-c>k',
      quit = 'q',
      shuttle = '[w',
      toggle_or_req = 'u',
    },
  },
  implement = {
    enable = false,
    sign = true,
    lang = {},
    virtual_text = true,
    priority = 100,
  },
  beacon = {
    enable = true,
    frequency = 7,
  },
  floaterm = {
    height = 0.7,
    width = 0.7,
  },
}

function saga.setup(opts)
  opts = opts or {}
  saga.config = vim.tbl_deep_extend('force', default_config, opts)

  require('lspsaga.highlight'):init_highlight()
  if saga.config.lightbulb.enable then
    require('lspsaga.codeaction.lightbulb').lb_autocmd()
  end

  if vim.version().minor >= 10 and vim.fn.exists('##LspNotify') ~= 0 then
    require('lspsaga.symbol.head'):register_module()
  else
    if vim.version().minor >= 10 then
      print(
        "[lspsaga.nvim] you're running outdated nightly version, you'll need LspNotify autocmd event to enable improved symbol"
      )
    end
    require('lspsaga.symbol'):register_module()
  end

  if saga.config.diagnostic.diagnostic_only_current then
    require('lspsaga.diagnostic.virt').diag_on_current()
  end
end

return saga
