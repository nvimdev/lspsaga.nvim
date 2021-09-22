# lspsaga.nvim

A light-weight lsp plugin based on neovim built-in lsp with highly a performant UI.

## Install

* vim-plug
```vim
Plug 'neovim/nvim-lspconfig'
Plug 'tami5/lspsaga.nvim'
```

## Usage

Lspsaga support use command `Lspsaga` with completion or use lua function

```lua

local saga = require 'lspsaga'

-- add your config value here
-- default value
-- use_saga_diagnostic_sign = true
-- error_sign = '',
-- warn_sign = '',
-- hint_sign = '',
-- infor_sign = '',
-- dianostic_header_icon = '   ',
-- code_action_icon = ' ',
-- code_action_prompt = {
--   enable = true,
--   sign = true,
--   sign_priority = 20,
--   virtual_text = true,
-- },
-- finder_definition_icon = '  ',
-- finder_reference_icon = '  ',
-- max_preview_lines = 10, -- preview lines of lsp_finder and definition preview
-- finder_action_keys = {
--   open = 'o', vsplit = 's',split = 'i',quit = 'q',scroll_down = '<C-f>', scroll_up = '<C-b>' -- quit can be a table
-- },
-- code_action_keys = {
--   quit = 'q',exec = '<CR>'
-- },
-- rename_action_keys = {
--   quit = '<C-c>',exec = '<CR>'  -- quit can be a table
-- },
-- definition_preview_icon = '  '
-- "single" "double" "round" "plus"
-- border_style = "single"
-- rename_prompt_prefix = '➤',
-- if you don't use nvim-lspconfig you must pass your server name and
-- the related filetypes into this table
-- like server_filetype_map = {metals = {'sbt', 'scala'}}
-- server_filetype_map = {}

saga.init_lsp_saga {
  your custom option here
}

or --use default config
saga.init_lsp_saga()
```

### Async Lsp Finder

```lua
-- lsp provider to find the cursor word definition and reference
nnoremap <silent> gh <cmd>lua require'lspsaga.provider'.lsp_finder()<CR>
-- or use command LspSagaFinder
nnoremap <silent> gh :Lspsaga lsp_finder<CR>
```
<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/107140076-ae77ec00-695a-11eb-8329-0b9d8361bfeb.gif" width=500 height=500/>
</div>

### Code Action

```lua
-- code action
nnoremap <silent><leader>ca <cmd>lua require('lspsaga.codeaction').code_action()<CR>
vnoremap <silent><leader>ca :<C-U>lua require('lspsaga.codeaction').range_code_action()<CR>
-- or use command
nnoremap <silent><leader>ca :Lspsaga code_action<CR>
vnoremap <silent><leader>ca :<C-U>Lspsaga range_code_action<CR>
```
<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/105657414-490a1100-5eff-11eb-897d-587ac1375d4e.gif" width=500 height=500/>
</div>

- code action auto prompt

<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/110590664-0e102400-81b3-11eb-9b9d-a894537104bc.gif" width=500 height=500/>
</div>

### Hover Doc

```lua
-- show hover doc
nnoremap <silent> K <cmd>lua require('lspsaga.hover').render_hover_doc()<CR>
-- or use command
nnoremap <silent>K :Lspsaga hover_doc<CR>

-- scroll down hover doc or scroll in definition preview
nnoremap <silent> <C-f> <cmd>lua require('lspsaga.action').smart_scroll_with_saga(1)<CR>
-- scroll up hover doc
nnoremap <silent> <C-b> <cmd>lua require('lspsaga.action').smart_scroll_with_saga(-1)<CR>
```
<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/106566308-1dc09b00-656b-11eb-85e2-2ab5b23599c9.gif" width=500 height=500/>
</div>

### SignatureHelp

```lua
-- show signature help
nnoremap <silent> gs <cmd>lua require('lspsaga.signaturehelp').signature_help()<CR>
-- or command
nnoremap <silent> gs :Lspsaga signature_help<CR>

and you also can use smart_scroll_with_saga to scroll in signature help win
```
<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/105969051-c7fb7700-60c2-11eb-9c79-aef3e01d88b1.gif" width=500 height=500 />
</div>

### Rename

