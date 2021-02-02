local M = {}
local api = vim.api

function M.add_highlight()
  api.nvim_command("hi LspFloatWinBorder guifg=black")
  api.nvim_command("hi LspSagaBorderTitle guifg=orange gui=bold")
  api.nvim_command("hi def link TargetWord Error")
  api.nvim_command("hi def link ReferencesCount Title")
  api.nvim_command("hi def link DefinitionCount Title")
  api.nvim_command("hi def link TargetFileName  Comment")
  api.nvim_command("hi def link DefinitionIcon Special")
  api.nvim_command("hi def link ReferencesIcon Special")
  api.nvim_command("hi ProviderTruncateLine guifg=black")
  api.nvim_command('hi SagaShadow guibg=#000000')

  -- diagnostic
  api.nvim_command("hi DiagnosticTruncateLine guifg=#6699cc gui=bold")
  api.nvim_command("hi def link DiagnosticError Error")
  api.nvim_command("hi def link DiagnosticWarning WarningMsg")
  api.nvim_command("hi DiagnosticInformation guifg=#6699cc gui=bold")
  api.nvim_command("hi DiagnosticHint guifg=#56b6c2 gui=bold")

  api.nvim_command("hi def link DefinitionPreviewTitle Title")

  api.nvim_command("hi LspDiagErrorBorder guifg=#EC5f67")
  api.nvim_command("hi LspDiagWarnBorder guifg=#d8a657")
  api.nvim_command("hi LspDiagInforBorder guifg=#6699cc")
  api.nvim_command("hi LspDiagHintBorder guifg=#56b6c2")

  api.nvim_command("hi LspSagaShTruncateLine guifg=black")
  api.nvim_command("hi LspSagaDocTruncateLine guifg=black")
  api.nvim_command("hi LineDiagTuncateLine guifg=#ff6c6b")
  api.nvim_command("hi LspSagaCodeActionTitle guifg=#da8548 gui=bold")
  api.nvim_command("hi LspSagaCodeActionTruncateLine guifg=black")

  api.nvim_command("hi LspSagaCodeActionContent guifg=#98be65 gui=bold")

  api.nvim_command("hi LspSagaRenamePromptPrefix guifg=#98be65")

  api.nvim_command('hi LspSagaRenameBorder guifg=#3bb6c4')
  api.nvim_command('hi LspSagaHoverBorder guifg=#80A0C2')
  api.nvim_command('hi LspSagaSignatureHelpBorder guifg=#98be65')
  api.nvim_command('hi LspSagaLspFinderBorder guifg=#51afef')
  api.nvim_command('hi LspSagaCodeActionBorder guifg=#b3deef')
  api.nvim_command('hi LspSagaAutoPreview guifg=#ECBE7B')
  api.nvim_command('hi LspSagaDefPreviewBorder guifg=#b3deef')
  api.nvim_command('hi LspLinesDiagBorder guifg=#ff6c6b')
end

return M

