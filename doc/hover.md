## Hover Usage

command is `:Lspsaga hover_doc`. and run command twice will close hover window

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/eb370389-ba84-4dbc-b08b-adbee358aedb)

config a keymap like:

```lua
vim.keymap.set('n', 'K', '<cmd>Lspsaga hover_doc')
```

## Default Options

default options in `hover` section.

- `max_width = 0.9`
- `max_height = 0.8`
- `open_link = 'gx'`
- `open_cmd = '!chrome'`

## Pre Require

treesitter `markdown` and `markdown_inline` parser . If you got trouble run `:checkhealth` first.

Why need these pareser. Unlike the built-in hover `vim.lsp.buf.hover`. it use regex syntax render markdown. lspsaga use treesitter render markdown.

### keep hover window

when command has `:Lspsaga hover_doc ++keep` when you want keep the hover window.
use `++keep` . it will show hover window in top right.

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/cb25b8ea-6437-44a1-9864-57d118c7457f)

## Open link

lspsaga hover support open link in hover window. usually the doc has link of website of file. you can use `open_link` default is `gx`. open command in default is mac `!open` windows `!explorer` wsl `!wslview` linux `!xdg-open`. if these command not found hover will use `open_cmd`
when cursor on link. almost is the last line. like :

![Untitled](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/30adcdcd-cbda-4442-ab23-e4ff37e42b7e)

workflow in gif:

- config `K` to open lspsaga hover
- press k twice jump into the hover window move cursor to view documents
- press gx


### Highlight

- `HoverNormal` config the hover window normal.
- `HoverBorder ` config the hover window border.