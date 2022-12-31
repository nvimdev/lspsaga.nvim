local api = vim.api
local ui = require('lspsaga').config_values.ui
local bg = ui.background

local highlights = {
  -- code action
  ActionPreviewNormal = { bg = bg },
  ActionPreviewBorder = { bg = bg },
  ActionPreviewTitle = { fg = '#CBA6F7', bg = bg },

  LspSagaCodeActionTitle = { fg = '#da8548', bold = true },
  LspSagaCodeActionBorder = { fg = '#CBA6F7' },
  LspSagaCodeActionTrunCateLine = { link = 'LspSagaCodeActionBorder' },
  LspSagaCodeActionContent = { fg = '#98be65', bold = true },
  -- finder
  LspSagaLspFinderBorder = { fg = '#51afef' },
  LspSagaAutoPreview = { fg = '#51afef' },
  LspSagaFinderSelection = { fg = '#89d957', bold = true },
  TargetFileName = { fg = '#d1d4cf' },
  FinderParam = { fg = '#CBA6F7', bg = '#392a52', bold = true },
  DefinitionsIcon = { fg = '#e3e346' },
  Definitions = { fg = '#CBA6F7', bold = true },
  DefinitionCount = { link = 'Title' },
  ReferencesIcon = { fg = '#e3e346' },
  References = { fg = '#CBA6F7', bold = true },
  ReferencesCount = { link = 'Title' },
  ImplementsIcon = { fg = '#e3e346' },
  Implements = { fg = '#CBA6F7', bold = true },
  ImplementsCount = { link = 'Title' },
  --finder spinner
  FinderSpinnerBorder = { fg = '#51afef' },
  FinderSpinnerTitle = { fg = '#b33076', bold = true },
  FinderSpinner = { fg = '#b33076', bold = true },
  FinderPreviewSearch = { link = 'Search' },
  FinderTitle = { bg = '#876ec2', fg = '#e0c06e' },
  FinderPreview = { bg = '#876ec2', fg = '#e0c06e' },
  FinderVirtText = { fg = '#c95942' },
  -- definition
  DefinitionBorder = { fg = '#b3deef' },
  DefinitionArrow = { fg = '#ad475f' },
  DefinitionSearch = { link = 'Search' },
  DefinitionFile = { bg = '#151838' },
  -- hover
  LspSagaHoverBorder = { fg = '#f7bb3b' },
  LspSagaHoverTrunCateLine = { link = 'LspSagaHoverBorder' },
  -- rename
  LspSagaRenameBorder = { fg = '#3bb6c4' },
  LspSagaRenameMatch = { link = 'Search' },
  -- diagnostic
  LspSagaDiagnosticBorder = { fg = '#CBA6F7' },
  DiagnosticSource = { link = 'Comment' },
  DiagnosticNormal = { bg = bg },

  DiagnosticErrorBorder = { bg = bg },
  DiagnosticWarnBorder = { bg = bg },
  DiagnosticHintBorder = { bg = bg },
  DiagnosticInfoBorder = { bg = bg },

  DiagnosticText = { fg = '#c77ba7' },
  DiagnosticActionText = { fg = '#d4bf87' },

  -- Call Hierachry
  CallHierarchyIcon = { fg = '#CBA6F7' },
  CallHierarchyTitle = { fg = '#9c255e' },
  -- lightbulb
  LspSagaLightBulb = { link = 'DiagnosticSignHint' },
  -- shadow
  SagaShadow = { fg = 'black' },
  -- float
  LspSagaBorderTitle = { link = 'String' },
  -- Outline
  LSOutlinePreviewBorder = { fg = '#52ad70' },
  OutlineExpand = { fg = '#c955ae' },
  OutlineCollaspe = { fg = '#b8733e' },
  OutlineDetail = { fg = '#73797e' },
  -- all floatwindow of lspsaga
  LspFloatWinNormal = { link = 'Normal' },
}

local loaded = false

local function init_highlight()
  if not loaded then
    for group, conf in pairs(highlights) do
      api.nvim_set_hl(0, group, vim.tbl_extend('keep', conf, { default = true }))
    end
  end
  loaded = true
end

return {
  init_highlight = init_highlight,
}
