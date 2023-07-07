## Symbols in winbar

support dynamisc render when you input like.

![Untitled](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/2541c09d-9b5b-4b14-9e4b-d66095e07ba0)

**Important**

this module is the pre requeuire of `outline` `implement` module.

## Default Options

default options in `symbol_in_winbar` section

- `enable = true`         enable
- `separator = ' › '`     separator symbol
- `hide_keyword = false`  this need treesitter when is true some symbols name like `if` `for` will ignored
- `show_file = true`      show file before symbols
- `folder_level = 1`      show how many folder before file name
- `color_mode = true`     true mean the symbol name and icon have same color otherwise symbol name is light-white
- `dely = 300`            dynamisc render delay
