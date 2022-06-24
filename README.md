# lspsaga.nvim

A light-weight lsp plugin based on neovim built-in lsp with highly a performant UI.

## Install

* vim-plug
```vim
Plug 'neovim/nvim-lspconfig'
Plug 'glepnir/lspsaga.nvim', { 'branch': 'main' }
```

## Usage

Lspsaga support use command `Lspsaga` with completion or use lua function

```lua

local saga = require 'lspsaga'

-- Error,Warn,Info,Hint
-- use emoji 
-- like {'🙀','😿','😾','😺'}
-- {'😡','😥','😤','😐'}
diagnostic_header_icon = {' ',' ',' ','ﴞ '},
-- show diagnostic source
show_diagnostic_source = true,
-- add bracket or something with diagnostic source,just have 2 elements
diagnostic_source_bracket = {},
-- use emoji lightbulb in default
code_action_icon = '💡',
-- if true can press number to execute the codeaction in codeaction window
code_action_num_shortcut = true,
-- same as nvim-lightbulb but async
code_action_lightbulb = {
  enable = true,
  sign = true,
  sign_priority = 20,
  virtual_text = true,
},
finder_definition_icon = '  ',
finder_reference_icon = '  ',
-- preview lines of lsp_finder and definition preview
max_preview_lines = 10,
finder_action_keys = {
  open = 'o', vsplit = 's',split = 'i',quit = 'q',scroll_down = '<C-f>', scroll_up = '<C-b>' -- quit can be a table
},
code_action_keys = {
  quit = 'q',exec = '<CR>'
},
rename_action_keys = {
  quit = '<C-c>',exec = '<CR>'  -- quit can be a table
},
definition_preview_icon = '  '
-- "single" "double" "rounded" "bold" "plus"
border_style = "single"
-- if you don't use nvim-lspconfig you must pass your server name and
-- the related filetypes into this table
-- like server_filetype_map = {metals = {'sbt', 'scala'}}
server_filetype_map = {}

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
src="https://user-images.githubusercontent.com/41671631/175307158-97f2a269-eeea-48e5-8b1e-d70123c30d77.gif" />
</div>

### Code Action Support use number to execute

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
src="https://user-images.githubusercontent.com/41671631/175305503-180e6b39-d162-4ef2-aa2b-9ffe309948e6.gif"/>
</div>

- async lightbulb

<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/175305874-e95508e1-ecb9-4e5a-a664-85dfd3577ef1.gif"/>
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
src="https://user-images.githubusercontent.com/41671631/175306592-f0540e35-561f-418c-a41e-7df167ba9b86.gif"/>
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
src="https://user-images.githubusercontent.com/41671631/175306809-755c4624-a5d2-4c11-8b29-f41914f22411.gif"/>
</div>

### Rename with Preview and Select

```lua
-- rename
nnoremap <silent>gr <cmd>lua require('lspsaga.rename').lsp_rename()<CR>
-- or command
nnoremap <silent>gr :Lspsaga rename<CR>
-- close rename win use <C-c> in insert mode or `q` in normal mode or `:q`
```
<div align="center">
<img
src="https://user-images.githubusercontent.com/41671631/175300080-6e72001c-78dd-4d86-8139-bba38befee15.gif" />
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
-- jump diagnostic
nnoremap <silent> [e <cmd>lua require'lspsaga.diagnostic'.lsp_jump_diagnostic_prev()<CR>
nnoremap <silent> ]e <cmd>lua require'lspsaga.diagnostic'.lsp_jump_diagnostic_next()<CR>
-- or use command
nnoremap <silent> [e :Lspsaga diagnostic_jump_next<CR>
nnoremap <silent> ]e :Lspsaga diagnostic_jump_prev<CR>
```
<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/175304950-f4620c7a-9080-4496-b7cb-2a077ab9ecc0.gif"/>
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

The available highlight groups you can find in [here](./plugin/lspsaga.lua)


## Donate
[![](https://img.shields.io/badge/PayPal-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/bobbyhub)

If you'd like to support my work financially, buy me a drink through [paypal](https://paypal.me/bobbyhub)

# License

MIT
