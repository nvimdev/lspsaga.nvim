local vim, api = vim, vim.api
local M = {}
local config = require("lspsaga").config_values
local wrap = require "lspsaga.wrap"

local function get_border_style(style, highlight)
  highlight = highlight or "FloatBorder"
  local border_style = {
    ["single"] = "single",
    ["double"] = "double",
    ["round"] = {
      { "╭", highlight },
      { "─", highlight },
      { "╮", highlight },
      { "│", highlight },
      { "╯", highlight },
      { "─", highlight },
      { "╰", highlight },
      { "│", highlight },
    },
    ["bold"] = {
      { "┏", highlight },
      { "─", highlight },
      { "┓", highlight },
      { "│", highlight },
      { "┛", highlight },
      { "─", highlight },
      { "┗", highlight },
      { "│", highlight },
    },
    ["plus"] = {
      { "+", highlight },
      { "─", highlight },
      { "+", highlight },
      { "│", highlight },
      { "+", highlight },
      { "─", highlight },
      { "+", highlight },
      { "│", highlight },
    },
  }

  return border_style[style]
end

local function make_floating_popup_options(width, height, opts)
  vim.validate {
    opts = { opts, "t", true },
  }
  opts = opts or {}
  vim.validate {
    ["opts.offset_x"] = { opts.offset_x, "n", true },
    ["opts.offset_y"] = { opts.offset_y, "n", true },
  }
  local new_option = {}

  new_option.style = "minimal"
  new_option.width = width
  new_option.height = height

  if opts.relative ~= nil then
    new_option.relative = opts.relative
  else
    new_option.relative = "cursor"
  end

  if opts.anchor ~= nil then
    new_option.anchor = opts.anchor
  end

  if opts.row == nil and opts.col == nil then
    local lines_above = vim.fn.winline() - 1
    local lines_below = vim.fn.winheight(0) - lines_above
    new_option.anchor = ""

    local pum_pos = vim.fn.pum_getpos()
    local pum_vis = not vim.tbl_isempty(pum_pos) -- pumvisible() can be true and pum_pos() returns {}
    if pum_vis and vim.fn.line "." >= pum_pos.row or not pum_vis and lines_above < lines_below then
      new_option.anchor = "N"
      new_option.row = 1
    else
      new_option.anchor = "S"
      new_option.row = -2
    end

    if vim.fn.wincol() + width <= api.nvim_get_option "columns" then
      new_option.anchor = new_option.anchor .. "W"
      new_option.col = 0
    else
      new_option.anchor = new_option.anchor .. "E"
      new_option.col = 1
    end
  else
    new_option.row = opts.row
    new_option.col = opts.col
  end

  return new_option
end

local function generate_win_opts(contents, opts)
  opts = opts or {}
  local win_width, win_height
  -- _make_floating_popup_size doesn't allow the window size to be larger than
  -- the current window. For the finder preview window, this means it won't let the
  -- preview window be wider than the finder window. To work around this, the
  -- no_size_override option can be set to indicate that the size shouldn't be changed
  -- from what was given.
  if opts.no_size_override and opts.width and opts.height then
    win_width, win_height = opts.width, opts.height
  else
    win_width, win_height = vim.lsp.util._make_floating_popup_size(contents, opts)
  end
  opts = make_floating_popup_options(win_width, win_height, opts)
  return opts
end

local function get_shadow_config()
  local opts = {
    relative = "editor",
    style = "minimal",
    width = vim.o.columns,
    height = vim.o.lines,
    row = 0,
    col = 0,
  }
  return opts
end

local function open_shadow_win()
  local opts = get_shadow_config()
  local shadow_winhl = "Normal:SagaShadow,NormalNC:SagaShadow,EndOfBuffer:SagaShadow"
  local shadow_bufnr = api.nvim_create_buf(false, true)
  local shadow_winid = api.nvim_open_win(shadow_bufnr, true, opts)
  api.nvim_win_set_option(shadow_winid, "winhl", shadow_winhl)
  api.nvim_win_set_option(shadow_winid, "winblend", 70)
  return shadow_bufnr, shadow_winid
end

