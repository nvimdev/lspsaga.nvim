local api = vim.api
local kind = require('lspsaga.lspkind').kind

local function hi_define()
  return {
    -- general
    TitleString = { link = 'Title' },
    TitleIcon = { link = 'Repeat' },
    SagaBorder = { link = 'FloatBorder' },
    SagaNormal = { link = 'NormalFloat' },
    SagaToggle = { link = 'Comment' },
    SagaCount = { link = 'Comment' },
    SagaBeacon = { bg = '#c43963' },
    SagaVirtLine = { link = 'Comment' },
    SagaSpinnerTitle = { link = 'Statement' },
    SagaSpinner = { link = 'Statement' },
    SagaFinderText = { link = 'Comment' },
    SagaSelection = { link = 'String' },
    SagaSearch = { link = 'Search' },
    -- code action
    ActionFix = { link = 'Keyword' },
    ActionPreviewNormal = { link = 'SagaNormal' },
    ActionPreviewBorder = { link = 'SagaBorder' },
    ActionPreviewTitle = { link = 'Title' },
    CodeActionNormal = { link = 'SagaNormal' },
    CodeActionBorder = { link = 'SagaBorder' },
    CodeActionText = { link = '@variable' },
    CodeActionNumber = { link = 'DiffAdd' },
    --finder spinner
    FinderPreview = { link = 'Search' },
    FinderNormal = { link = 'SagaNormal' },
    FinderBorder = { link = 'SagaBorder' },
    FinderPreviewBorder = { link = 'SagaBorder' },
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
    -- Float term
    TerminalBorder = { link = 'SagaBorder' },
    TerminalNormal = { link = 'SagaNormal' },
    -- Implement
    SagaImpIcon = { link = 'PreProc' },
    --Winbar
    SagaWinbarSep = { link = 'Operator' },
    SagaFileName = { link = 'Comment' },
    SagaFolderName = { link = 'Comment' },
  }
end

local function init_highlight()
  for group, conf in pairs(hi_define()) do
    api.nvim_set_hl(0, group, vim.tbl_extend('keep', conf, { default = true }))
  end

  for _, item in pairs(kind) do
    api.nvim_set_hl(0, 'Saga' .. item[1], { link = item[3], default = true })
  end
end

return {
  init_highlight = init_highlight,
}
