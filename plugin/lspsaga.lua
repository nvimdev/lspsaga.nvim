local api = vim.api
local highlights = {
  LspSagaTrunCateLine = {fg='black'},
  -- code action
  LspSagaCodeActionTitle = {fg='#da8548',bold = true},
  LspSagaCodeActionBorder= {fg = '#98be65'},
  LspSagaCodeActionContent = {fg = '#98be65',bold = true},
  -- finder
  LspSagaLspFinderBorder = {fg = '#51afef'},
  LspSagaAutoPreview = { fg= '#ecbe7b'},
  LspSagaFinderSelection = { fg = '#89d957',bold = true},
  -- definition
  LspSagaDefPreviewBorder = { fg = '#b3deef'},
  -- hover
  LspSagaHoverBorder = { fg = '#80a0c2'},
  -- rename
  LspSagaRenameBorder = { fg = '#3bb6c4'},
  LspSagaRenamePromptPrefix = {fg= '#98be65'},
  -- diagnostic
  LspSagaDiagnosticError = { link = 'DiagnosticError'},
  LspSagaDiagnosticWarn  = { link = 'DiagnosticWarn'},
  LspSagaDiagnosticInfo  = { link = 'DiagnosticInfo'},
  LspSagaDiagnosticHint  = { link = 'DiagnosticHint'},
}

for group,conf in pairs(highlights) do
  api.nvim_set_hl(0,group,conf)
end