function M.create_win_with_border(content_opts, opts)
  vim.validate {
    content_opts = { content_opts, "t" },
    contents = { content_opts.content, "t", true },
    opts = { opts, "t", true },
  }

  local contents, filetype = content_opts.contents, content_opts.filetype
  local enter = content_opts.enter or false
  local highlight = content_opts.highlight or "LspFloatWinBorder"
  opts = opts or {}
  opts = generate_win_opts(contents, opts)
  opts.border = get_border_style(config.border_style, highlight)

  -- create contents buffer
  local bufnr = api.nvim_create_buf(false, true)
  -- buffer settings for contents buffer
  -- Clean up input: trim empty lines from the end, pad
  local content = vim.lsp.util._trim(contents)

  if filetype then
    api.nvim_buf_set_option(bufnr, "filetype", filetype)
  end

  api.nvim_buf_set_lines(bufnr, 0, -1, true, content)
  api.nvim_buf_set_option(bufnr, "modifiable", false)
  api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
  api.nvim_buf_set_option(bufnr, "buftype", "nofile")

  local winid = api.nvim_open_win(bufnr, enter, opts)
  if filetype == "markdown" then
    api.nvim_win_set_option(winid, "conceallevel", 2)
  end

  api.nvim_win_set_option(winid, "winhl", "Normal:LspFloatWinNormal,FloatBorder:" .. highlight)
  api.nvim_win_set_option(winid, "winblend", 0)
  api.nvim_win_set_option(winid, "foldlevel", 100)
  return bufnr, winid
end

function M.open_shadow_float_win(content_opts, opts)
  local shadow_bufnr, shadow_winid = open_shadow_win()
  local contents_bufnr, contents_winid = M.create_win_with_border(content_opts, opts)
  return contents_bufnr, contents_winid, shadow_bufnr, shadow_winid
end

function M.get_max_float_width()
  -- current window width
  local WIN_WIDTH = vim.fn.winwidth(0)
  local max_width = math.floor(WIN_WIDTH * 0.5)
  return max_width
end

-- get the valid the screen_width
-- if have the file tree in left
-- use vim.o.column - file tree win width
local function get_valid_screen_width()
  local screen_width = vim.o.columns

  if vim.fn.winnr "$" > 1 then
    local special_win = {
      ["NvimTree"] = true,
      ["NerdTree"] = true,
    }
    local first_win_id = api.nvim_list_wins()[1]
    local bufnr = vim.fn.winbufnr(first_win_id)
    local buf_ft = api.nvim_buf_get_option(bufnr, "filetype")
    if special_win[buf_ft] then
      screen_width = screen_width - vim.fn.winwidth(first_win_id)
    end
    return screen_width
  end
  return screen_width
end

