```
                                 __
                                / /________  _________ _____ _____ _
                               / / ___/ __ \/ ___/ __ `/ __ `/ __ `/
                              / (__  ) /_/ (__  ) /_/ / /_/ / /_/ /
                             /_/____/ .___/____/\__,_/\__, /\__,_/
                                   /_/               /____/

                          ⚡ designed for convenience and efficiency ⚡
```

A light-weight lsp plugin based on neovim built-in lsp with highly a performant UI.

1. [Install](#install)
   - [Vim Plug](#vim-plug)
   - [Packer](#packer)
2. [Configuration](#configuration)
3. [Mappings](#mappings)
4. [Customize Appearance](#customize-appearance)
5. [Showcase](#showcase)
6. [Donate](#donate)
7. [License](#license)

## Install

### Vim Plug

```vim
Plug 'neovim/nvim-lspconfig'
Plug 'glepnir/lspsaga.nvim', { 'branch': 'main' }
```

### Packer

```lua
use({
    "glepnir/lspsaga.nvim",
    branch = "main",
    config = function()
        local saga = require("lspsaga")

        saga.init_lsp_saga({
            -- your configuration
        })
    end,
})
```

## Configuration

Lspsaga support use command `Lspsaga` with completion or use lua function

```lua
local saga = require 'lspsaga'

-- change the lsp symbol kind
local kind = require('lspsaga.lspkind')
kind[type_number][2] = icon -- see lua/lspsaga/lspkind.lua

-- use default config
saga.init_lsp_saga()

-- use custom config
saga.init_lsp_saga({
    -- "single" | "double" | "rounded" | "bold" | "plus"
    border_style = "single",
    -- Error, Warn, Info, Hint
    -- use emoji like
    -- { "🙀", "😿", "😾", "😺" }
    -- or
    -- { "😡", "😥", "😤", "😐" }
    -- and diagnostic_header can be a function type
    -- must return a string and when diagnostic_header
    -- is function type it will have a param `entry`
    -- entry is a table type has these filed
    -- { bufnr, code, col, end_col, end_lnum, lnum, message, severity, source }
    diagnostic_header = { " ", " ", " ", "ﴞ " },
    -- show diagnostic source
    show_diagnostic_source = true,
    -- add bracket or something with diagnostic source, just have 2 elements
    diagnostic_source_bracket = {},
    -- use emoji lightbulb in default
    code_action_icon = "💡",
    -- if true can press number to execute the codeaction in codeaction window
    code_action_num_shortcut = true,
    -- same as nvim-lightbulb but async
    code_action_lightbulb = {
        enable = true,
        sign = true,
        sign_priority = 20,
        virtual_text = true,
    },
    -- separator in finder
    finder_separator = "  ",
    -- preview lines of lsp_finder and definition preview
    max_preview_lines = 10,
    finder_action_keys = {
        open = "o",
        vsplit = "s",
        split = "i",
        tabe = "t",
        quit = "q",
        scroll_down = "<C-f>",
        scroll_up = "<C-b>", -- quit can be a table
    },
    code_action_keys = {
        quit = "q",
        exec = "<CR>",
    },
    rename_action_quit = "<C-c>",
    definition_preview_icon = "  ",
    -- if you don't use nvim-lspconfig you must pass your server name and
    -- the related filetypes into this table
    -- like server_filetype_map = { metals = { "sbt", "scala" } }
    server_filetype_map = {},
})
```

## Mappings

Plugin does not provide mappings by default. However, you can bind mappings yourself. You can find examples in the [showcase](#showcase) section.

## Customize Appearance

Colors can be simply changed by overwriting the default highlights groups LspSaga is using.

```vim
highlight link LspSagaFinderSelection Search
" or
highlight link LspSagaFinderSelection guifg='#ff0000' guibg='#00ff00' gui='bold'
```

The available highlight groups you can find in [here](./plugin/lspsaga.lua).

## Showcase

<details>
<summary>Async lsp finder</summary>

**Vimscript**

```vim
" lsp finder to find the cursor word definition and reference
nnoremap <silent> gh <cmd>lua require('lspsaga.finder').lsp_finder()<CR>
" or use command LspSagaFinder
nnoremap <silent> gh <cmd>Lspsaga lsp_finder<CR>
```

**Lua**

```lua
-- lsp finder to find the cursor word definition and reference
vim.keymap.set("n", "gh", require("lspsaga.finder").lsp_finder, { silent = true })
-- or use command LspSagaFinder
vim.keymap.set("n", "gh", "<cmd>Lspsaga lsp_finder<CR>", { silent = true })
```

<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/175801499-4598dbc9-50c1-4053-b671-303df4e94a19.gif" />
</div>

</details>

<details>
<summary>Code action</summary>

**Vimscript**

```vim
" code action
nnoremap <silent> <leader>ca <cmd>lua require('lspsaga.codeaction').code_action()<CR>
vnoremap <silent> <leader>ca <cmd><C-U>lua require('lspsaga.codeaction').range_code_action()<CR>
" or use command
nnoremap <silent> <leader>ca <cmd>Lspsaga code_action<CR>
vnoremap <silent> <leader>ca <cmd><C-U>Lspsaga range_code_action<CR>
```

**Lua**

```lua
local action = require("lspsaga.codeaction")

