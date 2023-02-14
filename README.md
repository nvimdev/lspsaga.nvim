```
                                 __
                                / /________  _________ _____ _____ _
                               / / ___/ __ \/ ___/ __ `/ __ `/ __ `/
                              / (__  ) /_/ (__  ) /_/ / /_/ / /_/ /
                             /_/____/ .___/____/\__,_/\__, /\__,_/
                                   /_/               /____/

                          ⚡ Designed for convenience and efficiency ⚡
```

A lightweight LSP plugin based on Neovim's built-in LSP with a highly performant UI.

[![](https://img.shields.io/badge/Element-0DBD8B?style=for-the-badge&logo=element&logoColor=white)](https://matrix.to/#/#lspsaga-nvim:matrix.org)

1. [Install](#install)
2. [Example Configuration](#example-configuration)
3. [Using Lspsaga](#using-lspsaga)
4. [Customizing Lspsaga's Appearance](#customizing-lspsagas-appearance)
5. [Backers](#backers)
6. [Donate](#donate)
7. [License](#license)

# Install

You can use plugin managers like `lazy.nvim` and `packer.nvim` to install `lspsaga` and lazy load `lspsaga` using the plugin manager's keyword for lazy loading (`lazy` for `lazy.nvim` and `opt` for `packer.nvim`).

- `cmd` - Load `lspsaga` only when a `lspsaga` command is called.
- `ft` - `lazy.nvim` and `packer.nvim` both provide lazy loading by filetype. This way, you can load `lspsaga` according to the filetypes that you use a LSP in.
- `event` - Only load `lspsaga` on an event like `BufRead` or `BufReadPost`. Do make sure that your LSP plugins, like [lsp-zero](https://github.com/VonHeikemen/lsp-zero.nvim) or [lsp-config](https://github.com/neovim/nvim-lspconfig), are loaded before loading `lspsaga`.
- `dependencies` - For `lazy.nvim` you can set `glepnir/lspsaga.nvim` as a dependency of `nvim-lspconfig` using the `dependencies` keyword and vice versa. For `packer.nvim` you should use `requires` as the keyword instead.
- `after` - For `packer.nvim` you can use `after` keyword to ensure `lspsaga` only loads after your LSP plugins have loaded. This is not necessary for `lazy.nvim`.

## [Lazy](https://github.com/folke/lazy.nvim)

```lua
require("lazy").setup({
    "glepnir/lspsaga.nvim",
    event = "BufRead",
    config = function()
        require("lspsaga").setup({})
    end,
    dependencies = {
      {"nvim-tree/nvim-web-devicons"},
      --Please make sure you install markdown and markdown_inline parser
      {"nvim-treesitter/nvim-treesitter"}
    }
}, opt)
```

## [Packer](https://github.com/wbthomason/packer.nvim)

```lua
use({
    "glepnir/lspsaga.nvim",
    branch = "main",
    config = function()
        require("lspsaga").setup({})
    end,
    requires = {
        {"nvim-tree/nvim-web-devicons"},
        --Please make sure you install markdown and markdown_inline parser
        {"nvim-treesitter/nvim-treesitter"}
    }
})
```

# Example Configuration

```lua
require("lazy").setup({
    "glepnir/lspsaga.nvim",
    event = "BufRead",
    config = function()
      require("lspsaga").setup({})
    end,
    dependencies = { {"nvim-tree/nvim-web-devicons"} }
})

local keymap = vim.keymap.set

-- LSP finder - Find the symbol's definition
-- If there is no definition, it will instead be hidden
-- When you use an action in finder like "open vsplit",
-- you can use <C-t> to jump back
keymap("n", "gh", "<cmd>Lspsaga lsp_finder<CR>")

-- Code action
keymap({"n","v"}, "<leader>ca", "<cmd>Lspsaga code_action<CR>")

-- Rename all occurrences of the hovered word for the entire file
keymap("n", "gr", "<cmd>Lspsaga rename<CR>")

-- Rename all occurrences of the hovered word for the selected files
keymap("n", "gr", "<cmd>Lspsaga rename ++project<CR>")

