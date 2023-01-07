local api = vim.api
local ui = require('lspsaga').config.ui
local hi = {}

local function get_colors()
  local colors = {
    fg = '#bbc2cf',
    red = '#e95678',
    orange = '#FF8700',
    yellow = '#f7bb3b',
    green = '#afd700',
    cyan = '#36d0e0',
    blue = '#61afef',
    violet = '#CBA6F7',
    teal = '#1abc9c',
  }
  for k, v in pairs(ui.colors) do
    colors[k] = v
  end
  return colors
end

local function hi_define(colors)
  return {
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
end

function hi:gen_symbol_winbar_hi(colors)
  local prefix = 'LspSagaWinbar'
  local winbar_sep = 'LspSagaWinbarSep'

  for _, v in pairs(self.kind) do
    api.nvim_set_hl(0, prefix .. v[1], { fg = v[3] })
  end
  api.nvim_set_hl(0, winbar_sep, { fg = colors.red })
  api.nvim_set_hl(0, prefix .. 'File', { fg = colors.fg, bold = true })
end

function hi:gen_outline_hi()
  for _, v in pairs(self.kind) do
    local hi_name = 'LSOutline' .. v[1]
    local ok, tbl = pcall(api.nvim_get_hl_by_name, hi_name, true)
    if not ok or not tbl.foreground then
      api.nvim_set_hl(0, hi_name, { fg = v[3] })
    end
  end
end

function hi:init_highlight()
  local colors = get_colors()
  for group, conf in pairs(hi_define(colors)) do
    api.nvim_set_hl(0, group, vim.tbl_extend('keep', conf, { default = true }))
  end

  self.kind = require('lspsaga.lspkind').get_kind(colors)
  self:gen_symbol_winbar_hi(colors)
  self:gen_outline_hi()
end

return hi