local function get_max_content_length(contents)
  vim.validate {
    contents = { contents, "t" },
  }
  if next(contents) == nil then
    return 0
  end
  if #contents == 1 then
    return #contents[1]
  end
  local tmp = {}
  for _, text in ipairs(contents) do
    tmp[#tmp + 1] = #text
  end
  table.sort(tmp)
  return tmp[#tmp]
end

function M.fancy_floating_markdown(contents, opts)
  vim.validate {
    contents = { contents, "t" },
    opts = { opts, "t", true },
  }
  opts = opts or {}

  local stripped = {}
  local highlights = {}
  do
    local i = 1
    while i <= #contents do
      local line = contents[i]
      -- TODO(ashkan): use a more strict regex for filetype?
      local ft = line:match "^```([a-zA-Z0-9_]*)$"
      -- local ft = line:match("^```(.*)$")
      -- TODO(ashkan): validate the filetype here.
      if ft then
        local start = #stripped
        i = i + 1
        while i <= #contents do
          line = contents[i]
          if line == "```" then
            i = i + 1
            break
          end
          table.insert(stripped, line)
          i = i + 1
        end
        table.insert(highlights, {
          ft = ft,
          start = start + 1,
          finish = #stripped + 1 - 1,
        })
      else
        table.insert(stripped, line)
        i = i + 1
      end
    end
  end
  -- Clean up and add padding
  stripped = vim.lsp.util._trim(stripped)

  -- Compute size of float needed to show (wrapped) lines
  opts.wrap_at = opts.wrap_at or (vim.wo["wrap"] and api.nvim_win_get_width(0))
  -- record the first line
  local firstline = stripped[1]

  -- current window height
  local WIN_HEIGHT = vim.fn.winheight(0)

  local width = get_max_content_length(stripped)
  -- the max width of doc float window keep has 20 pad
  local WIN_WIDTH = get_valid_screen_width()

  local _pad = width / WIN_WIDTH
  if _pad < 1 then
    width = math.floor(WIN_WIDTH * 0.7)
  else
    width = math.floor(WIN_WIDTH * 0.6)
  end

  local max_height = math.ceil((WIN_HEIGHT - 4) * 0.5)

  if #stripped + 4 > max_height then
    opts.height = max_height
  end

  stripped = wrap.wrap_contents(stripped, width)

  local wraped_index = #wrap.wrap_text(firstline, width)

  -- if only has one line do not insert truncate line
  if #stripped ~= 1 then
    local truncate_line = wrap.add_truncate_line(stripped)
    if stripped[1]:find "{%s$" then
      for idx, text in ipairs(stripped) do
        if text == "} " or text == "}" then
          wraped_index = idx
          break
        end
      end
    end
    if wraped_index ~= #stripped then
      table.insert(stripped, wraped_index + 1, truncate_line)
    end
  end

  local content_opts = {
    contents = stripped,
    filetype = "sagahover",
    highlight = "LspSagaHoverBorder",
  }

  -- Make the floating window.
  local bufnr, winid = M.create_win_with_border(content_opts, opts)
  local height = opts.height or #stripped
  api.nvim_win_set_var(0, "lspsaga_hoverwin_data", { winid, height, height, #stripped })

  api.nvim_buf_add_highlight(bufnr, -1, "LspSagaDocTruncateLine", wraped_index, 0, -1)

  -- Switch to the floating window to apply the syntax highlighting.
  -- This is because the syntax command doesn't accept a target.
  local cwin = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(winid)

  vim.cmd "ownsyntax markdown"
  local idx = 1
  --@private
  local function apply_syntax_to_region(ft, start, finish)
    if ft == "" then
      return
    end
    local name = ft .. idx
    idx = idx + 1
    local lang = "@" .. ft:upper()
    -- TODO(ashkan): better validation before this.
    if not pcall(vim.cmd, string.format("syntax include %s syntax/%s.vim", lang, ft)) then
      return
    end
    vim.cmd(string.format("syntax region %s start=+\\%%%dl+ end=+\\%%%dl+ contains=%s", name, start, finish + 1, lang))
  end
  -- Previous highlight region.
  -- TODO(ashkan): this wasn't working for some reason, but I would like to
  -- make sure that regions between code blocks are definitely markdown.
  -- local ph = {start = 0; finish = 1;}
  for _, h in ipairs(highlights) do
    h.finish = wraped_index
    -- apply_syntax_to_region('markdown', ph.finish, h.start)
    apply_syntax_to_region(h.ft, h.start, h.finish)
    -- ph = h
  end

  vim.api.nvim_set_current_win(cwin)
  return bufnr, winid
end

function M.nvim_close_valid_window(winid)
  local close_win = function(win_id)
    if win_id == 0 then
      return
    end
    if vim.api.nvim_win_is_valid(win_id) then
      api.nvim_win_close(win_id, true)
    end
  end

  local _switch = {
    ["table"] = function()
      for _, id in ipairs(winid) do
        close_win(id)
      end
    end,
    ["number"] = function()
      close_win(winid)
    end,
  }

  local _switch_metatable = {
    __index = function(_, t)
      error(string.format("Wrong type %s of winid", t))
    end,
  }

  setmetatable(_switch, _switch_metatable)

  _switch[type(winid)]()
end

function M.nvim_win_try_close()
  local has_var, line_diag_winids = pcall(api.nvim_win_get_var, 0, "show_line_diag_winids")
  if has_var and line_diag_winids ~= nil then
    M.nvim_close_valid_window(line_diag_winids)
  end
end

return M