-- Peek definition
-- You can edit the file containing the definition in the floating window
-- It also supports open/vsplit/etc operations, do refer to "definition_action_keys"
-- It also supports tagstack
-- Use <C-t> to jump back
keymap("n", "gd", "<cmd>Lspsaga peek_definition<CR>")

-- Go to definition
keymap("n","gd", "<cmd>Lspsaga goto_definition<CR>")

-- Peek type definition
-- You can edit the file containing the type definition in the floating window
-- It also supports open/vsplit/etc operations, do refer to "definition_action_keys"
-- It also supports tagstack
-- Use <C-t> to jump back
keymap("n", "gt", "<cmd>Lspsaga peek_type_definition<CR>")

-- Go to type definition
keymap("n","gt", "<cmd>Lspsaga goto_type_definition<CR>")


-- Show line diagnostics
-- You can pass argument ++unfocus to
-- unfocus the show_line_diagnostics floating window
keymap("n", "<leader>sl", "<cmd>Lspsaga show_line_diagnostics<CR>")

-- Show cursor diagnostics
-- Like show_line_diagnostics, it supports passing the ++unfocus argument
keymap("n", "<leader>sc", "<cmd>Lspsaga show_cursor_diagnostics<CR>")

-- Show buffer diagnostics
keymap("n", "<leader>sb", "<cmd>Lspsaga show_buf_diagnostics<CR>")

-- Diagnostic jump
-- You can use <C-o> to jump back to your previous location
keymap("n", "[e", "<cmd>Lspsaga diagnostic_jump_prev<CR>")
keymap("n", "]e", "<cmd>Lspsaga diagnostic_jump_next<CR>")

-- Diagnostic jump with filters such as only jumping to an error
keymap("n", "[E", function()
  require("lspsaga.diagnostic"):goto_prev({ severity = vim.diagnostic.severity.ERROR })
end)
keymap("n", "]E", function()
  require("lspsaga.diagnostic"):goto_next({ severity = vim.diagnostic.severity.ERROR })
end)

-- Toggle outline
keymap("n","<leader>o", "<cmd>Lspsaga outline<CR>")

-- Hover Doc
-- If there is no hover doc,
-- there will be a notification stating that
-- there is no information available.
-- To disable it just use ":Lspsaga hover_doc ++quiet"
-- Pressing the key twice will enter the hover window
keymap("n", "K", "<cmd>Lspsaga hover_doc<CR>")

-- If you want to keep the hover window in the top right hand corner,
-- you can pass the ++keep argument
-- Note that if you use hover with ++keep, pressing this key again will
-- close the hover window. If you want to jump to the hover window
-- you should use the wincmd command "<C-w>w"
keymap("n", "K", "<cmd>Lspsaga hover_doc ++keep<CR>")

-- Call hierarchy
keymap("n", "<Leader>ci", "<cmd>Lspsaga incoming_calls<CR>")
keymap("n", "<Leader>co", "<cmd>Lspsaga outgoing_calls<CR>")

-- Floating terminal
keymap({"n", "t"}, "<A-d>", "<cmd>Lspsaga term_toggle<CR>")
```

## Using Lspsaga

**Note that the title in the floating window requires Neovim 0.9 or greater.**
**If you are using Neovim 0.8 you won't see a title.**

**If you are using Neovim 0.9 and want to disable the title, see [Customizing Lspsaga's Appearance](#customizing-lspsagas-appearance)

**You need not copy all of the options into the setup function. Just set the options that you've changed in the setup function and it will be extended with the default options!**

You can find the documentation for Lspsaga in Neovim by using `:h lspsaga`.

## Default options

```lua
  preview = {
    lines_above = 0,
    lines_below = 10,
  },
  scroll_preview = {
    scroll_down = "<C-f>",
    scroll_up = "<C-b>",
  },
  request_timeout = 2000,
```


## :Lspsaga lsp_finder

A `finder` to show the defintion, reference and implementation (only shown when current hovered word is a function, a type, a class, or an interface).

Default options:
```lua
  finder = {
    --percentage
    max_height = 0.5,
    keys = {
      jump_to = 'p',
      edit = { 'o', '<CR>' },
      vsplit = 's',
      split = 'i',
      tabe = 't',
      quit = { 'q', '<ESC>' },
      close_in_preview = '<ESC>'
    },
  },
