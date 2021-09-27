local window = require "lspsaga.window"
local vim, api, lsp, vfn = vim, vim.api, vim.lsp, vim.fn
local config = require("lspsaga").config_values
local libs = require "lspsaga.libs"
local home_dir = libs.get_home_dir()
local scroll_in_win = require("lspsaga.action").scroll_in_win

local send_request = function(timeout)
  local method = { "textDocument/definition", "textDocument/references" }
  local def_params = lsp.util.make_position_params()
  local ref_params = lsp.util.make_position_params()
  ref_params.context = { includeDeclaration = true }
  local def_response = lsp.buf_request_sync(0, method[1], def_params, timeout or 1000)
  local ref_response = lsp.buf_request_sync(0, method[2], ref_params, timeout or 1000)
  if config.debug then
    print(vim.inspect(def_response))
    print(vim.inspect(ref_response))
  end

  local responses = {}
  if libs.result_isempty(def_response) then
    def_response[1] = {}
    def_response[1].result = {}
    def_response[1].result.saga_msg = "0 definitions found"
  end
  table.insert(responses, def_response)

  if libs.result_isempty(ref_response) then
    ref_response[1] = {}
    ref_response[1].result = {}
    ref_response[1].result.saga_msg = "0 references found"
  end
  table.insert(responses, ref_response)

  for i, response in ipairs(responses) do
    if type(response) == "table" then
      for _, res in pairs(response) do
        if res.result then
          coroutine.yield(res.result, i)
        end
      end
    end
  end
end

local Finder = {}

local uv = vim.loop

function Finder:lsp_finder_request()
  return uv.new_async(vim.schedule_wrap(function()
    local root_dir = libs.get_lsp_root_dir()
    if string.len(root_dir) == 0 then
      print "[LspSaga] get root dir failed"
      return
    end
    self.WIN_WIDTH = vim.fn.winwidth(0)
    self.WIN_HEIGHT = vim.fn.winheight(0)
    self.contents = {}
    self.short_link = {}
    self.definition_uri = 0
    self.reference_uri = 0

    local request_intance = coroutine.create(send_request)
    self.buf_filetype = api.nvim_buf_get_option(0, "filetype")
    while true do
      local _, result, method_type = coroutine.resume(request_intance)
      self:create_finder_contents(result, method_type, root_dir)

      if coroutine.status(request_intance) == "dead" then
        break
      end
    end
    self:render_finder_result()
  end))
end

