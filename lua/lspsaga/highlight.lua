local api = vim.api

local function get_colors()
  return {
    red = '#e95678',
    magenta = '#b33076',
    orange = '#FF8700',
    yellow = '#f7bb3b',
    green = '#afd700',
    cyan = '#36d0e0',
    blue = '#61afef',
    purple = '#CBA6F7',
    white = '#d1d4cf',
    black = '#1c1c19',
    gray = '#6e6b6b',
    fg = '#f2f2bf',
  }
end

local function theme_normal()
  local conf = api.nvim_get_hl_by_name('Normal', true)
  if conf.background then
    return conf.background
  end
  return 'NONE'
end

local function hi_define()
  local colors = get_colors()
  local bg = theme_normal()
  return {
    -- general
    TitleString = { fg = colors.fg },
    TitleIcon = { fg = colors.red },
    SagaBorder = { bg = bg, fg = colors.blue },
    SagaNormal = { bg = bg },
    SagaExpand = { fg = colors.red },
    SagaCollapse = { fg = colors.red },
    SagaBeacon = { bg = colors.magenta },
    -- code action
    ActionPreviewNormal = { link = 'SagaNormal' },
    ActionPreviewBorder = { link = 'SagaBorder' },
    ActionPreviewTitle = { fg = colors.purple, bg = bg },
    CodeActionNormal = { link = 'SagaNormal' },
    CodeActionBorder = { link = 'SagaBorder' },
    CodeActionText = { fg = colors.orange },
    CodeActionNumber = { fg = colors.green },
    -- finder
    FinderSelection = { fg = colors.cyan, bold = true },
    FinderFileName = { fg = colors.white },
    FinderCount = { link = 'Label' },
    FinderIcon = { fg = colors.cyan },
    FinderType = { fg = colors.purple },
    --finder spinner
    FinderSpinnerTitle = { fg = colors.magenta, bold = true },
    FinderSpinner = { fg = colors.magenta, bold = true },
    FinderPreviewSearch = { link = 'Search' },
    FinderVirtText = { fg = colors.red },
    FinderNormal = { link = 'SagaNormal' },
    FinderBorder = { link = 'SagaBorder' },
    FinderPreviewBorder = { link = 'SagaBorder' },
    -- definition
    DefinitionBorder = { link = 'SagaBorder' },
    DefinitionNormal = { link = 'SagaNormal' },
    DefinitionSearch = { link = 'Search' },
    -- hover
    HoverNormal = { link = 'SagaNormal' },
    HoverBorder = { link = 'SagaBorder' },
    -- rename
    RenameBorder = { link = 'SagaBorder' },
    RenameNormal = { fg = colors.orange, bg = bg },
    RenameMatch = { link = 'Search' },
    -- diagnostic
    DiagnosticBorder = { link = 'SagaBorder' },
    DiagnosticSource = { fg = 'gray' },
    DiagnosticNormal = { link = 'SagaNormal' },
    DiagnosticErrorBorder = { link = 'DiagnosticError' },
    DiagnosticWarnBorder = { link = 'DiagnosticWarn' },
    DiagnosticHintBorder = { link = 'DiagnosticHint' },
    DiagnosticInfoBorder = { link = 'DiagnosticInfo' },
    DiagnosticPos = { fg = colors.gray },
    DiagnosticWord = { fg = colors.fg },
    -- Call Hierachry
    CallHierarchyNormal = { link = 'SagaNormal' },
    CallHierarchyBorder = { link = 'SagaBorder' },
    CallHierarchyIcon = { fg = colors.purple },
    CallHierarchyTitle = { fg = colors.red },
    -- lightbulb
    LspSagaLightBulb = { link = 'DiagnosticSignHint' },
    -- shadow
    SagaShadow = { bg = colors.black },
    -- Outline
    OutlineIndent = { fg = colors.magenta },
    OutlinePreviewBorder = { link = 'SagaNormal' },
    OutlinePreviewNormal = { link = 'SagaBorder' },
    -- Float term
    TerminalBorder = { link = 'SagaBorder' },
    TerminalNormal = { link = 'SagaNormal' },
  }
end

local function get_kind()
  return require('lspsaga.lspkind').get_kind(get_colors())()
end

local function gen_symbol_winbar_hi()
  local prefix = 'LspSagaWinbar'
  local winbar_sep = 'LspSagaWinbarSep'
  local colors = get_colors()
  local kind = get_kind()

  local winbar_ns = api.nvim_create_namespace('LspagaWinbar')
  for _, v in pairs(kind or {}) do
    api.nvim_set_hl(winbar_ns, prefix .. v[1], { fg = v[3] })
  end
  api.nvim_set_hl(winbar_ns, winbar_sep, { fg = colors.red, default = true })
  api.nvim_set_hl(winbar_ns, prefix .. 'File', { fg = colors.fg, default = true })
  api.nvim_set_hl(winbar_ns, prefix .. 'Word', { fg = colors.white, default = true })
  api.nvim_set_hl(winbar_ns, prefix .. 'FolderName', { fg = colors.fg, default = true })

  api.nvim_set_hl_ns_fast(winbar_ns)
end

local function gen_outline_hi()
  local kind = get_kind()
  for _, v in pairs(kind or {}) do
    local hi_name = 'LSOutline' .. v[1]
    local ok, tbl = pcall(api.nvim_get_hl_by_name, hi_name, true)
    if not ok or not tbl.foreground then
      api.nvim_set_hl(0, hi_name, { fg = v[3] })
    end
  end
end

local function init_highlight()
  for group, conf in pairs(hi_define()) do
    api.nvim_set_hl(0, group, vim.tbl_extend('keep', conf, { default = true }))
  end

  gen_symbol_winbar_hi()
  gen_outline_hi()
end

return {
  init_highlight = init_highlight,
  get_kind = get_kind,
  get_colors = get_colors,
}
