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

local function init_highlight()
  for group, conf in pairs(hi_define()) do
    api.nvim_set_hl(0, group, vim.tbl_extend('keep', conf, { default = true }))
  end
end

return {
  init_highlight = init_highlight,
  get_colors = get_colors,
}
