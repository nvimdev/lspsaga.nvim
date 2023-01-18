local api = vim.api
local ui = require('lspsaga').config.ui

local resolved

local function get_colors()
  local colors = {
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
  if not resolved then
    for k, v in pairs(ui.colors) do
      colors[k] = v
    end
    resolved = function()
      return colors
    end
  end
  return resolved
end

local function hi_define()
  local colors = resolved()
  return {
    -- general
    TitleString = { bg = colors.title_bg, fg = colors.black, bold = true },
    TitleSymbol = { bg = colors.normal_bg, fg = colors.title_bg },
    TitleIcon = { bg = colors.title_bg, fg = colors.red },
    SagaBorder = { bg = colors.normal_bg },
    SagaExpand = { fg = colors.red },
    SagaCollapse = { fg = colors.red },
    SagaBeacon = { bg = colors.magenta },
    -- code action
    ActionPreviewNormal = { link = 'SagaBorder' },
    ActionPreviewBorder = { link = 'SagaBorder' },
    ActionPreviewTitle = { fg = colors.purple, bg = colors.normal_bg },
    CodeActionNormal = { link = 'SagaBorder' },
    CodeActionBorder = { link = 'SagaBorder' },
    CodeActionText = { fg = colors.yellow },
    CodeActionConceal = { fg = colors.green },
    -- finder
    FinderSelection = { fg = colors.cyan, bold = true },
    FinderFileName = { fg = colors.white },
    FinderCount = { link = 'Title' },
    FinderIcon = { fg = colors.cyan },
    FinderType = { fg = colors.purple },
    --finder spinner
    FinderSpinnerTitle = { fg = colors.magenta, bold = true },
    FinderSpinner = { fg = colors.magenta, bold = true },
    FinderPreviewSearch = { link = 'Search' },
    FinderVirtText = { fg = colors.red },
    FinderNormal = { link = 'SagaBorder' },
    FinderBorder = { link = 'SagaBorder' },
    FinderPreviewBorder = { link = 'SagaBorder' },
    -- definition
    DefinitionBorder = { link = 'SagaBorder' },
    DefinitionNormal = { link = 'SagaBorder' },
    DefinitionSearch = { link = 'Search' },
    -- hover
    HoverNormal = { link = 'SagaBorder' },
    HoverBorder = { link = 'SagaBorder' },
    -- rename
    RenameBorder = { link = 'SagaBorder' },
    RenameNormal = { fg = colors.orange, bg = colors.normal_bg },
    RenameMatch = { link = 'Search' },
    -- diagnostic
    DiagnosticSource = { fg = 'gray' },
    DiagnosticNormal = { link = 'SagaBorder' },
    DiagnosticBorder = { link = 'SagaBorder' },
    DiagnosticErrorBorder = { link = 'SagaBorder' },
    DiagnosticWarnBorder = { link = 'SagaBorder' },
    DiagnosticHintBorder = { link = 'SagaBorder' },
    DiagnosticInfoBorder = { link = 'SagaBorder' },
    DiagnosticPos = { fg = colors.gray },
    DiagnosticWord = { fg = colors.fg },
    -- Call Hierachry
    CallHierarchyNormal = { link = 'SagaBorder' },
    CallHierarchyBorder = { link = 'SagaBorder' },
    CallHierarchyIcon = { fg = colors.purple },
    CallHierarchyTitle = { fg = colors.red },
    -- lightbulb
    LspSagaLightBulb = { link = 'DiagnosticSignHint' },
    -- shadow
    SagaShadow = { bg = colors.black },
    -- Outline
    OutlineIndent = { fg = colors.magenta },
    OutlinePreviewBorder = { link = 'SagaBorder' },
    OutlinePreviewNormal = { link = 'SagaBorder' },
    -- Float term
    TerminalBorder = { link = 'SagaBorder' },
    TerminalNormal = { link = 'SagaBorder' },
  }
end

local function get_kind(colors)
  colors = colors or resolved()
  return require('lspsaga.lspkind').get_kind(colors)()
end

local function gen_symbol_winbar_hi()
  local prefix = 'LspSagaWinbar'
  local winbar_sep = 'LspSagaWinbarSep'
  local colors = resolved()
  local kind = get_kind(colors)

  for _, v in pairs(kind or {}) do
    api.nvim_set_hl(0, prefix .. v[1], { fg = v[3] })
  end
  api.nvim_set_hl(0, winbar_sep, { fg = colors.red, default = true })
  api.nvim_set_hl(0, prefix .. 'File', { fg = colors.white, bold = true, default = true })
  api.nvim_set_hl(0, prefix .. 'Word', { fg = colors.white, default = true })
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
  get_colors()
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
