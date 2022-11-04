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
   - [Vim Plug](#vim-plug)
   - [Packer](#packer)
1. [Configuration](#configuration)
1. [Customize Appearance](#customize-appearance)
1. [Showcase](#showcase)
1. [Donate](#donate)
1. [License](#license)

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

<details>
<summary> Example config </summary>

```lua
local keymap = vim.keymap.set
local saga = require('lspsaga')

saga.init_lsp_saga()

-- Lsp finder find the symbol definition implement reference
-- if there is no implement it will hide
-- when you use action in finder like open vsplit then you can
-- use <C-t> to jump back
keymap("n", "gh", "<cmd>Lspsaga lsp_finder<CR>", { silent = true })

-- Code action
keymap({"n","v"}, "<leader>ca", "<cmd>Lspsaga code_action<CR>", { silent = true })

-- Rename
keymap("n", "gr", "<cmd>Lspsaga rename<CR>", { silent = true })

-- Peek Definition
-- you can edit the definition file in this flaotwindow
-- also support open/vsplit/etc operation check definition_action_keys
-- support tagstack C-t jump back
keymap("n", "gd", "<cmd>Lspsaga peek_definition<CR>", { silent = true })

-- Show line diagnostics
keymap("n", "<leader>cd", "<cmd>Lspsaga show_line_diagnostics<CR>", { silent = true })

-- Show cursor diagnostic
keymap("n", "<leader>cd", "<cmd>Lspsaga show_cursor_diagnostics<CR>", { silent = true })

-- Diagnsotic jump can use `<c-o>` to jump back
keymap("n", "[e", "<cmd>Lspsaga diagnostic_jump_prev<CR>", { silent = true })
keymap("n", "]e", "<cmd>Lspsaga diagnostic_jump_next<CR>", { silent = true })

-- Only jump to error
keymap("n", "[E", function()
  require("lspsaga.diagnostic").goto_prev({ severity = vim.diagnostic.severity.ERROR })
end, { silent = true })
keymap("n", "]E", function()
  require("lspsaga.diagnostic").goto_next({ severity = vim.diagnostic.severity.ERROR })
end, { silent = true })

-- Outline
keymap("n","<leader>o", "<cmd>LSoutlineToggle<CR>",{ silent = true })

-- Hover Doc
keymap("n", "K", "<cmd>Lspsaga hover_doc<CR>", { silent = true })

-- Float terminal
keymap("n", "<A-d>", "<cmd>Lspsaga open_floaterm<CR>", { silent = true })
-- if you want pass somc cli command into terminal you can do like this
-- open lazygit in lspsaga float terminal
keymap("n", "<A-d>", "<cmd>Lspsaga open_floaterm lazygit<CR>", { silent = true })
-- close floaterm
keymap("t", "<A-d>", [[<C-\><C-n><cmd>Lspsaga close_floaterm<CR>]], { silent = true })
```
</details>

<details>
<summary> Default options with value </summary>

```lua
-- Options with default value
-- "single" | "double" | "rounded" | "bold" | "plus"
border_style = "single",
--the range of 0 for fully opaque window (disabled) to 100 for fully
--transparent background. Values between 0-30 are typically most useful.
saga_winblend = 0,
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
-- preview lines above of lsp_finder
preview_lines_above = 0,
-- preview lines of lsp_finder and definition preview
max_preview_lines = 10,
-- use emoji lightbulb in default
code_action_icon = "💡",
-- if true can press number to execute the codeaction in codeaction window
code_action_num_shortcut = true,
-- same as nvim-lightbulb but async
code_action_lightbulb = {
    enable = true,
    enable_in_insert = true,
    cache_code_action = true,
    sign = true,
    update_time = 150,
    sign_priority = 20,
    virtual_text = true,
},
-- finder icons
finder_icons = {
  def = '  ',
  ref = '諭 ',
  link = '  ',
},
-- finder do lsp request timeout
-- if your project big enough or your server very slow
-- you may need to increase this value
finder_request_timeout = 1500,
finder_action_keys = {
    open = {'o', '<CR>'},
    vsplit = 's',
    split = 'i',
    tabe = 't',
    quit = {'q', '<ESC>'},
},
code_action_keys = {
    quit = 'q',
    exec = '<CR>',
},
definition_action_keys = {
  edit = '<C-c>o',
  vsplit = '<C-c>v',
  split = '<C-c>i',
  tabe = '<C-c>t',
  quit = 'q',
},
rename_action_quit = '<C-c>',
rename_in_select = true,
-- show symbols in winbar must nightly
-- in_custom mean use lspsaga api to get symbols
-- and set it to your custom winbar or some winbar plugins.
-- if in_cusomt = true you must set in_enable to false
symbol_in_winbar = {
    in_custom = false,
    enable = true,
    separator = ' ',
    show_file = true,
    -- define how to customize filename, eg: %:., %
    -- if not set, use default value `%:t`
    -- more information see `vim.fn.expand` or `expand`
    -- ## only valid after set `show_file = true`
    file_formatter = "",
    click_support = false,
},
-- show outline
show_outline = {
  win_position = 'right',
  --set special filetype win that outline window split.like NvimTree neotree
  -- defx, db_ui
  win_with = '',
  win_width = 30,
  auto_enter = true,
  auto_preview = true,
  virt_text = '┃',
  jump_key = 'o',
  -- auto refresh when change buffer
  auto_refresh = true,
},
-- custom lsp kind
-- usage { Field = 'color code'} or {Field = {your icon, your color code}}
custom_kind = {},
-- if you don't use nvim-lspconfig you must pass your server name and
-- the related filetypes into this table
-- like server_filetype_map = { metals = { "sbt", "scala" } }
server_filetype_map = {},
```
</details>

## Show symbols in winbar(nvim 0.8+) or in statusline

<details>
<summary> work with custom winbar/statusline </summary>

```lua
saga.init_lsp_saga({
    symbol_in_winbar = {
        in_custom = true
    }
})
```

- use `require('lspsaga.symbolwinbar').get_symbol_node` this function in your custom winbar
to get symbols node and set `User LspsagaUpdateSymbol` event in your autocmds

```lua
-- Example:
local function get_file_name(include_path)
    local file_name = require('lspsaga.symbolwinbar').get_file_name()
    if vim.fn.bufname '%' == '' then return '' end
    if include_path == false then return file_name end
    -- Else if include path: ./lsp/saga.lua -> lsp > saga.lua
    local sep = vim.loop.os_uname().sysname == 'Windows' and '\\' or '/'
    local path_list = vim.split(string.gsub(vim.fn.expand '%:~:.:h', '%%', ''), sep)
    local file_path = ''
    for _, cur in ipairs(path_list) do
        file_path = (cur == '.' or cur == '~') and '' or
                    file_path .. cur .. ' ' .. '%#LspSagaWinbarSep#>%*' .. ' %*'
    end
    return file_path .. file_name
end

local function config_winbar_or_statusline()
    local exclude = {
        ['terminal'] = true,
        ['toggleterm'] = true,
        ['prompt'] = true,
        ['NvimTree'] = true,
        ['help'] = true,
    } -- Ignore float windows and exclude filetype
    if vim.api.nvim_win_get_config(0).zindex or exclude[vim.bo.filetype] then
        vim.wo.winbar = ''
    else
        local ok, lspsaga = pcall(require, 'lspsaga.symbolwinbar')
        local sym
        if ok then sym = lspsaga.get_symbol_node() end
        local win_val = ''
        win_val = get_file_name(true) -- set to true to include path
        if sym ~= nil then win_val = win_val .. sym end
        vim.wo.winbar = win_val
        -- if work in statusline
        vim.wo.stl = win_val
    end
end

local events = { 'BufEnter', 'BufWinEnter', 'CursorMoved' }

vim.api.nvim_create_autocmd(events, {
    pattern = '*',
    callback = function() config_winbar_or_statusline() end,
})

vim.api.nvim_create_autocmd('User', {
    pattern = 'LspsagaUpdateSymbol',
    callback = function() config_winbar_or_statusline() end,
})
```

</details>

<details>

<summary>Support Click in symbols winbar</summary>

To enable click support for winbar define a function similar to [statusline](https://neovim.io/doc/user/options.html#'statusline') (Search for "Start of execute function label")

minwid will be replaced with current node. For example:

```lua
symbol_in_winbar = {
    click_support = function(node, clicks, button, modifiers)
        -- To see all avaiable details: vim.pretty_print(node)
        local st = node.range.start
        local en = node.range['end']
        if button == "l" then
            if clicks == 2 then
                -- double left click to do nothing
            else -- jump to node's starting line+char
                vim.fn.cursor(st.line + 1, st.character + 1)
            end
        elseif button == "r" then
            if modifiers == "s" then
                print "lspsaga" -- shift right click to print "lspsaga"
            end -- jump to node's ending line+char
            vim.fn.cursor(en.line + 1, en.character + 1)
        elseif button == "m" then
            -- middle click to visual select node
            vim.fn.cursor(st.line + 1, st.character + 1)
            vim.cmd "normal v"
            vim.fn.cursor(en.line + 1, en.character + 1)
        end
    end
}
```
</details>

## Module Contact

* Enable `symbol_in_winbar` will make render outline fast.
* Enable `code_action_lightbulb` will make code action fast.


## Customize Appearance

### Custom Lsp Kind Icon and Color

You can use the `custom_kind` option to change the default icon and color:

```lua
-- if only change the color you can do it like
custom_kind = {
  Field = '#000000',
}

-- if you  want to change the icon and color
custom_kind = {
  Field = {'your icon','your color'},
}
```

### Highlight Group

Colors can be simply changed by overwriting the default highlights groups LspSaga is using.


```vim
highlight link LspSagaFinderSelection Search
" or
highlight link LspSagaFinderSelection guifg='#ff0000' guibg='#00ff00' gui='bold'
```

The available highlight groups you can find in [here](./plugin/lspsaga.lua).

## Changelog

- [version 0.2 in 2022-08-18](./Changelog.md)

## Showcase

<details>
<summary>lsp finder</summary>

<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/181253960-cef49f9d-db8b-4b04-92d8-cb6322749414.png" />
</div>
</details>

<details>
<summary>peek definition</summary>
<div align="center">
<img
src="https://user-images.githubusercontent.com/41671631/189480034-89f4bcc8-918a-47a5-b2a4-0dfe1c688525.gif"/>
</div>
</details>

<details>
<summary>Code action</summary>

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

<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/175306592-f0540e35-561f-418c-a41e-7df167ba9b86.gif"/>
</div>

</details>

<details>
<summary>Rename with preview and select</summary>

<div align="center">
<img
src="https://user-images.githubusercontent.com/41671631/175300080-6e72001c-78dd-4d86-8139-bba38befee15.gif" />
</div>

</details>

<details>
<summary>Jump and show diagnostics</summary>

<div align='center'>
<img
src="https://user-images.githubusercontent.com/41671631/182015252-c2e8acc1-3833-473d-a375-8093e104dc47.gif"/>
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
<summary>Outline</summary>

work fast when lspsaga symbol winbar `in_custom = true` or `enable = true`,

<img
src="https://user-images.githubusercontent.com/41671631/179864315-3ec84106-bcd4-43db-8590-2fb07f4055d9.gif"/>
</div>
</details>

<details>
<summary>Float terminal</summary>

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
