local api = vim.api

local function theme_normal()
  local conf = api.nvim_get_hl_by_name('Normal', true)
  if conf.background then
    return conf.background
  end
  return 'NONE'
end

local function hi_define()
  local bg = theme_normal()
  return {
    -- general
    TitleString = { link = 'Title' },
    TitleIcon = { link = 'Repeat' },
    SagaBorder = { link = 'FloatBorder' },
    SagaNormal = { bg = bg },
    SagaExpand = { fg = '#475164' },
    SagaCollapse = { fg = '#475164' },
    SagaCount = { link = 'Comment' },
    SagaBeacon = { bg = '#c43963' },
    -- code action
    ActionFix = { link = 'Keyword' },
    ActionPreviewNormal = { link = 'SagaNormal' },
    ActionPreviewBorder = { link = 'SagaBorder' },
    ActionPreviewTitle = { link = 'Title' },
    CodeActionNormal = { link = 'SagaNormal' },
    CodeActionBorder = { link = 'SagaBorder' },
    CodeActionText = { link = '@variable' },
    CodeActionNumber = { link = 'DiffAdd' },
    -- finder
    FinderSelection = { link = 'String' },
    FinderFName = {},
    FinderCode = { link = 'Comment' },
    FinderCount = { link = 'Constant' },
    FinderIcon = { link = 'Type' },
    FinderType = { link = '@property' },
    FinderStart = { link = 'Function' },
    --finder spinner
    FinderSpinnerTitle = { link = 'Statement' },
    FinderSpinner = { link = 'Statement' },
    FinderPreview = { link = 'Search' },
    FinderLines = { link = 'Operator' },
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
    RenameNormal = { link = 'Statement' },
    RenameMatch = { link = 'Search' },
    -- diagnostic
    DiagnosticBorder = { link = 'SagaBorder' },
    DiagnosticSource = { link = 'Comment' },
    DiagnosticNormal = { link = 'SagaNormal' },
    DiagnosticText = {},
    DiagnosticBufnr = { link = '@variable' },
    DiagnosticFname = { link = 'KeyWord' },
    DiagnosticShowNormal = { link = 'SagaNormal' },
    DiagnosticShowBorder = { link = '@property' },
    -- Call Hierachry
    CallHierarchyNormal = { link = 'SagaNormal' },
    CallHierarchyBorder = { link = 'SagaBorder' },
    CallHierarchyIcon = { link = 'TitleIcon' },
    CallHierarchyTitle = { link = 'Title' },
    -- lightbulb
    SagaLightBulb = { link = 'DiagnosticSignHint' },
    -- shadow
    SagaShadow = { link = 'FloatShadow' },
    -- Outline
    OutlineIndent = { fg = '#806d9e' },
    OutlinePreviewBorder = { link = 'SagaNormal' },
    OutlinePreviewNormal = { link = 'SagaBorder' },
    OutlineWinSeparator = { link = 'WinSeparator' },
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
}
