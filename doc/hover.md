## Default Options

default options in `hover` section.

- `max_width = 0.9`
- `max_height = 0.8`
- `open_link = 'gx'`
- `open_cmd = '!chrome'`

## Pre Require

treesitter `markdown` and `markdown_inline` parser . If you got trouble run `:checkhealth` first.

Why need these pareser. Unlike the built-in hover `vim.lsp.buf.hover`. it use regex syntax render markdown. lspsaga use treesitter render markdown.

## Hover Usage

command is `:Lspsaga hover_doc`. and run command twice will close hover window

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/eb370389-ba84-4dbc-b08b-adbee358aedb)

config a keymap like:

```lua
vim.keymap.set('n', 'K', '<cmd>Lspsaga hover_doc')
```

### keep hover window

when command has `:Lspsaga hover_doc ++keep` when you want keep the hover window.
use `++keep` . it will show hover window in top right.

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/cb25b8ea-6437-44a1-9864-57d118c7457f)


### Highlight

- `HoverNormal` config the hover window normal.
- `HoverBorder ` config the hover window border.