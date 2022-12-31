local api = vim.api
local ui = require('lspsaga').config.ui
local bg = ui.normal

local highlights = {
  -- general
  TitleString = { bg = ui.title, fg = '#013e77', bold = true },
  TitleSymbol = { bg = bg, fg = ui.title },
  TitleIcon = { bg = ui.title, fg = '#89d957' },
  SagaBorder = { bg = bg },
  -- code action
  ActionPreviewNormal = { link = 'SagaBorder' },
  ActionPreviewBorder = { link = 'SagaBorder' },
  ActionPreviewTitle = { fg = '#CBA6F7', bg = bg },
  CodeActionNormal = { link = 'SagaBorder' },
  CodeActionBorder = { link = 'SagaBorder' },
  CodeActionText = { fg = '#e8e1c5' },
  -- finder
  FinderSelection = { fg = '#89d957', bold = true },
  TargetFileName = { fg = '#d1d4cf' },
  FinderCount = { link = 'Title' },
  --finder spinner
  FinderSpinnerBorder = { fg = '#51afef' },
  FinderSpinnerTitle = { fg = '#b33076', bold = true },
  FinderSpinner = { fg = '#b33076', bold = true },
  FinderPreviewSearch = { link = 'Search' },
  FinderVirtText = { fg = '#c95942' },
  FinderNormal = { link = 'SagaBorder' },
  FinderBorder = { link = 'SagaBorder' },
  FinderPreviewBorder = { link = 'SagaBorder' },
  FinderTitleString = { bg = bg, fg = '#ffd6b1', bold = true },
  FinderTitleIcon = { bg = bg, fg = '#89d957' },
  -- definition
  DefinitionBorder = { link = 'SagaBorder' },
  DefinitionNormal = { link = 'SagaBorder' },
  DefinitionSearch = { link = 'Search' },
  -- hover
  HoverNormal = { link = 'SagaBorder' },
  HoverBorder = { link = 'SagaBorder' },
  -- rename
  RenameBorder = { link = 'SagaBorder' },
  RenameNormal = { fg = '#f17866', bg = bg },
  RenameMatch = { link = 'Search' },
  -- diagnostic
  DiagnosticSource = { fg = 'gray' },
  DiagnosticNormal = { link = 'SagaBorder' },
  DiagnosticErrorBorder = { link = 'SagaBorder' },
  DiagnosticWarnBorder = { link = 'SagaBorder' },
  DiagnosticHintBorder = { link = 'SagaBorder' },
  DiagnosticInfoBorder = { link = 'SagaBorder' },
  -- Call Hierachry
  CallHierarchyIcon = { fg = '#CBA6F7' },
  CallHierarchyTitle = { fg = '#9c255e' },
  -- lightbulb
  LspSagaLightBulb = { link = 'DiagnosticSignHint' },
  -- shadow
  SagaShadow = { fg = 'black' },
  -- Outline
  OutlinePreviewBorder = { link = 'SagaBorder' },
  OutlinePreviewNormal = { link = 'SagaBorder' },
  OutlineExpand = { fg = '#c955ae' },
  OutlineCollaspe = { fg = '#b8733e' },
  OutlineDetail = { fg = '#73797e' },
}

local loaded = false

local function init_highlight()
  if not loaded then
    for group, conf in pairs(highlights) do
      api.nvim_set_hl(0, group, vim.tbl_extend('keep', conf, { default = true }))
    end
  end
  require('lspsaga.lspkind').gen_outline_hi()
  loaded = true
end

return {
  init_highlight = init_highlight,
}
