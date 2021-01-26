# lspsaga.nvim

A light-weight lsp plugin based on neovim built-in lsp with highly performance UI.

## Install

* vim-plug
```vim
Plug 'neovim/nvim-lspconfig'
Plug 'glepnir/lspsaga.nvim'
```

## Usage

```lua

local saga = require 'lspsaga'

-- add your config value here
-- default value
-- use_saga_diagnostic_handler = 1 // disable the lspsaga diagnostic handler
-- use_saga_diagnostic_sign = 1 // disable the lspsaga diagnostic sign
-- error_sign = '',
-- warn_sign = '',
-- hint_sign = '',
-- infor_sign = '',
-- code_action_icon = ' ',
-- finder_definition_icon = '  ',
-- finder_reference_icon = '  ',
-- definition_preview_icon = '  '
-- 1: thin border | 2: rounded border | 3: thick border
-- border_style = 1

local opts = {
  error_sign = 'xxx'
}

saga.init_lsp_saga(opts)
```

### Lsp Finder

```lua
-- lsp provider to find the currsor word definition and reference
nnoremap <silent> gh <cmd>lua require'lspsaga.provider'.lsp_finder()<CR>
```
<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/105656835-11e73000-5efe-11eb-868f-54c99a770dc8.gif" width=500 height=500/>
</div>

### Code Action

```lua
-- code action
nnoremap <silent><leader>ca <cmd>lua require('lspsaga.codeaction').code_action()<CR>
```
<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/105657414-490a1100-5eff-11eb-897d-587ac1375d4e.gif" width=500 height=500/>
</div>

### Hover Doc

```lua
-- show hover doc
nnoremap <silent> K <cmd>lua vim.lsp.buf.hover()<CR>
```
<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/105657800-29bfb380-5f00-11eb-85e7-8d6735dd5d58.gif" width=500 height=500/>
</div>

### Preview Definition

```lua
-- preview definition
nnoremap <silent> gd <cmd>lua require'lspsaga.provider'.preview_definition()<CR>
```
<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/105657900-5b387f00-5f00-11eb-8b39-4d3b1433cb75.gif" width=500 height=500/>
</div>

### Jump Diagnostic

```lua
-- jump diagnostic
nnoremap <silent> [e <cmd>lua require'lspsaga.diagnostic'.lsp_jump_diagnostic_prev()<CR>
nnoremap <silent> ]e <cmd>lua require'lspsaga.diagnostic'.lsp_jump_diagnostic_next()<CR>
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
```
<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/105658287-2c6ed880-5f01-11eb-8af6-daa6fd23576c.gif" width=500 height=500/>
</div>