```

- `max_height` of the finder window.
- `keys.jump_to` finder peek window.
- `close_in_preview` will close all finder window in when you in preview window.

<details>
<summary>lsp_finder showcase</summary>

<img
src="https://user-images.githubusercontent.com/41671631/215719819-4bfe6e86-fecc-4dc0-bac0-837c0bdeb349.gif" height=80% width=80%/>
</details>


## :Lspsaga peek_definition

There are two commands, `:Lspsaga peek_definition` and `:Lspsaga goto_definition`. The `peek_definition` command works like the VSCode command of the same name, which shows the target file in an editable floating window.

Default options:
```lua
  definition = {
    edit = "<C-c>o",
    vsplit = "<C-c>v",
    split = "<C-c>i",
    tabe = "<C-c>t",
    quit = "q",
    close = "<Esc>",
  }
```

<details>
<summary>peek_definition showcase</summary>

The steps demonstrated in this showcase are:
- Pressing `gd` to run `:Lspsaga peek_definition`
- Editing a comment and using `:w` to save
- Pressing `<C-c>o` to jump to the file in the floating window
- Lspsaga shows a beacon highlight after jumping to the file

<img
src="https://user-images.githubusercontent.com/41671631/215719806-0dea0248-4a2c-45df-a258-43a4ba207a43.gif" height=80% width=80%/>
</details>

## :Lspsaga goto_definition

Jumps to the definition of the hovered word and shows a beacon highlight.


## :Lspsaga code_action

Default options:
```lua
  code_action = {
    num_shortcut = true,
    show_server_name = false,
    extend_gitsigns = true
    keys = {
      -- string | table type
      quit = "q",
      exec = "<CR>",
    },
  },
```
- `num_shortcut` - It is `true` by default so you can quickly run a code action by pressing its corresponding number.
- `extend_gitsigns` show gitsings in code action.

<details>
<summary>code_action showcase</summary>

The steps demonstrated in this showcase are:
- Pressing `ga` to run `:Lspsaga code_action`
- Pressing `j` to move within the code action preview window
- Pressing `<Cr>` to run the action

<img src="https://user-images.githubusercontent.com/41671631/215719772-ccebdcba-4e4a-46f7-9af8-61ac8391f2f4.gif" height=80% width=80%/>
</details>

## :Lspsaga Lightbulb

When there are possible code actions to be taken, a lightbulb icon will be shown.

Default options:
```lua
  lightbulb = {
    enable = true,
    enable_in_insert = true,
    sign = true,
    sign_priority = 40,
    virtual_text = true,
  },
```

<details>
<summary>lightbulb showcase</summary>
<img src="https://user-images.githubusercontent.com/41671631/212009221-e0fb193e-f69d-4ed6-a4a2-d9ecb589f211.gif" height=80% width=80%/>
</details>

## :Lspasga hover_doc

You should install the [treesitter](https://github.com/nvim-treesitter/nvim-treesitter) markdown parser so Lspsaga can use it to render the hover window.
You can press the keyboard shortcut for `:Lspsaga hover_doc` twice to enter the hover window.

<details>
<summary>hover_docshow case</summary>

The steps demonstrated in this showcase are:
- Pressing `K` once to run `:Lspsaga hover_doc`
- Pressing `K` again to enter the hover window
- Pressing `q` to quit

<img src="https://user-images.githubusercontent.com/41671631/215719832-37d2f6ab-66ed-4500-b6de-a6c289983ab2.gif" height=80% width=80%/>

</details>

## :Lspsaga diagnostic_jump_next

Jumps to next diagnostic position and show a beacon highlight. Lspsaga will then show the code actions.

Default options:
```lua
  diagnostic = {
    show_code_action = true,
    show_source = true,
    jump_num_shortcut = true,
     --1 is max
    max_width = 0.7,
    custom_fix = nil,
    custom_msg = nil,
    text_hl_follow = false,
    border_follow = true,
    keys = {
      exec_action = "o",
      quit = "q",
      go_action = "g"
    },
  },
