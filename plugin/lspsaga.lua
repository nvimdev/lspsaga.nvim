local api = vim.api
local highlights = {
  -- code action
  LspSagaCodeActionTitle = { fg = '#da8548', bold = true },
  LspSagaCodeActionBorder = { fg = '#CBA6F7' },
  LspSagaCodeActionTrunCateLine = { link = 'LspSagaCodeActionBorder' },
  LspSagaCodeActionContent = { fg = '#98be65', bold = true },
  -- finder
  LspSagaLspFinderBorder = { fg = '#51afef' },
  LspSagaAutoPreview = { fg = '#ecbe7b' },
  LspSagaFinderSelection = { fg = '#89d957', bold = true },
  TargetFileName = { link = 'Comment' },

  DefinitionsIcon = { fg = '#e3e346' },
  Definitions = { fg = '#CBA6F7', bold = true },
  ReferencesIcon = { fg = '#e3e346' },
  References = { fg = '#CBA6F7', bold = true },
  DefinitionCount = { link = 'Title' },
  ReferencesCount = { link = 'Title' },
  LSFinderBarFind = { fg = '#3af2dd', bg = '#a579b8', bold = true },
  LSFinderBarParam = { fg = '#3af2dd', bg = '#a579b8', bold = true },
  -- definition
  LspSagaDefPreviewBorder = { fg = '#b3deef' },
  DefinitionPreviewTitle = { link = 'Title' },
  -- hover
  LspSagaHoverBorder = { fg = '#f7bb3b' },
  LspSagaHoverTrunCateLine = { link = 'LspSagaHoverBorder' },
  -- rename
  LspSagaRenameBorder = { fg = '#3bb6c4' },
  LspSagaRenameMatch = { link = 'Search' },
  -- diagnostic
  LspSagaDiagnosticSource = { fg = '#FF8700' },
  LspSagaDiagnosticError = { link = 'DiagnosticError' },
  LspSagaDiagnosticWarn = { link = 'DiagnosticWarn' },
  LspSagaDiagnosticInfo = { link = 'DiagnosticInfo' },
  LspSagaDiagnosticHint = { link = 'DiagnosticHint' },
  LspSagaErrorTrunCateLine = { link = 'DiagnosticError' },
  LspSagaWarnTrunCateLine = { link = 'DiagnosticWarn' },
  LspSagaInfoTrunCateLine = { link = 'DiagnosticInfo' },
  LspSagaHintTrunCateLine = { link = 'DiagnosticHint' },
  LspSagaDiagnosticBorder = { fg = '#CBA6F7' },
  LspSagaDiagnosticHeader = { fg = '#afd700' },
  LspSagaDiagnosticTruncateLine = { link = 'LspSagaDiagnosticBorder' },
  -- signture help
  LspSagaSignatureHelpBorder = { fg = '#98be65' },
  LspSagaShTrunCateLine = { link = 'LspSagaSignatureHelpBorder' },
  -- lightbulb
  LspSagaLightBulb = { link = 'DiagnosticSignHint' },
  -- shadow
  SagaShadow = { fg = 'black' },
  -- float
  LspSagaBorderTitle = { link = 'String' },
  -- Outline
  LSOutlinePreviewBorder = { fg = '#52ad70' },
}

for group, conf in pairs(highlights) do
  api.nvim_set_hl(0, group, vim.tbl_extend('keep', conf, { default = true }))
end

api.nvim_create_user_command('Lspsaga', function(args)
  require('lspsaga.command').load_command(unpack(args.fargs))
end, {
  nargs = '+',
  complete = function(arg)
    local list = require('lspsaga.command').command_list()
    return vim.tbl_filter(function(s)
      return string.match(s, '^' .. arg)
    end, list)
  end,
})
