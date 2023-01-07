local api = vim.api
local ui = require('lspsaga').config.ui

local colors = {
  --float window normal bakcground color
  normal_bg = '#1d1536',
  --title background color
  title_bg = '#e29cb1',
  title_fg = '',
  red = '',
  orange = '',
  yellow = '',
  green = '',
  aqua = '',
  blue = '',
  purple = '',
}

local highlights = {
  -- general
  TitleString = { bg = colors.title_bg, fg = '#013e77', bold = true },
  TitleSymbol = { bg = colors.normal_bg, fg = colors.title_bg },
  TitleIcon = { bg = colors.title_bg, fg = '#89d957' },
  SagaBorder = { bg = colors.normal_bg },
  SagaExpand = { fg = '#c955ae' },
  SagaCollaspe = { fg = '#b8733e' },
  -- code action
  ActionPreviewNormal = { link = 'SagaBorder' },
  ActionPreviewBorder = { link = 'SagaBorder' },
  ActionPreviewTitle = { fg = '#CBA6F7', bg = colors.normal_bg },
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
  FinderTitleString = { bg = colors.normal_bg, fg = '#ffd6b1', bold = true },
  FinderTitleIcon = { bg = colors.normal_bg, fg = '#89d957' },
  -- definition
  DefinitionBorder = { link = 'SagaBorder' },
  DefinitionNormal = { link = 'SagaBorder' },
  DefinitionSearch = { link = 'Search' },
  -- hover
  HoverNormal = { link = 'SagaBorder' },
  HoverBorder = { link = 'SagaBorder' },
  -- rename
  RenameBorder = { link = 'SagaBorder' },
  RenameNormal = { fg = '#f17866', bg = colors.normal_bg },
  RenameMatch = { link = 'Search' },
  -- diagnostic
  DiagnosticSource = { fg = 'gray' },
  DiagnosticNormal = { link = 'SagaBorder' },
  DiagnosticErrorBorder = { link = 'SagaBorder' },
  DiagnosticWarnBorder = { link = 'SagaBorder' },
  DiagnosticHintBorder = { link = 'SagaBorder' },
  DiagnosticInfoBorder = { link = 'SagaBorder' },
  -- Call Hierachry
  CallHierarchyNormal = { link = 'SagaBorder' },
  CallHierarchyBorder = { link = 'SagaBorder' },
  CallHierarchyIcon = { fg = '#CBA6F7' },
  CallHierarchyTitle = { fg = '#9c255e' },
  -- lightbulb
  LspSagaLightBulb = { link = 'DiagnosticSignHint' },
  -- shadow
  SagaShadow = { fg = 'black' },
  -- Outline
  OutlinePreviewBorder = { link = 'SagaBorder' },
  OutlinePreviewNormal = { link = 'SagaBorder' },
  OutlineDetail = { fg = '#73797e' },
}

local loaded = false

local function init_color()
  if not vim.tbl_isempty(ui.colors) then
    vim.tbl_extend('force', colors, ui.colors)
  end
end

local function init_highlight()
  if not loaded then
    init_color()
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