-- code action
vim.keymap.set("n", "<leader>ca", action.code_action, { silent = true })
vim.keymap.set("v", "<leader>ca", function()
    vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<C-U>", true, false, true))
    action.range_code_action()
end, { silent = true })
-- or use command
vim.keymap.set("n", "<leader>ca", "<cmd>Lspsaga code_action<CR>", { silent = true })
vim.keymap.set("v", "<leader>ca", "<cmd><C-U>Lspsaga range_code_action<CR>", { silent = true })
```

<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/175305503-180e6b39-d162-4ef2-aa2b-9ffe309948e6.gif"/>
</div>

</details>

<details>
<summary>Async lightbulb</summary>

<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/175752848-cef8218a-f8e4-42c2-96bd-06bb07cd42c6.gif"/>
</div>

</details>

<details id="hover-doc">
<summary>Hover doc</summary>

**Vimscript**

```vim
" show hover doc
nnoremap <silent> K <cmd>lua require('lspsaga.hover').render_hover_doc()<CR>
" or use command
nnoremap <silent> K <cmd>Lspsaga hover_doc<CR>

" scroll down hover doc or scroll in definition preview
nnoremap <silent> <C-f> <cmd>lua require('lspsaga.action').smart_scroll_with_saga(1)<CR>
" scroll up hover doc
nnoremap <silent> <C-b> <cmd>lua require('lspsaga.action').smart_scroll_with_saga(-1)<CR>
```

**Lua**

```lua
-- show hover doc
vim.keymap.set("n", "K", require("lspsaga.hover").render_hover_doc, { silent = true })
-- or use command
vim.keymap.set("n", "K", "<cmd>Lspsaga hover_doc<CR>", { silent = true })

local action = require("lspsaga.action")
-- scroll down hover doc or scroll in definition preview
vim.keymap.set("n", "<C-f>", function()
    action.smart_scroll_with_saga(1)
end, { silent = true })
-- scroll up hover doc
vim.keymap.set("n", "<C-b>", function()
    action.smart_scroll_with_saga(-1)
end, { silent = true })
```

<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/175306592-f0540e35-561f-418c-a41e-7df167ba9b86.gif"/>
</div>

</details>

<details>
<summary>Signature help</summary>

You also can use `smart_scroll_with_saga` (see [hover doc](#hover-doc)) to scroll in signature help win.

**Vimscript**

```vim
" show signature help
nnoremap <silent> gs <cmd>lua require('lspsaga.signaturehelp').signature_help()<CR>
" or command
nnoremap <silent> gs <cmd>Lspsaga signature_help<CR>
```

**Lua**

```lua
-- show signature help
vim.keymap.set("n", "gs", require("lspsaga.signaturehelp").signature_help, { silent = true })
-- or command
vim.keymap.set("n", "gs", "<Cmd>Lspsaga signature_help<CR>", { silent = true })
```

<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/175306809-755c4624-a5d2-4c11-8b29-f41914f22411.gif"/>
</div>

</details>

<details>
<summary>Rename with preview and select</summary>

**Vimscript**

```vim
" rename
nnoremap <silent> gr <cmd>lua require('lspsaga.rename').lsp_rename()<CR>
" or command
nnoremap <silent> gr <cmd>Lspsaga rename<CR>
" close rename win use <C-c> in insert mode or `q` in normal mode or `:q`
```

**Lua**

```lua
-- rename
vim.keymap.set("n", "gr", require("lspsaga.rename").lsp_rename, { silent = true })
-- or command
vim.keymap.set("n", "gr", "<cmd>Lspsaga rename<CR>", { silent = true })
-- close rename win use <C-c> in insert mode or `q` in normal mode or `:q`
```

<div align="center">
<img
src="https://user-images.githubusercontent.com/41671631/175300080-6e72001c-78dd-4d86-8139-bba38befee15.gif" />
</div>

</details>

<details>
<summary>Preview definition</summary>

You also can use `smart_scroll_with_saga` (see [hover doc](#hover-doc)) to scroll in preview definition win.

**Vimscript**

```vim
" preview definition
nnoremap <silent> gd <cmd>lua require('lspsaga.definition').preview_definition()<CR>
" or use command
nnoremap <silent> gd <cmd>Lspsaga preview_definition<CR>
```

**Lua**

```lua
-- preview definition
vim.keymap.set("n", "gd", require("lspsaga.definition").preview_definition, { silent = true })
-- or use command
vim.keymap.set("n", "gd", "<cmd>Lspsaga preview_definition<CR>", { silent = true })
```

<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/105657900-5b387f00-5f00-11eb-8b39-4d3b1433cb75.gif"/>
</div>

</details>

<details>
<summary>Jump and show diagnostics</summary>

**Vimscript**

```vim
nnoremap <silent> <leader>cd <cmd>lua require('lspsaga.diagnostic').show_line_diagnostics()<CR>

