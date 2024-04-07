local api = vim.api
local kind = require('lspsaga.lspkind').kind

local function hi_define()
  return {
    -- general
    SagaTitle = { link = 'Title' },
    SagaBorder = { link = 'FloatBorder' },
    SagaNormal = { link = 'NormalFloat' },
    SagaToggle = { link = 'Comment' },
    SagaBeacon = { bg = '#c43963' },
    SagaVirtLine = { fg = '#444a4d' },
    SagaSpinnerTitle = { link = 'Statement' },
    SagaSpinner = { link = 'Statement' },
    SagaText = { link = 'Comment' },
    SagaSelect = { link = 'String' },
    SagaSearch = { link = 'Search' },
    SagaFinderFname = { link = 'Function' },
    SagaDetail = { link = 'Comment' },
    SagaInCurrent = { link = 'KeyWord' },
    SagaCount = { bg = 'gray', fg = 'white', bold = true },
    SagaSep = { link = 'Comment' },

    -- code action
    ActionFix = { link = 'Keyword' },
    ActionPreviewNormal = { link = 'SagaNormal' },
    ActionPreviewBorder = { link = 'SagaBorder' },
    ActionPreviewTitle = { link = 'Title' },
    CodeActionText = { link = '@variable' },
    CodeActionNumber = { link = 'DiffAdd' },
    CodeActionCursorLine = { link = 'CursorLine' },
    -- hover
    HoverNormal = { link = 'SagaNormal' },
    HoverBorder = { link = 'SagaBorder' },
    -- rename
    RenameBorder = { link = 'SagaBorder' },
    RenameNormal = { link = 'Statement' },
    RenameMatch = { link = 'Search' },
    -- diagnostic
    DiagnosticBorder = { link = 'SagaBorder' },
    DiagnosticNormal = { link = 'SagaNormal' },
    DiagnosticText = {},
    DiagnosticShowNormal = { link = 'SagaNormal' },
    DiagnosticShowBorder = { link = '@property' },
    -- lightbulb
    SagaLightBulb = { link = 'DiagnosticSignHint' },
    -- Float term
    TerminalBorder = { link = 'SagaBorder' },
    TerminalNormal = { link = 'SagaNormal' },
    -- Implement
    SagaImpIcon = { link = 'PreProc' },
    --Winbar
    SagaWinbarSep = { link = 'Operator' },
    SagaWinbarFileName = { link = 'SagaFileName' },
    SagaWinbarFolderName = { link = 'SagaFolderName' },
    SagaWinbarFolder = { link = 'SagaFolder' },

    -- deprecated
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
