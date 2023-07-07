## Callhierarchy Usage

callhierarchy has two commands `:Lspsaga incoming_calls` and `:Lspsaga outgoing_calls`.

![image](https://github.com/nvimdev/lspsaga.nvim/assets/41671631/20d4001f-57a2-4ad5-87a8-514171c011c1)


## Default Options

default options in `callhierarchy` section

 - `layout = 'float'`  layout available value `normal` `float`

## Default Keymaps

default keymaps in `callhierarchy.keys`

- `edit = 'e'`           edit(open) file
- `vsplit = 's'`         vsplit
- `split = 'i'`          split
- `tabe = 't'`           open in tabe
- `quit = 'q'`           quit f
- `shuttle = '[w'`        shuttle bettween the layout left and right
- `toggle_or_req = 'u'`  toggle or do requese.


## Change Layout

two ways change layout first is change `layout` option, second is pass layout from command like `:Lspsaga incoming_calls ++normal`