nnoremap <silent> <leader>cd <Cmd>Lspsaga show_line_diagnostics<CR>
" jump diagnostic
nnoremap <silent> [e <cmd>lua require('lspsaga.diagnostic').goto_prev()<CR>
nnoremap <silent> ]e <cmd>lua require('lspsaga.diagnostic').goto_next()<CR>
" or use command
nnoremap <silent> [e <cmd>Lspsaga diagnostic_jump_next<CR>
nnoremap <silent> ]e <cmd>Lspsaga diagnostic_jump_prev<CR>
```

**Lua**

```lua
vim.keymap.set("n", "<leader>cd", require("lspsaga.diagnostic").show_line_diagnostics, { silent = true })
vim.keymap.set("n", "<leader>cd", "<cmd>Lspsaga show_line_diagnostics<CR>", { silent = true })

-- jump diagnostic
vim.keymap.set("n", "[e", require("lspsaga.diagnostic").goto_prev, { silent = true })
vim.keymap.set("n", "]e", require("lspsaga.diagnostic").goto_next, { silent = true })
-- or use command
vim.keymap.set("n", "[e", "<cmd>Lspsaga diagnostic_jump_next<CR>", { silent = true })
vim.keymap.set("n", "]e", "<cmd>Lspsaga diagnostic_jump_prev<CR>", { silent = true })
```

<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/175304950-f4620c7a-9080-4496-b7cb-2a077ab9ecc0.gif"/>
</div>

</details>

<details>
<summary>Float terminal</summary>

**Vimscript**

```vim
" float terminal also you can pass the cli command in open_float_terminal function
nnoremap <silent> <A-d> <cmd>lua require('lspsaga.floaterm').open_float_terminal()<CR>
tnoremap <silent> <A-d> <C-\><C-n><cmd>lua require('lspsaga.floaterm').close_float_terminal()<CR>

" or use command
nnoremap <silent> <A-d> <cmd>Lspsaga open_floaterm<CR>
tnoremap <silent> <A-d> <C-\><C-n><cmd>Lspsaga close_floaterm<CR>
```

**Lua**

```lua
-- float terminal also you can pass the cli command in open_float_terminal function
local term = require("lspsaga.floaterm")

-- float terminal also you can pass the cli command in open_float_terminal function
vim.keymap.set("n", "<A-d>", term.open_float_terminal, { silent = true })
vim.keymap.set("t", "<A-d>", function()
    vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, false, true))
    term.close_float_terminal()
end, { silent = true })

-- or use command
vim.keymap.set("n", "<A-d>", "<cmd>Lspsaga open_floaterm<CR>", { silent = true })
vim.keymap.set("t", "<A-d>", "<C-\\><C-n><cmd>Lspsaga close_floaterm<CR>", { silent = true })
```

<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/105658287-2c6ed880-5f01-11eb-8af6-daa6fd23576c.gif"/>
</div>

</details>

## Donate

[![](https://img.shields.io/badge/PayPal-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/bobbyhub)

If you'd like to support my work financially, buy me a drink through [paypal](https://paypal.me/bobbyhub).

# License

Licensed under the [MIT](./LICENSE) license.