```

- Using `go_action`, you can quickly jump to line where actions need to be taken in the diagnostics floating window.
- `jump_num_shortcut` - The default is `true`. After jumping, Lspasga will automatically bind code actions to a number. Afterwards, you can press the number to execute the code action. After the floating window is closed, these numbers will no longer be tied to the same code actions.
- `custom_msg` string used to custom the diagnostic jump `Msg` section titile
- `custom_fix` string used to custom the diagnostic jump `Fix` section titile
- `max_width` is the max width for diagnostic jump window. percentage
- `text_hl_follow` is false default true that you can define `DiagnostcText` to custom the diagnotic
  text color
- `border_follow` the border highlight will follow the diagnostic type. if false it will use the
  highlight `DiagnosticBorder`.

You can also use a filter when using diagnostic jump by using a Lspsaga function. The function takes a table as its argument.
It is functionally identical to `:h vim.diagnostic.get_next`.

```lua
-- This will only jump to an error
-- If no error is found, it executes "goto_next"
require("lspsaga.diagnostic"):goto_prev({ severity = vim.diagnostic.severity.ERROR })
```

<details>
<summary>diagnostic_jump_next showcase</summary>

The steps demonstrated in this showcase are:
- Pressing `[e` to jump to the next diagnostic position, which shows the beacon highlight and the code actions in a diagnostic window
- Pressing the number `2` to execute the code action without needing to enter the floating window

<img src="https://user-images.githubusercontent.com/41671631/215725463-36065017-91b6-401a-b48b-764179eaeb5e.gif" height=80% width=80%/>

- If you want to see the code action, you can use `<C-w>w` to enter the floating window.
- Press `g` to go to the action line and see the code action preview.
- Press `o` to execute the action.


</details>

## :Lspsaga show_diagnostics

`show_line_diagnostics`, `show_buf_diagnostics`, `show_cursor_diagnostics`

- you can use `<C-w>w` jump into and use `<CR>` jump to diagnostic position

<details>
<summary>show_diagnostics showcase</summary>

<img src="https://user-images.githubusercontent.com/41671631/215719847-c09e84c0-c19a-4365-bd16-87800e3685cc.gif" height=80% width=80%/>
</details>

## :Lspsaga rename

Uses the current LSP to rename the hovered word.

Default options:
```lua
  rename = {
    quit = "<C-c>",
    exec = "<CR>",
    mark = "x",
    confirm = "<CR>",
    in_select = true,
  },
```

- `mark` is used for the `++project` argument. It is used to mark the files which you want to rename the hovered word in.
- `confirm` - After you have marked the files, press this key to execute the rename.

<details>
<summary>rename showcase</summary>

The steps demonstrated in this showcase are:
- Pressing `gr` to run `:Lspsaga rename`
- Typing `stesdd` and then pressing `<CR>` to execute the rename

<img src="" height=80% width=80%/>

The steps demonstrated in this showcase are:
- Pressing `gR` to run `:Lspsaga rename ++project`
- Pressing `x` to mark the file
- Pressing `<CR>` to execute rename

<img src="https://user-images.githubusercontent.com/41671631/215719843-7278cc97-399f-48ee-88eb-555647eba42f.gif"  height=80% width=80%/>
</details>

## :Lspsaga outline

Default options:
```lua
  outline = {
    win_position = "right",
    win_with = "",
    win_width = 30,
    show_detail = true,
    auto_preview = true,
    auto_refresh = true,
    auto_close = true,
    custom_sort = nil,
    keys = {
      jump = "o",
      expand_collapse = "u",
      quit = "q",
    },
  },
```

<details>
<summary>outline showcase</summary>

The steps demonstrated in this showcase are:
- Pressing `<Leader>o` run `:Lspsaga outline`
- Pressing `j` to move down
- Pressing `o` to jump

<img src="https://user-images.githubusercontent.com/41671631/215719836-25a03774-891b-4dfd-ab2f-0b590ae1c862.gif" height=80% width=80%/>
</details>

## :Lspsaga incoming_calls / outgoing_calls

Runs the LSP's callhierarchy/incoming_calls.

Default options:
```lua
  callhierarchy = {
    show_detail = false,
    keys = {
      edit = "e",
      vsplit = "s",
      split = "i",
      tabe = "t",
      jump = "o",
      quit = "q",
      expand_collapse = "u",
    },
  },
```

<details>
<summary>incoming_calls showcase</summary>
<img src="https://user-images.githubusercontent.com/41671631/215719762-9482e84b-921e-425e-b1a9-7bd1f569a5ce.gif" height=80% width=80%/>
</details>


## :Lspsaga symbols in winbar

This requires Neovim version >= 0.8.

Default options:
```lua
  symbol_in_winbar = {
    enable = true,
    separator = " ",
    hide_keyword = true,
    show_file = true,
    folder_level = 2,
    respect_root = false,
    color_mode = true,
  },
```
- `hide_keyword` - The default value is `true`. Lspsaga will hide some keywords and temporary variables to make the symbols look cleaner.
- `folder_level` only works when `show_file` is `true`.
- `respect_root` will respect the LSP's root. If this is `true`, Lspsaga will ignore the `folder_level` option. If no LSP client is being used, Lspsaga will fall back to using folder level.
- `color_mode` - The default value is `true`. When it is set to `false`, only icons will have color.

<details>
<summary>Symbols in winbar</summary>
<img src="https://user-images.githubusercontent.com/41671631/212026278-11012b17-209c-4b55-b76c-1c3d8d9a2eb2.gif" height=80% width=80%/>
</details>

## :Lspsaga symbols in a custom winbar/statusline

Lspsaga provides an API that you can use in your custom winbar or statusline.

```lua
vim.wo.winbar / vim.wo.stl = require('lspsaga.symbolwinbar'):get_winbar()
```

## :Lspsaga term_toggle

A simple floating terminal.

<details>
<summary>Toggling the floating terminal</summary>
<img src="https://user-images.githubusercontent.com/41671631/212027060-56d1cebc-c6a8-412e-bd01-620aac3029ed.gif" height=80% width=80%/>
</details>

## :Lspsaga beacon

after jump from float window there will show beacon to remind you where the cursor is.

```lua
  beacon = {
    enable = true,
    frequency = 7,
  },
```

`frequency` the blink frequency.

## Customizing Lspsaga's Appearance

## :Lspsaga UI

Default UI options
```lua
  ui = {
    -- Currently, only the round theme exists
    theme = "round",
    -- This option only works in Neovim 0.9
    title = true,
    -- Border type can be single, double, rounded, solid, shadow.
    border = "solid",
    winblend = 0,
    expand = "",
    collapse = "",
    preview = " ",
    code_action = "💡",
    diagnostic = "🐞",
    incoming = " ",
    outgoing = " ",
    hover = ' ',
    kind = {},
  },
```

# Custom Highlighting

All highlight groups can be found in [highlight.lua](./lua/lspsaga/highlight.lua).

# Custom Kind

Modify `ui.kind` to change the icons of the kinds.

All kinds used in Lspsaga are defined in [lspkind.lua](./lua/lspsaga/lspkind.lua).
The key in `ui.kind` is the kind name, and the value can either be a string or a table. If a string is passed, it is setting the `icon`. If table is passed, it will be passed as `{ icon, color }`.

# Backers
Thanks for everything!

[@Möller Lukas](https://github.com/lmllrjr)
[@HendrikPetertje](https://github.com/HendrikPetertje)
[@Bojan Wilytsch](https://github.com/bwilytsch)
[@zhourrr](https://github.com/zhourrr)
[@Burgess Darrion](https://github.com/ca-mantis-shrimp)

# Donate

[![](https://img.shields.io/badge/PayPal-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/bobbyhub)

Currently, I am in need of some donations. If you'd like to support my work financially, please donate through [PayPal](https://paypal.me/bobbyhub).
Thanks!

# License

Licensed under the [MIT](./LICENSE) license.
