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

[![](https://img.shields.io/badge/Element-0DBD8B?style=for-the-badge&logo=element&logoColor=white)](https://matrix.to/#/#lspsaga-nvim:matrix.org)

1. [Install](#install)
2. [Example Configuration](#example-configuration)
3. [Usage Turtorial](#usage-tutorial)
4. [Customize Appearance](#customize-appearance)
5. [Backers](#backers)
6. [Donate](#donate)
7. [License](#license)

# Install

you can use some plugins management like `lazy.nvim`, `packer.nvim` to install `lspsaga` and lazyload by the plugin management keyword.

- `cmd` lazyload by `lspsaga` command
- `ft`  lazy.nvim and packer both provide lazyload by filetype. then you can load the lspsaga according the filetypes which you write and use lsp.
- `event` lazyload by event like `BufRead,BufReadPost` make sure your lsp plugin also loaded.
- `dependices` for lazy.nvim you can set the `lspsaga` into `nvim-lspconfig` or other lsp plugin `dependices` keyword.
- `after` for packer you can use after keyword.

## Lazy

```lua
require('lazy').setup({
    'glepnir/lspsaga.nvim',
    event = 'BufRead',
    config = function()
        require('lspsaga').setup({})
    end
},opt)
```

## Packer

```lua
use({
    "glepnir/lspsaga.nvim",
    branch = "main",
    config = function()
        require('lspsaga').setup({})
    end,
})
```

# Example Configuration

```lua
require('lazy').setup({
    'glepnir/lspsaga.nvim',
    event = 'BufRead',
    config = function()
      require('lspsaga').setup({})
    end
})

local keymap = vim.keymap.set
-- Lsp finder find the symbol definition implement reference
-- if there is no implement it will hide
-- when you use action in finder like open vsplit then you can
-- use <C-t> to jump back
keymap("n", "gh", "<cmd>Lspsaga lsp_finder<CR>")

-- Code action
keymap({"n","v"}, "<leader>ca", "<cmd>Lspsaga code_action<CR>")

-- Rename
keymap("n", "gr", "<cmd>Lspsaga rename<CR>")

-- Peek Definition
-- you can edit the definition file in this flaotwindow
-- also support open/vsplit/etc operation check definition_action_keys
-- support tagstack C-t jump back
keymap("n", "gd", "<cmd>Lspsaga peek_definition<CR>")

-- Go to Definition
keymap("n","gd", "<cmd>Lspsaga goto_definition<CR>")

-- Show line diagnostics you can pass arugment ++unfocus to make
-- show_line_diagnsotic float window unfocus
keymap("n", "<leader>sl", "<cmd>Lspsaga show_line_diagnostics<CR>")

-- Show cursor diagnostic
-- also like show_line_diagnostics  support pass ++unfocus
keymap("n", "<leader>sc", "<cmd>Lspsaga show_cursor_diagnostics<CR>")

-- Show buffer diagnostic
keymap("n", "<leader>sb", "<cmd>Lspsaga show_buf_diagnostics<CR>")

-- Diagnsotic jump can use `<c-o>` to jump back
keymap("n", "[e", "<cmd>Lspsaga diagnostic_jump_prev<CR>")
keymap("n", "]e", "<cmd>Lspsaga diagnostic_jump_next<CR>")

-- Diagnostic jump with filter like Only jump to error
keymap("n", "[E", function()
  require("lspsaga.diagnostic").goto_prev({ severity = vim.diagnostic.severity.ERROR })
end)
keymap("n", "]E", function()
  require("lspsaga.diagnostic").goto_next({ severity = vim.diagnostic.severity.ERROR })
end)

-- Toggle Outline
keymap("n","<leader>o", "<cmd>Lspsaga outline<CR>")

-- Hover Doc
-- if there has no hover will have a notify no information available
-- to disable it just Lspsaga hover_doc ++quiet
keymap("n", "K", "<cmd>Lspsaga hover_doc<CR>")

-- Callhierarchy
keymap("n", "<Leader>ci", "<cmd>Lspsaga incoming_calls<CR>")
keymap("n", "<Leader>co", "<cmd>Lspsaga outgoing_calls<CR>")

-- Float terminal
keymap({"n", "t"}, "<A-d>", "<cmd>Lspsaga term_toggle<CR>")
```

## Usage Tutorial
**Notice that title in float window must need neovim version >= 0.9**

## default options

```lua
  preview = {
    lines_above = 0,
    lines_below = 10,
  },
  scroll_preview = {
    scroll_down = '<C-f>',
    scroll_up = '<C-b>',
  },
  request_timeout = 2000,
```


## :Lspsaga lsp_finder

`Finder` to show the defintion,reference,implement(only show when current word is interface or some type)

default finder options

```lua
  finder = {
    edit = { 'o', '<CR>' },
    vsplit = 's',
    split = 'i',
    tabe = 't',
    quit = { 'q', '<ESC>' },
  },
```

<details>
<summary>lsp finder show case</summary>

<img
src="https://user-images.githubusercontent.com/41671631/212032702-f45bba5a-3e2e-465d-85c3-3d02d1b88da4.gif" height=80% width=80%/>
</details>


## :Lspsaga peek_definition

there has two commands `Lspsaga peek_definition` and `Lspsaga goto_definition`, the `peek_definition` work like vscode that show the target file in a floatwindow you can edit as normalize.

options with default value

```lua
  definition = {
    edit = '<C-c>o',
    vsplit = '<C-c>v',
    split = '<C-c>i',
    tabe = '<C-c>t',
    quit = 'q',
    close = '<Esc>',
  }
```

<details>
<summary>peek_definition show case</summary>

the step in this gif show case
- `gd` run `lspsaga peek_definition`.
- do some comment edit then `:w` to save.
- `<C-c> o` jump to this file.
- lspsaga will show becacon highlight after jump .

<img
src="https://user-images.githubusercontent.com/41671631/212002926-60c11060-233c-4610-a86e-57decefe6927.gif" height=80% width=80%/>
</details>

## :Lspsaga goto_definition

jump to definition and show beacon


## :Lspsaga code_action

options with default value

```lua
  code_action = {
    num_shortcut = true,
    keys = {
      -- string |table type
      quit = 'q',
      exec = '<CR>',
    },
  },
```
- `num_shortcut` it's `true` by default then you can use number to fast run action

<details>
<summary> code_action show case </summary>

- `ga` run `Lspsaga code_action`
- `j` to move and show the code action preview
- `<Cr>` to run a action
<img src="https://user-images.githubusercontent.com/41671631/212005522-bc7fa99b-6c6f-4c0e-b7fc-c95edee5c169.gif" height=80% width=80%/>
</details>

## :Lspsaga Lightbulb

when there has code action it will show a lightbulb, default options.

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
<summary> lightbulb show case </summary>
<img src="https://user-images.githubusercontent.com/41671631/212009221-e0fb193e-f69d-4ed6-a4a2-d9ecb589f211.gif" height=80% width=80%/>
</details>

## :Lspasga hover_doc

lspsaga use treesitter markdown parser to render hover. so you must install markdown parser.
you can press shotcut of `Lspsaga hover_doc` twice jump into the hover window. in my case is `K`.

<details>
<summary> hover_doc show case </summary>

- `K` to run `Lspsaga hover_doc`.
- press `K` again jump into the hover window.
- `q` to quit.
   
<img src="https://user-images.githubusercontent.com/41671631/212010765-55341ba1-95c2-41e9-b4bd-03827676ee94.gif" height=80% width=80%/>
</details>

## :Lspsaga diagnostic_jump_next

jump to next diagnsotic position then show beacon and show the codeaction. default options

```lua
  diagnostic = {
    twice_into = false,
    show_code_action = true,
    show_source = true,
    keys = {
      exec_action = 'o',
      quit = 'q',
      go_action = 'g'
    },
  },
```
if `twice_into` set to `true`, press twice the diagnostic jump shortcut it will jump into the floatwindow. other way is use `wincmd` to jump into use `<C-w>w`.

`go_action` can quickly jump to action line in diagnostic floatwindow

also you can use a filter in diagnostic jump by using lspsaga function. function params is a table
same as `:h vim.diagnsotic.get_next`

```lua
-- this is mean only jump to error position
-- or goto_next
require("lspsaga.diagnostic").goto_prev({ severity = vim.diagnostic.severity.ERROR })
```

<details>
<summary>diagnostic jump show case </summary>

- `[e` to jump next diangostic position.
- `<C-w>w` jump into the float window.
- `j` to move.
- `o` to execuate an action.

<img src="https://user-images.githubusercontent.com/41671631/212014091-ebeb4571-47e4-4c47-9d05-d57b173faa22.gif" height=80% width=80%/>
</details>


## :Lspsaga show_diagnsotic

`show_line_diagnsotic` , `show_buf_diagnostics` ,`show_cursor_diagnostics`

<details>
<summary> show diangostics show case </summary>
<img src="https://user-images.githubusercontent.com/41671631/212220793-a52215fd-5f60-4be6-8132-78247b921f1e.gif" height=80% width=80%/>
</details>

## :Lspsaga rename

lsp rename with select. default options

```lua

  rename = {
    quit = '<C-c>',
    exec = '<CR>',
    mark = 'x',
    confirm = '<CR>',
    in_select = true,
    whole_project = true,
  },
```

- `whole_project` support rename whole project after using lsp rename by `rg`.
- `mark` after lsp rename if there still have this word in project then wil popup a window that inclue the files which include the word.then you can use this key mark the line that you want changed.
- `confirm` when you markd the lines then press this keymap to execute.

<details>
<summary> rename show case</summary>

- `gr` to run `Lspsaga rename`
- `stesdd<CR>` 

<img src="https://user-images.githubusercontent.com/41671631/212015791-5a278ace-d23a-4954-bb95-1978f51153a7.gif" height=80% width=80%/>
</details>

## :Lspsaga outline

default options

```lua
  outline = {
    win_position = 'right',
    win_with = '',
    win_width = 30,
    show_detail = true,
    auto_preview = true,
    auto_refresh = true,
    auto_close = true,
    custom_sort = nil,
    keys = {
      jump = 'o',
      expand_collapse = 'u',
      quit = 'q',
    },
  },
```

<details>
<summary>outline show case</summary>

- `<Leader>o` run `Lspsaga outline`
- `j` move down
- `o` to jump

<img src="https://user-images.githubusercontent.com/41671631/212017018-6753e470-58e4-498e-8812-5ff416ff27c1.gif" height=80% width=80%/>
</details>

## :Lspsaga incoming_calls

run lsp callhierarchy incoming_calls.  default options

```lua
  callhierarchy = {
    show_detail = false,
    keys = {
      edit = 'e',
      vsplit = 's',
      split = 'i',
      tabe = 't',
      jump = 'o',
      quit = 'q',
      expand_collapse = 'u',
    },
  },
```

<details>
<summary>incoming_calls show case</summary>
<img src="https://user-images.githubusercontent.com/41671631/212018219-26ed4a5f-00e1-488a-8a87-1a89f2c5d14b.gif" height=80% width=80%/>
</details>

## :Lspsaga outgoing_calls

run lsp callhierarchy outgoing_calls

<details>
<summary>outgoing show_case</summary>
<img src="https://user-images.githubusercontent.com/41671631/212024418-cf26f3f7-7acb-46df-a50a-9abe3f8f68f3.gif" height=80% width=80%/>
</details>

## :Lspsaga symbols in winbar

require your neovim version >= 0.8. options with default value

```lua
  symbol_in_winbar = {
    enable = true,
    separator = ' ',
    hide_keyword = true,
    show_file = true,
    folder_level = 2,
    respect_root = false,
    color_mode = false,
  },
```
- `hide_keyword` default is true it will hide some keyword or tmp variable make symbols more clean
- `folder_level` work with `show_file`
- `respect_root` will respect lsp root if this is true will ignore the folder_level. if there is no
  lsp client usage then fallback to folder_level
- `color_mode` default is false that mean only the icon have color when true the icon and word
  both have highlight.


<details>
<summary>symbols in winbar </summary>
<img src="https://user-images.githubusercontent.com/41671631/212026278-11012b17-209c-4b55-b76c-1c3d8d9a2eb2.gif" height=80% width=80%/>
</details>

## :Lspaga symbols in custom winbar/statusline

lspsaga provide an api that you can use in your custom winbar or statusline.

```lua
vim.wo.winbar/ vim.wo.stl = require('lspsaga.symbolwinbar'):get_winbar()
```

## :Lspsaga term_toggle

simple floaterm

<details>
<summary> float terminal toggle</summary>
<img src="https://user-images.githubusercontent.com/41671631/212027060-56d1cebc-c6a8-412e-bd01-620aac3029ed.gif" height=80% width=80%/>
</details>

## Customize Appearance

## :Lspsaga UI

default ui options

```lua
  ui = {
    -- currently only round theme
    theme = 'round',
    -- border type can be single,double,rounded,solid,shadow.
    border = 'solid',
    winblend = 0,
    expand = '',
    collapse = '',
    preview = ' ',
    code_action = '💡',
    diagnostic = '🐞',
    incoming = ' ',
    outgoing = ' ',
    colors = {
      --float window normal bakcground color
      normal_bg = '#1d1536',
      --title background color
      title_bg = '#afd700',
      red = '#e95678',
      magenta = '#b33076',
      orange = '#FF8700',
      yellow = '#f7bb3b',
      green = '#afd700',
      cyan = '#36d0e0',
      blue = '#61afef',
      purple = '#CBA6F7',
      white = '#d1d4cf',
      black = '#1c1c19',
    },
    kind = {},
  },
```

# Custom Highlight

If you don't like config the colors or you use switch colorschem according time then you can use 
the old way. change the highlight group in your colorscheme or config.
find all highlight groups in [highlight.lua](./lua/lspsaga/highlight.lua)

# Custom Kind

through `ui.kind` to modified the all kinds defined in [lspkind.lua](./lua/lspsaga/lspkind.lua)
the key in `ui.kind` is kind name, value can be string or table if string type is icon if table type
is `{icon, color}`.

# Backers
Thanks for all.

[@Bojan Wilytsch](https://github.com/bwilytsch)
[@HendrikPetertje](https://github.com/HendrikPetertje)

# Donate

[![](https://img.shields.io/badge/PayPal-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/bobbyhub)

Currently I need some donate. If you'd like to support my work financially, donate through [paypal](https://paypal.me/bobbyhub).
Thanks!

# License

Licensed under the [MIT](./LICENSE) license.