function Finder:create_finder_contents(result, method_type, root_dir)
  local target_lnum = 0
  if type(result) == "table" then
    local method_option = {
      { icon = config.finder_definition_icon, title = ":  " .. #result .. " Definitions" },
      { icon = config.finder_reference_icon, title = ":  " .. #result .. " References" },
    }
    local params = vim.fn.expand "<cword>"
    self.param_length = #params
    local title = method_option[method_type].icon .. params .. method_option[method_type].title

    if method_type == 1 then
      self.definition_uri = result.saga_msg and 1 or #result
      table.insert(self.contents, title)
      target_lnum = 2
      if result.saga_msg then
        table.insert(self.contents, " ")
        table.insert(self.contents, "[1] " .. result.saga_msg)
        return
      end
    else
      self.reference_uri = result.saga_msg and 1 or #result
      target_lnum = target_lnum + self.definition_uri + 5
      table.insert(self.contents, " ")
      table.insert(self.contents, title)
      if result.saga_msg then
        table.insert(self.contents, " ")
        table.insert(self.contents, "[1] " .. result.saga_msg)
        return
      end
    end

    for index, _ in ipairs(result) do
      local uri = result[index].targetUri or result[index].uri
      if uri == nil then
        return
      end
      local bufnr = vim.uri_to_bufnr(uri)
      if not api.nvim_buf_is_loaded(bufnr) then
        vim.fn.bufload(bufnr)
      end
      local link = vim.uri_to_fname(uri) -- returns lowercase drive letters on Windows
      if libs.is_windows() then
        link = link:gsub("^%l", link:sub(1, 1):upper())
      end
      local short_name

      -- reduce filename length by root_dir or home dir
      if link:find(root_dir, 1, true) then
        short_name = link:sub(root_dir:len() + 2)
      elseif link:find(home_dir, 1, true) then
        short_name = link:sub(home_dir:len() + 2)
        -- some definition still has a too long path prefix
        if #short_name > 40 then
          short_name = libs.split_by_pathsep(short_name, 4)
        end
      else
        short_name = libs.split_by_pathsep(link, 4)
      end

      local target_line = "[" .. index .. "]" .. " " .. short_name
      local range = result[index].targetRange or result[index].range
      if index == 1 then
        table.insert(self.contents, " ")
      end
      table.insert(self.contents, target_line)
      target_lnum = target_lnum + 1
      -- max_preview_lines
      local max_preview_lines = config.max_preview_lines
      local lines = api.nvim_buf_get_lines(
        bufnr,
        range.start.line - 0,
        range["end"].line + 1 + max_preview_lines,
        false
      )

      self.short_link[target_lnum] = {
        link = link,
        preview = lines,
        row = range.start.line + 1,
        col = range.start.character + 1,
      }
    end
  end
end

function Finder:render_finder_result()
  if next(self.contents) == nil then
    return
  end
  table.insert(self.contents, " ")
  -- get dimensions
  local width = api.nvim_get_option "columns"
  local height = api.nvim_get_option "lines"

  -- calculate our floating window size
  local win_height = math.ceil(height * 0.8)
  local win_width = math.ceil(width * 0.8)

  -- and its starting position
  local row = math.ceil((height - win_height) * 0.7)
  local col = math.ceil((width - win_width))
  local opts = {
    style = "minimal",
    relative = "editor",
    row = row,
    col = col,
  }

  local max_height = math.ceil((height - 4) * 0.5)
  if #self.contents > max_height then
    opts.height = max_height
  end

  local content_opts = {
    contents = self.contents,
    filetype = "lspsagafinder",
    enter = true,
    highlight = "LspSagaLspFinderBorder",
  }

  self.bufnr, self.winid = window.create_win_with_border(content_opts, opts)
  api.nvim_buf_set_option(self.contents_buf, "buflisted", false)
  api.nvim_win_set_var(self.conents_win, "lsp_finder_win_opts", opts)
  api.nvim_win_set_option(self.conents_win, "cursorline", true)

  if not self.cursor_line_bg and not self.cursor_line_fg then
    self:get_cursorline_highlight()
  end
  api.nvim_command "highlight! link CursorLine LspSagaFinderSelection"
  api.nvim_command 'autocmd CursorMoved <buffer> lua require("lspsaga.provider").set_cursor()'
  api.nvim_command 'autocmd CursorMoved <buffer> lua require("lspsaga.provider").auto_open_preview()'
  api.nvim_command "autocmd QuitPre <buffer> lua require('lspsaga.provider').close_lsp_finder_window()"

  for i = 1, self.definition_uri, 1 do
    api.nvim_buf_add_highlight(self.contents_buf, -1, "TargetFileName", 1 + i, 0, -1)
  end

  for i = 1, self.reference_uri, 1 do
    local def_count = self.definition_uri ~= 0 and self.definition_uri or -1
    api.nvim_buf_add_highlight(self.contents_buf, -1, "TargetFileName", i + def_count + 4, 0, -1)
  end
  -- load float window map
  self:apply_float_map()
  self:lsp_finder_highlight()
end

function Finder:apply_float_map()
  local action = config.finder_action_keys
  local nvim_create_keymap = require("lspsaga.libs").nvim_create_keymap
  local lhs = {
    noremap = true,
    silent = true,
  }
  local keymaps = {
    { self.bufnr, "n", action.vsplit, ":lua require'lspsaga.provider'.open_link(2)<CR>" },
    { self.bufnr, "n", action.split, ":lua require'lspsaga.provider'.open_link(3)<CR>" },
    { self.bufnr, "n", action.scroll_down, ":lua require'lspsaga.provider'.scroll_in_preview(1)<CR>" },
    { self.bufnr, "n", action.scroll_up, ":lua require'lspsaga.provider'.scroll_in_preview(-1)<CR>" },
  }

  if type(action.open) == "table" then
    for _, key in ipairs(action.open) do
      table.insert(keymaps, { self.bufnr, "n", key, ":lua require'lspsaga.provider'.open_link(1)<CR>" })
    end
  elseif type(action.open) == "string" then
    table.insert(keymaps, { self.bufnr, "n", action.open, ":lua require'lspsaga.provider'.open_link(1)<CR>" })
  end

  if type(action.quit) == "table" then
    for _, key in ipairs(action.quit) do
      table.insert(keymaps, { self.bufnr, "n", key, ":lua require'lspsaga.provider'.close_lsp_finder_window()<CR>" })
    end
  elseif type(action.quit) == "string" then
    table.insert(
      keymaps,
      { self.bufnr, "n", action.quit, ":lua require'lspsaga.provider'.close_lsp_finder_window()<CR>" }
    )
  end
  nvim_create_keymap(keymaps, lhs)
end

function Finder:lsp_finder_highlight()
  local def_icon = config.finder_definition_icon or ""
  local ref_icon = config.finder_reference_icon or ""
  local def_uri_count = self.definition_uri == 0 and -1 or self.definition_uri
  -- add syntax
  api.nvim_buf_add_highlight(self.contents_buf, -1, "DefinitionIcon", 0, 1, #def_icon - 1)
  api.nvim_buf_add_highlight(self.contents_buf, -1, "TargetWord", 0, #def_icon, self.param_length + #def_icon + 3)
  api.nvim_buf_add_highlight(self.contents_buf, -1, "DefinitionCount", 0, 0, -1)
  api.nvim_buf_add_highlight(
    self.contents_buf,
    -1,
    "TargetWord",
    3 + def_uri_count,
    #ref_icon,
    self.param_length + #ref_icon + 3
  )
  api.nvim_buf_add_highlight(self.contents_buf, -1, "ReferencesIcon", 3 + def_uri_count, 1, #ref_icon + 4)
  api.nvim_buf_add_highlight(self.contents_buf, -1, "ReferencesCount", 3 + def_uri_count, 0, -1)
end

function Finder:set_cursor()
  local current_line = vim.fn.line "."
  local column = 2

  local first_def_uri_lnum = self.definition_uri ~= 0 and 3 or 5
  local last_def_uri_lnum = 3 + self.definition_uri - 1
  local first_ref_uri_lnum = 3 + self.definition_uri + 3
  local count = self.definition_uri == 0 and 1 or 2
  local last_ref_uri_lnum = 3 + self.definition_uri + count + self.reference_uri

  if current_line == 1 then
    vim.fn.cursor(first_def_uri_lnum, column)
  elseif current_line == last_def_uri_lnum + 1 then
    vim.fn.cursor(first_ref_uri_lnum, column)
  elseif current_line == last_ref_uri_lnum + 1 then
    vim.fn.cursor(first_def_uri_lnum, column)
  elseif current_line == first_ref_uri_lnum - 1 then
    if self.definition_uri == 0 then
      vim.fn.cursor(first_def_uri_lnum, column)
    else
      vim.fn.cursor(last_def_uri_lnum, column)
    end
  elseif current_line == first_def_uri_lnum - 1 then
    vim.fn.cursor(last_ref_uri_lnum, column)
  end
end

function Finder:get_cursorline_highlight()
  self.cursor_line_bg = vfn.synIDattr(vfn.hlID "cursorline", "bg")
  self.cursor_line_fg = vfn.synIDattr(vfn.hlID "cursorline", "fg")
end

function Finder:auto_open_preview()
  local current_line = vim.fn.line "."
  if not self.short_link[current_line] then
    return
  end
  local content = self.short_link[current_line].preview or {}

  if next(content) ~= nil then
    local has_var, finder_win_opts = pcall(api.nvim_win_get_var, 0, "lsp_finder_win_opts")
    if not has_var then
      print "get finder window options wrong"
      return
    end
    local opts = {
      relative = "editor",
      -- We'll make sure the preview window is the correct size
      no_size_override = true,
    }

    local finder_width = vim.fn.winwidth(0)
    local finder_height = vim.fn.winheight(0)
    local screen_width = api.nvim_get_option "columns"

    local content_width = 0
    for _, line in ipairs(content) do
      content_width = math.max(vim.fn.strdisplaywidth(line), content_width)
    end

    local border_width
    if config.border_style == "double" then
      border_width = 4
    else
      border_width = 2
    end

    local max_width = screen_width - finder_win_opts.col - finder_width - border_width - 2

    if max_width > 42 then
      -- Put preview window to the right of the finder window
      local preview_width = math.min(content_width + border_width, max_width)
      opts.col = finder_win_opts.col + finder_width + 2
      opts.row = finder_win_opts.row
      opts.width = preview_width
      opts.height = self.definition_uri + self.reference_uri + 6
      if opts.height > finder_height then
        opts.height = finder_height
      end
    else
      -- Put preview window below the finder window
      local max_height = self.WIN_HEIGHT - finder_win_opts.row - finder_height - border_width - 2
      if max_height <= 3 then
        return
      end -- Don't show preview window if too short

      opts.row = finder_win_opts.row + finder_height + 2
      opts.col = finder_win_opts.col
      opts.width = finder_width
      opts.height = math.min(8, max_height)
    end

    local content_opts = {
      contents = content,
      filetype = self.buf_filetype,
      highlight = "LspSagaAutoPreview",
    }

    vim.defer_fn(function()
      self:close_auto_preview_win()
      local bufnr, winid = window.create_win_with_border(content_opts, opts)
      api.nvim_buf_set_option(bufnr, "buflisted", false)
      api.nvim_win_set_var(0, "saga_finder_preview", { winid, 1, config.max_preview_lines + 1 })
    end, 10)
  end
end

function Finder:close_auto_preview_win()
  local has_var, pdata = pcall(api.nvim_win_get_var, 0, "saga_finder_preview")
  if has_var then
    window.nvim_close_valid_window(pdata[1])
  end
end

-- action 1 mean enter
-- action 2 mean vsplit
-- action 3 mean split
function Finder:open_link(action_type)
  local action = { "edit ", "vsplit ", "split " }
  local current_line = vim.fn.line "."

  if self.short_link[current_line] == nil then
    error "[LspSaga] target file uri not exist"
    return
  end

  self:close_auto_preview_win()
  api.nvim_win_close(self.winid, true)
  api.nvim_command(action[action_type] .. self.short_link[current_line].link)
  vim.fn.cursor(self.short_link[current_line].row, self.short_link[current_line].col)
  self:clear_tmp_data()
end

function Finder:scroll_in_preview(direction)
  local has_var, pdata = pcall(api.nvim_win_get_var, 0, "saga_finder_preview")
  if not has_var then
    return
  end
  if not api.nvim_win_is_valid(pdata[1]) then
    return
  end

  local current_win_lnum, last_lnum = pdata[3], pdata[4]
  current_win_lnum = scroll_in_win(pdata[1], direction, current_win_lnum, last_lnum, config.max_preview_lines)
  api.nvim_win_set_var(0, "saga_finder_preview", { pdata[1], current_win_lnum, last_lnum })
end

function Finder:quit_float_window()
  self:close_auto_preview_win()
  if self.winid ~= 0 then
    window.nvim_close_valid_window(self.winid)
  end
  self:clear_tmp_data()
end

function Finder:clear_tmp_data()
  self.short_link = {}
  self.contents = {}
  self.definition_uri = 0
  self.reference_uri = 0
  self.param_length = 0
  self.buf_filetype = ""
  self.WIN_HEIGHT = 0
  self.WIN_WIDTH = 0
  api.nvim_command("hi! CursorLine  guibg=" .. self.cursor_line_bg)
  if self.cursor_line_fg == "" then
    api.nvim_command "hi! CursorLine  guifg=NONE"
  end
end

local lspfinder = {}

function lspfinder.lsp_finder()
  local active, msg = libs.check_lsp_active()
  if not active then
    print(msg)
    return
  end
  local async_finder = Finder:lsp_finder_request()
  async_finder:send()
end

function lspfinder.close_lsp_finder_window()
  Finder:quit_float_window()
end

function lspfinder:auto_open_preview()
  Finder:auto_open_preview()
end

function lspfinder:set_cursor()
  Finder:set_cursor()
end

function lspfinder.open_link(action_type)
  Finder:open_link(action_type)
end

function lspfinder.scroll_in_preview(direction)
  Finder:scroll_in_preview(direction)
end

function lspfinder.preview_definition(timeout_ms)
  local active, msg = libs.check_lsp_active()
  if not active then
    print(msg)
    return
  end
  local filetype = vim.api.nvim_buf_get_option(0, "filetype")

  local method = "textDocument/definition"
  local params = lsp.util.make_position_params()
  local result = vim.lsp.buf_request_sync(0, method, params, timeout_ms or 1000)
  if result == nil or vim.tbl_isempty(result) then
    print("No location found: " .. method)
    return nil
  end

  if vim.tbl_islist(result) and not vim.tbl_isempty(result[1]) then
    local uri = result[1].result[1].uri or result[1].result[1].targetUri
    if #uri == 0 then
      return
    end
    local bufnr = vim.uri_to_bufnr(uri)
    local link = vim.uri_to_fname(uri)
    local short_name
    local root_dir = libs.get_lsp_root_dir()

    -- reduce filename length by root_dir or home dir
    if link:find(root_dir, 1, true) then
      short_name = link:sub(root_dir:len() + 2)
    elseif link:find(home_dir, 1, true) then
      short_name = link:sub(home_dir:len() + 2)
      -- some definition still has a too long path prefix
      if #short_name > 40 then
        short_name = libs.split_by_pathsep(short_name, 4)
      end
    else
      short_name = libs.split_by_pathsep(link, 4)
    end

    if not vim.api.nvim_buf_is_loaded(bufnr) then
      vim.fn.bufload(bufnr)
    end
    local range = result[1].result[1].targetRange or result[1].result[1].range
    local start_line = 0
    if range.start.line - 3 >= 1 then
      start_line = range.start.line - 3
    else
      start_line = range.start.line
    end

    local content = vim.api.nvim_buf_get_lines(
      bufnr,
      start_line,
      range["end"].line + 1 + config.max_preview_lines,
      false
    )
    content = vim.list_extend({
      config.definition_preview_icon .. "Definition Preview: " .. short_name,
      "",
    }, content)

    local opts = {
      relative = "cursor",
      style = "minimal",
    }

    local WIN_WIDTH = api.nvim_get_option "columns"
    local max_width = math.floor(WIN_WIDTH * 0.5)
    local width, _ = vim.lsp.util._make_floating_popup_size(content, opts)

    if width > max_width then
      opts.width = max_width
    end

    local content_opts = {
      contents = content,
      filetype = filetype,
      highlight = "LspSagaDefPreviewBorder",
    }

    local bf, wi = window.create_win_with_border(content_opts, opts)
    vim.lsp.util.close_preview_autocmd({ "CursorMoved", "CursorMovedI", "BufHidden", "BufLeave" }, wi)
    vim.api.nvim_buf_add_highlight(bf, -1, "DefinitionPreviewTitle", 0, 0, -1)

    api.nvim_buf_set_var(0, "lspsaga_def_preview", { wi, 1, config.max_preview_lines, 10 })
  end
end

function lspfinder.has_saga_def_preview()
  local has_preview, pdata = pcall(api.nvim_buf_get_var, 0, "lspsaga_def_preview")
  if has_preview and api.nvim_win_is_valid(pdata[1]) then
    return true
  end
  return false
end

function lspfinder.scroll_in_def_preview(direction)
  local has_preview, pdata = pcall(api.nvim_buf_get_var, 0, "lspsaga_def_preview")
  if not has_preview then
    return
  end
  local current_win_lnum = scroll_in_win(pdata[1], direction, pdata[2], config.max_preview_lines, pdata[4])
  api.nvim_buf_set_var(0, "lspsaga_def_preview", { pdata[1], current_win_lnum, config.max_preview_lines, pdata[4] })
end

return lspfinder
