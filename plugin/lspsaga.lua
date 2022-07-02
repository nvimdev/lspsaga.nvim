local api = vim.api
local highlights = {
  -- code action
  LspSagaCodeActionTitle = {fg='#da8548',bold = true},
  LspSagaCodeActionBorder= {fg = '#CBA6F7'},
  LspSagaCodeActionTrunCateLine = { link = 'LspSagaCodeActionBorder'},
  LspSagaCodeActionContent = {fg = '#98be65',bold = true},
  -- finder
  LspSagaLspFinderBorder = {fg = '#51afef'},
  LspSagaAutoPreview = { fg= '#ecbe7b'},
  LspSagaFinderSelection = { fg = '#89d957',bold = true},
  TargetFileName = {link = 'Comment'},
  DefinitionCount = {link = 'Title'},
  ReferencesCount = {link = 'Title'},
  TargetWord = {fg = '#1abc9c' ,bold =true},
  FinderSeparator = {fg='#36d0e0'},
  -- definition
  LspSagaDefPreviewBorder = { fg = '#b3deef'},
  DefinitionPreviewTitle = { link = 'Title'},
  -- hover
  LspSagaHoverBorder = { fg = '#f7bb3b'},
  LspSagaHoverTrunCateLine = { link = 'LspSagaHoverBorder'},
  -- rename
  LspSagaRenameBorder = { fg = '#3bb6c4'},
  LspSagaRenameMatch = { link = 'Search'},
  -- diagnostic
  LspSagaDiagnosticSource = {fg = '#FF8700'},
  LspSagaDiagnosticError = { link = 'DiagnosticError'},
  LspSagaDiagnosticWarn  = { link = 'DiagnosticWarn'},
  LspSagaDiagnosticInfo  = { link = 'DiagnosticInfo'},
  LspSagaDiagnosticHint  = { link = 'DiagnosticHint'},
  LspSagaErrorTrunCateLine = { link = 'DiagnosticError'},
  LspSagaWarnTrunCateLine = { link = 'DiagnosticWarn'},
  LspSagaInfoTrunCateLine = { link = 'DiagnosticInfo'},
  LspSagaHintTrunCateLine = { link = 'DiagnosticHint'},
  LspSagaDiagnosticBorder = {fg = '#CBA6F7'},
  LspSagaDiagnosticHeader = { fg= '#afd700'},
  LspSagaDiagnosticTruncateLine = {link = 'LspSagaDiagnosticBorder'},
  -- signture help
  LspSagaSignatureHelpBorder = { fg = "#98be65"},
  LspSagaShTrunCateLine = { link = 'LspSagaSignatureHelpBorder'},
  -- lightbulb
  LspSagaLightBulb = { link = 'DiagnosticSignHint'},
  -- shadow
  SagaShadow = {fg = 'black'},
  -- float
  LspSagaBorderTitle = {link = 'String'}

}

for group,conf in pairs(highlights) do
  api.nvim_set_hl(0,group,conf)
end

api.nvim_create_user_command('Lspsaga',function(args)
  require('lspsaga.command').load_command(unpack(args.fargs))
end,{
    nargs = "+",
    complete = function (arg)
      local list = require('lspsaga.command').command_list()
      return vim.tbl_filter(function (s)
        return string.match(s, "^" .. arg)
      end,list)
    end,
  })