```lua
-- rename
nnoremap <silent>gr <cmd>lua require('lspsaga.rename').rename()<CR>
-- or command
nnoremap <silent>gr :Lspsaga rename<CR>
-- close rename win use <C-c> in insert mode or `q` in noremal mode or `:q`
```
<div align="center">
<img
src="https://user-images.githubusercontent.com/41671631/106115648-f6915480-618b-11eb-9818-003cfb15c8ac.gif" />
</div>

### Preview Definition

```lua
-- preview definition
nnoremap <silent> gd <cmd>lua require'lspsaga.provider'.preview_definition()<CR>
-- or use command
nnoremap <silent> gd :Lspsaga preview_definition<CR>

can use smart_scroll_with_saga to scroll
```
<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/105657900-5b387f00-5f00-11eb-8b39-4d3b1433cb75.gif" width=500 height=500/>
</div>

### Jump Diagnostic and Show Diagnostics

```lua
-- show
nnoremap <silent><leader>cd <cmd>lua
require'lspsaga.diagnostic'.show_line_diagnostics()<CR>

nnoremap <silent> <leader>cd :Lspsaga show_line_diagnostics<CR>
-- only show diagnostic if cursor is over the area
nnoremap <silent><leader>cc <cmd>lua
require'lspsaga.diagnostic'.show_cursor_diagnostics()<CR>

-- jump diagnostic
nnoremap <silent> [e <cmd>lua require'lspsaga.diagnostic'.lsp_jump_diagnostic_prev()<CR>
nnoremap <silent> ]e <cmd>lua require'lspsaga.diagnostic'.lsp_jump_diagnostic_next()<CR>
-- or use command
nnoremap <silent> [e :Lspsaga diagnostic_jump_next<CR>
nnoremap <silent> ]e :Lspsaga diagnostic_jump_prev<CR>
```
<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/102290042-21786e00-3f7b-11eb-8026-d467bc256ba8.gif" width=500 height=300/>
</div>

### Float Terminal

```lua
-- float terminal also you can pass the cli command in open_float_terminal function
nnoremap <silent> <A-d> <cmd>lua require('lspsaga.floaterm').open_float_terminal()<CR> -- or open_float_terminal('lazygit')<CR>
tnoremap <silent> <A-d> <C-\><C-n>:lua require('lspsaga.floaterm').close_float_terminal()<CR>
-- or use command
nnoremap <silent> <A-d> :Lspsaga open_floaterm<CR>
tnoremap <silent> <A-d> <C-\><C-n>:Lspsaga close_floaterm<CR>
```
<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/105658287-2c6ed880-5f01-11eb-8af6-daa6fd23576c.gif" width=500 height=500/>
</div>

## Customize Appearance

### Colors

Colors can be simply changed by overwriting the default highlights groups LspSaga is using.

```vim
highlight link LspSagaFinderSelection Search
" or
highlight link LspSagaFinderSelection guifg='#ff0000' guibg='#00ff00' gui='bold'
```

The available highlight groups are:

| Group Name               | Description                                                      |
| :----------------------- | :----------------------------------------------------------------|
| `LspSagaFinderSelection` | Currently active entry in the finder window that gets previewed. |
| `LspFloatWinNormal` | |
| `LspFloatWinBorder` | |
| `LspSagaBorderTitle` | |
| `TargetWord` | |
| `ReferencesCount` | |
| `DefinitionCount` | |
| `TargetFileName` | |
| `DefinitionIcon` | |
| `ReferencesIcon` | |
| `ProviderTruncateLine` | |
| `SagaShadow` | |
| `LspSagaFinderSelection` | |
| `DiagnosticTruncateLine` | |
| `DiagnosticError` | |
| `DiagnosticWarning` | |
| `DiagnosticInformation` | |
| `DiagnosticHint` | |
| `DefinitionPreviewTitle` | |
| `LspSagaShTruncateLine` | |
| `LspSagaDocTruncateLine` | |
| `LineDiagTuncateLine` | |
| `LspSagaCodeActionTitle` | |
| `LspSagaCodeActionTruncateLine` | |
| `LspSagaCodeActionContent` | |
| `LspSagaRenamePromptPrefix` | |
| `LspSagaRenameBorder` | |
| `LspSagaHoverBorder` | |
| `LspSagaSignatureHelpBorder` | |
| `LspSagaCodeActionBorder` | |
| `LspSagaAutoPreview` | |
| `LspSagaDefPreviewBorder` | |
| `LspLinesDiagBorder` | |

# License

MIT
