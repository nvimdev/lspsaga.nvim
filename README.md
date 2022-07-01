```
                                 __
                                / /________  _________ _____ _____ _
                               / / ___/ __ \/ ___/ __ `/ __ `/ __ `/
                              / (__  ) /_/ (__  ) /_/ / /_/ / /_/ /
                             /_/____/ .___/____/\__,_/\__, /\__,_/
                                   /_/               /____/

                          ⚡ designed for convenience and efficiency ⚡
```

A light-weight lsp plugin based on neovim's built-in lsp with a highly performant UI.

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
    -- when cursor in saga window you config these to move
    move_in_saga = { prev = '<C-p>',next = '<C-n>'},
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
    -- show symbols in winbar must nightly
    symbol_in_winbar = false,
    winbar_separator = '>',
    winbar_show_file = true,
    -- function type  return file string,
    -- by default saga use expand('%:t')
    -- you can custom file name include path or something
    winbar_file_format = function() your code here end,
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


**Lua**

```lua
-- lsp finder to find the cursor word definition and reference
vim.keymap.set("n", "gh", require("lspsaga.finder").lsp_finder, { silent = true,noremap = true })
-- or use command LspSagaFinder
vim.keymap.set("n", "gh", "<cmd>Lspsaga lsp_finder<CR>", { silent = true,noremap = true})
```

<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/175801499-4598dbc9-50c1-4053-b671-303df4e94a19.gif" />
</div>

</details>

<details>
<summary>Code action</summary>

**Lua**

```lua
local action = require("lspsaga.codeaction")

-- code action
vim.keymap.set("n", "<leader>ca", action.code_action, { silent = true,noremap = true })
vim.keymap.set("v", "<leader>ca", function()
    vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<C-U>", true, false, true))
    action.range_code_action()
end, { silent = true,noremap =true })
-- or use command
vim.keymap.set("n", "<leader>ca", "<cmd>Lspsaga code_action<CR>", { silent = true,noremap = true })
vim.keymap.set("v", "<leader>ca", "<cmd><C-U>Lspsaga range_code_action<CR>", { silent = true,noremap = true })
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

**Lua**

```lua
-- show signature help
vim.keymap.set("n", "gs", require("lspsaga.signaturehelp").signature_help, { silent = true,noremap = true})
-- or command
vim.keymap.set("n", "gs", "<Cmd>Lspsaga signature_help<CR>", { silent = true,noremap = true })
```

<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/175306809-755c4624-a5d2-4c11-8b29-f41914f22411.gif"/>
</div>

</details>

<details>
<summary>Rename with preview and select</summary>

**Lua**

```lua
-- rename
vim.keymap.set("n", "gr", require("lspsaga.rename").lsp_rename, { silent = true,noremap = true })
-- or command
vim.keymap.set("n", "gr", "<cmd>Lspsaga rename<CR>", { silent = true,noremap = true })
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

**Lua**

```lua
-- preview definition
vim.keymap.set("n", "gd", require("lspsaga.definition").preview_definition, { silent = true,noremap = true })
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

**Lua**

```lua
vim.keymap.set("n", "<leader>cd", require("lspsaga.diagnostic").show_line_diagnostics, { silent = true,noremap = true })
vim.keymap.set("n", "<leader>cd", "<cmd>Lspsaga show_line_diagnostics<CR>", { silent = true,noremap= true })

-- jump diagnostic
vim.keymap.set("n", "[e", require("lspsaga.diagnostic").goto_prev, { silent = true, noremap =true })
vim.keymap.set("n", "]e", require("lspsaga.diagnostic").goto_next, { silent = true, noremap =true })
-- or use command
vim.keymap.set("n", "[e", "<cmd>Lspsaga diagnostic_jump_next<CR>", { silent = true, noremap = true })
vim.keymap.set("n", "]e", "<cmd>Lspsaga diagnostic_jump_prev<CR>", { silent = true, noremap = true })
```

<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/175304950-f4620c7a-9080-4496-b7cb-2a077ab9ecc0.gif"/>
</div>

</details>

<details>
<summary>Fastest show symbols in winbar by use cache </summary>

<div align="center">
<img
src="https://user-images.githubusercontent.com/41671631/176679585-9485676b-ddea-44ca-bc88-b0eb04d450b1.gif" />
</div>

</details>

<details>
<summary>Float terminal</summary>

**Lua**

```lua
-- float terminal also you can pass the cli command in open_float_terminal function
local term = require("lspsaga.floaterm")

-- float terminal also you can pass the cli command in open_float_terminal function
vim.keymap.set("n", "<A-d>", function()
    term.open_float_terminal("custom_cli_command")
end, { silent = true,noremap = true })
vim.keymap.set("t", "<A-d>", function()
    vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, false, true))
    term.close_float_terminal()
end, { silent = true })

-- or use command
vim.keymap.set("n", "<A-d>", "<cmd>Lspsaga open_floaterm custom_cli_command<CR>", { silent = true,noremap = true })
vim.keymap.set("t", "<A-d>", "<C-\\><C-n><cmd>Lspsaga close_floaterm<CR>", { silent = true,noremap =true })
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
