local api, lsp, fn, uv = vim.api, vim.lsp, vim.fn, vim.loop
local config = require('lspsaga').config
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')
local insert = table.insert

local finder = {}
local ctx = {}

finder.__index = finder
finder.__newindex = function(t, k, v)
  rawset(t, k, v)
end

local function get_titles(index)
  local t = {
    '● Definition',
    '● Implements',
    '● References',
  }
  return t[index]
end

local function methods(index)
  local t = {
    'textDocument/definition',
    'textDocument/implementation',
    'textDocument/references',
  }

  return index and t[index] or t
end

local function supports_implement(buf)
  local support = {}
  for _, client in pairs(lsp.get_active_clients({ bufnr = buf })) do
    if not client.supports_method(methods(2)) then
      table.insert(support, false)
    end
  end
  if vim.tbl_contains(support, false) then
    return false
  end
  return true
end

function finder:lsp_finder()
  -- push a tag stack
  local pos = api.nvim_win_get_cursor(0)
  self.current_word = fn.expand('<cword>')
  self.main_buf = api.nvim_get_current_buf()
  local from = { self.main_buf, pos[1], pos[2], 0 }
  local items = { { tagname = self.current_word, from = from } }
  fn.settagstack(api.nvim_get_current_win(), { items = items }, 't')

  self.request_result = {}
  self.request_status = {}

  local params = lsp.util.make_position_params()
  ---@diagnostic disable-next-line: param-type-mismatch
  local meths = methods()
  if not supports_implement(self.main_buf) then
    self.request_result[meths[2]] = {}
    self.request_status[meths[2]] = true
    ---@diagnostic disable-next-line: param-type-mismatch
    table.remove(meths, 2)
  end
  ---@diagnostic disable-next-line: param-type-mismatch
  for _, method in pairs(meths) do
    self:do_request(params, method)
  end
  -- make a spinner
  self:loading_bar()
end

function finder:request_done()
  local done = true
  ---@diagnostic disable-next-line: param-type-mismatch
  for _, method in pairs(methods()) do
    if not self.request_status[method] then
      done = false
    end
  end
  return done
end

function finder:loading_bar()
  local opts = {
    relative = 'cursor',
    height = 2,
    width = 20,
  }

  local content_opts = {
    contents = {},
    buftype = 'nofile',
    border = 'solid',
    highlight = {
      normal = 'finderNormal',
      border = 'finderBorder',
    },
    enter = false,
  }

  local spin_buf, spin_win = window.create_win_with_border(content_opts, opts)
  local spin_config = {
    spinner = {
      '█▁▁▁▁▁▁▁▁▁',
      '██▁▁▁▁▁▁▁▁',
      '███▁▁▁▁▁▁▁',
      '████▁▁▁▁▁▁',
      '█████▁▁▁▁▁',
      '██████▁▁▁▁',
      '███████▁▁▁',
      '████████▁▁ ',
      '█████████▁',
      '██████████',
    },
    interval = 50,
    timeout = config.request_timeout,
  }
  api.nvim_buf_set_option(spin_buf, 'modifiable', true)

  local spin_frame = 1
  local spin_timer = uv.new_timer()
  local start_request = uv.now()
  spin_timer:start(
    0,
    spin_config.interval,
    vim.schedule_wrap(function()
      spin_frame = spin_frame == 11 and 1 or spin_frame
      local msg = ' LOADING' .. string.rep('.', spin_frame > 3 and 3 or spin_frame)
      local spinner = ' ' .. spin_config.spinner[spin_frame]
      pcall(api.nvim_buf_set_lines, spin_buf, 0, -1, false, { msg, spinner })
      pcall(api.nvim_buf_add_highlight, spin_buf, 0, 'finderSpinnerTitle', 0, 0, -1)
      pcall(api.nvim_buf_add_highlight, spin_buf, 0, 'finderSpinner', 1, 0, -1)
      spin_frame = spin_frame + 1

      if uv.now() - start_request >= spin_config.timeout and not spin_timer:is_closing() then
        spin_timer:stop()
        spin_timer:close()
        if api.nvim_buf_is_loaded(spin_buf) then
          api.nvim_buf_delete(spin_buf, { force = true })
        end
        window.nvim_close_valid_window(spin_win)
        vim.notify('request timeout')
        return
      end

      if self:request_done() and not spin_timer:is_closing() then
        spin_timer:stop()
        spin_timer:close()
        if api.nvim_buf_is_loaded(spin_buf) then
          api.nvim_buf_delete(spin_buf, { force = true })
        end
        window.nvim_close_valid_window(spin_win)
        self:render_finder()
      end
    end)
  )
end

function finder:do_request(params, method)
  if method == methods(3) then
    params.context = { includeDeclaration = true }
  end
  lsp.buf_request_all(self.current_buf, method, params, function(results)
    local result = {}
    for _, res in pairs(results or {}) do
      if res.result then
        libs.merge_table(result, res.result)
      end
    end

    self.request_result[method] = result
    self.request_status[method] = true
  end)
end

function finder:get_file_icon()
  local res = libs.icon_from_devicon(vim.bo[self.main_buf].filetype)
  if #res == 0 then
    self.f_icon = ''
  else
    self.f_icon = res[1] .. ' '
    self.f_hl = res[2]
  end
end

function finder:get_uri_scope(method, start_lnum, end_lnum)
  if method == methods(1) then
    self.def_scope = { start_lnum, end_lnum }
  end

  if method == methods(2) then
    self.imp_scope = { start_lnum, end_lnum }
  end

  if method == methods(3) then
    self.ref_scope = { start_lnum, end_lnum }
  end
end

function finder:render_finder()
  self.root_dir = libs.get_lsp_root_dir()
  self.short_link = {}
  self.contents = {}

  local lnum, start_lnum = 0, 0

  local generate_contents = function(tbl, method)
    if not tbl then
      return
    end
    start_lnum = lnum
    for _, val in pairs(tbl) do
      insert(self.contents, val[1])
      lnum = lnum + 1

      if val[2] then
        self.short_link[lnum] = val[2]
      end
    end
    self:get_uri_scope(method, start_lnum, lnum - 1)
  end

  ---@diagnostic disable-next-line: param-type-mismatch
  for i, method in pairs(methods()) do
    if i == 2 and #self.request_result[method] == 0 then
      goto skip
    end
    local tbl = self:create_finder_contents(self.request_result[method], method)
    generate_contents(tbl, method)
    ::skip::
  end
  self:render_finder_result()
end

local function get_msg(method)
  local idx = libs.tbl_index(methods(), method)
  local t = {
    'No Definition Found',
    'No Implement  Found',
    'No Reference  Found',
  }
  return t[idx]
end

function finder:create_finder_contents(result, method)
  self:get_file_icon()

  local contents = {}
  local title = get_titles(libs.tbl_index(methods(), method))
  insert(contents, { title .. '  ' .. #result, false })
  insert(contents, { ' ', false })
  self.indent = '    '

  if #result == 0 then
    insert(contents, { self.indent .. self.f_icon .. get_msg(method), false })
    insert(contents, { ' ', false })
    self.short_link[#contents - 1] = {
      preview = {'Sorry not result found'},
      link = api.nvim_buf_get_name(self.main_buf),
    }
    return contents
  end

  for _, res in ipairs(result) do
    local uri = res.targetUri or res.uri
    if uri == nil then
      vim.notify('miss uri in server response')
      return
    end
    local bufnr = vim.uri_to_bufnr(uri)
    local link = vim.uri_to_fname(uri) -- returns lowercase drive letters on Windows
    if not api.nvim_buf_is_loaded(bufnr) then
      --TODO: find a better way to avoid trigger autocmd
      vim.opt.eventignore:append({ 'BufRead', 'BufReadPost', 'BufEnter', 'FileType' })
      fn.bufload(bufnr)
      vim.opt.eventignore:remove({ 'BufRead', 'BufReadPost', 'BufEnter', 'FileType' })
    end

    if libs.iswin then
      link = link:gsub('^%l', link:sub(1, 1):upper())
    end
    local short_name
    local path_sep = libs.path_sep
    -- reduce filename length by root_dir or home dir
    if self.root_dir and link:find(self.root_dir, 1, true) then
      short_name = link:sub(self.root_dir:len() + 2)
    else
      local _split = vim.split(link, path_sep)
      if #_split >= 4 then
        short_name = table.concat(_split, path_sep, #_split - 2, #_split)
      end
    end

    local target_line = self.indent .. self.f_icon .. short_name

    local range = res.targetRange or res.range
    local lines = api.nvim_buf_get_lines(
      bufnr,
      range.start.line - config.preview.lines_above,
      range['end'].line + 1 + config.preview.lines_below,
      false
    )

    local link_with_preview = {
      link = link,
      preview = lines,
      row = range.start.line + 1,
      col = range.start.character + 1,
      _end_col = range['end'].character,
    }
    insert(contents, { target_line, link_with_preview })
    if bufnr ~= self.main_buf then
      api.nvim_buf_delete(bufnr, { force = true })
    end
  end
  insert(contents, { ' ', false })
  return contents
end

function finder:render_finder_result()
  if next(self.contents) == nil then
    return
  end

  local opt = {
    relative = 'editor',
    width = window.get_max_content_length(self.contents),
  }

  local max_height = vim.o.lines * 0.5
  opt.height = #self.contents > max_height and max_height or #self.contents

  local winline = fn.winline()
  if vim.o.lines - 6 - opt.height - winline <= 0 then
    vim.cmd('normal! zz')
    local keycode = api.nvim_replace_termcodes('6<C-e>', true, false, true)
    api.nvim_feedkeys(keycode, 'x', false)
  end
  winline = fn.winline()
  opt.row = winline + 2
  opt.col = 10

  local side_char = window.border_chars()['top'][config.ui.border]
  local content_opts = {
    contents = self.contents,
    filetype = 'lspsagafinder',
    enter = true,
    border_side = {
      ['right'] = ' ',
      ['righttop'] = side_char,
      ['rightbottom'] = side_char,
    },
    highlight = {
      border = 'finderBorder',
      normal = 'finderNormal',
    },
  }

  if fn.has('nvim-0.9') == 1 and config.ui.title then
    opt.title = {
      { ' ', 'TitleIcon' },
      { self.current_word, 'TitleString' },
    }
  end

  self.bufnr, self.winid = window.create_win_with_border(content_opts, opt)
  api.nvim_buf_set_option(self.bufnr, 'buflisted', false)
  api.nvim_win_set_option(self.winid, 'cursorline', false)

  self:set_cursor()

  local finder_group = api.nvim_create_augroup('lspsaga_finder', { clear = true })
  api.nvim_create_autocmd('CursorMoved', {
    group = finder_group,
    buffer = self.bufnr,
    callback = function()
      self:set_cursor()
      self:auto_open_preview()
    end,
  })

  local events = { 'WinClosed', 'WinLeave' }

  api.nvim_create_autocmd(events, {
    group = finder_group,
    buffer = self.bufnr,
    callback = function()
      self:quit_with_clear()
      if finder_group then
        pcall(api.nvim_del_augroup_by_id, finder_group)
      end
      -- make sure close all finder preview window
      for _, win in pairs(api.nvim_list_wins()) do
        local ok, id = pcall(api.nvim_win_get_var, win, 'finder_preview')
        if ok then
          pcall(api.nvim_win_close, id, true)
        end
      end
    end,
  })

  local virt_hi = 'finderVirtText'

  local ns_id = api.nvim_create_namespace('lspsagafinder')
  api.nvim_buf_set_extmark(0, ns_id, 1, 0, {
    virt_text = { { '│', virt_hi } },
    virt_text_pos = 'overlay',
  })

  for i = self.def_scope[1] + 2, self.def_scope[2] - 1, 1 do
    local virt_texts = {}
    api.nvim_buf_add_highlight(self.bufnr, -1, 'finderFileName', 1 + i, 0, -1)
    if self.f_hl then
      api.nvim_buf_add_highlight(self.bufnr, -1, self.f_hl, i, 0, #self.indent + #self.f_icon)
    end

    if i == self.def_scope[2] - 1 then
      insert(virt_texts, { '└', virt_hi })
      insert(virt_texts, { '───', virt_hi })
    else
      insert(virt_texts, { '├', virt_hi })
      insert(virt_texts, { '───', virt_hi })
    end

    api.nvim_buf_set_extmark(0, ns_id, i, 0, {
      virt_text = virt_texts,
      virt_text_pos = 'overlay',
    })
  end

  if self.imp_scope then
    api.nvim_buf_set_extmark(0, ns_id, self.imp_scope[1] + 1, 0, {
      virt_text = { { '│', virt_hi } },
      virt_text_pos = 'overlay',
    })

    for i = self.imp_scope[1] + 2, self.imp_scope[2] - 1, 1 do
      local virt_texts = {}
      api.nvim_buf_add_highlight(self.bufnr, -1, 'TargetFileName', 1 + i, 0, -1)
      if self.f_hl then
        api.nvim_buf_add_highlight(self.bufnr, -1, self.f_hl, i, 0, #self.indent + #self.f_icon)
      end

      if i == self.imp_scope[2] - 1 then
        insert(virt_texts, { '└', virt_hi })
        insert(virt_texts, { '───', virt_hi })
      else
        insert(virt_texts, { '├', virt_hi })
        insert(virt_texts, { '───', virt_hi })
      end

      api.nvim_buf_set_extmark(0, ns_id, i, 0, {
        virt_text = virt_texts,
        virt_text_pos = 'overlay',
      })
    end
  end

  api.nvim_buf_set_extmark(0, ns_id, self.ref_scope[1] + 1, 0, {
    virt_text = { { '│', virt_hi } },
    virt_text_pos = 'overlay',
  })

  for i = self.ref_scope[1] + 2, self.ref_scope[2] - 1 do
    local virt_texts = {}
    api.nvim_buf_add_highlight(self.bufnr, -1, 'TargetFileName', i, 0, -1)
    if self.f_hl then
      api.nvim_buf_add_highlight(self.bufnr, -1, self.f_hl, i, 0, #self.indent + #self.f_icon)
    end

    if i == self.ref_scope[2] - 1 then
      insert(virt_texts, { '└', virt_hi })
      insert(virt_texts, { '───', virt_hi })
    else
      insert(virt_texts, { '├', virt_hi })
      insert(virt_texts, { '───', virt_hi })
    end

    api.nvim_buf_set_extmark(0, ns_id, i, 0, {
      virt_text = virt_texts,
      virt_text_pos = 'overlay',
    })
  end
  -- disable some move keys in finder window
  libs.disable_move_keys(self.bufnr)
  -- load float window map
  self:apply_map()
  self:lsp_finder_highlight()
end

function finder:apply_map()
  local opts = {
    buffer = true,
    nowait = true,
  }

  for action, map in pairs(config.finder) do
    if type(map) == 'string' then
      map = { map }
    end
    for _, key in pairs(map) do
      if key ~= 'quit' then
        vim.keymap.set('n', key, function()
          self:open_link(action)
        end, opts)
      end
    end
  end

  for _, key in pairs(config.finder.quit) do
    vim.keymap.set('n', key, function()
      window.nvim_close_valid_window({ self.winid, self.preview_winid })
    end, opts)
  end
end

function finder:lsp_finder_highlight()
  local len = string.len('Definition')

  for _, v in pairs({ 0, self.ref_scope[1], self.imp_scope and self.imp_scope[1] or nil }) do
    api.nvim_buf_add_highlight(self.bufnr, -1, 'FinderIcon', v, 0, 3)
    api.nvim_buf_add_highlight(self.bufnr, -1, 'FinderType', v, 4, 4 + len)
    api.nvim_buf_add_highlight(self.bufnr, -1, 'FinderCount', v, 4 + len, -1)
  end
end

local finder_ns = api.nvim_create_namespace('finder_select')

function finder:set_cursor()
  local current_line = api.nvim_win_get_cursor(0)[1]
  local column = #self.indent + #self.f_icon + 1

  local first_def_uri_lnum = self.def_scope[1] + 3
  local last_def_uri_lnum = self.def_scope[2]
  local first_ref_uri_lnum = self.ref_scope[1] + 3
  local last_ref_uri_lnum = self.ref_scope[2]

  local first_imp_uri_lnum = self.imp_scope and self.imp_scope[1] + 3 or -2
  local last_imp_uri_lnum = self.imp_scope and self.imp_scope[2] or -2

  if current_line == 1 then
    fn.cursor(first_def_uri_lnum, column)
  elseif current_line == last_def_uri_lnum + 1 then
    fn.cursor(first_imp_uri_lnum > 0 and first_imp_uri_lnum or first_ref_uri_lnum, column)
  elseif current_line == last_imp_uri_lnum + 1 then
    fn.cursor(first_ref_uri_lnum, column)
  elseif current_line == last_ref_uri_lnum + 1 then
    fn.cursor(first_def_uri_lnum, column)
  elseif current_line == first_ref_uri_lnum - 1 then
    fn.cursor(last_imp_uri_lnum > 0 and last_imp_uri_lnum or last_def_uri_lnum, column)
  elseif current_line == first_imp_uri_lnum - 1 then
    fn.cursor(last_def_uri_lnum, column)
  elseif current_line == first_def_uri_lnum - 1 then
    fn.cursor(last_ref_uri_lnum, column)
  end

  local actual_line = api.nvim_win_get_cursor(0)[1]
  if actual_line == first_def_uri_lnum then
    api.nvim_buf_add_highlight(0, finder_ns, 'finderSelection', 2, #self.indent + #self.f_icon, -1)
  end

  api.nvim_buf_clear_namespace(0, finder_ns, 0, -1)
  api.nvim_buf_add_highlight(
    0,
    finder_ns,
    'finderSelection',
    actual_line - 1,
    #self.indent + #self.f_icon,
    -1
  )
end

function finder:auto_open_preview()
  local current_line = fn.line('.')
  if not self.short_link[current_line] then
    return
  end

  local content
  local table_length = vim.tbl_count(self.short_link[current_line].preview)

  if
    table_length == 0 or (self.short_link[current_line].preview[1] == '' and table_length == 1)
  then
    content = { 'the file is empty' }
  else
    content = self.short_link[current_line].preview
  end

  local start_pos = self.short_link[current_line].col
  local _end_col = self.short_link[current_line]._end_col

  if next(content) ~= nil then
    local opts = {
      relative = 'editor',
      -- We'll make sure the preview window is the correct size
      no_size_override = true,
    }

    local winconfig = api.nvim_win_get_config(self.winid)
    opts.col = winconfig.col[false] + winconfig.width + 2
    opts.row = winconfig.row[false]
    opts.height = winconfig.height
    local max_width = vim.o.columns - opts.col - 4
    local max_len = window.get_max_content_length(content)
    opts.width = max_width > max_len and max_len or max_width

    local rtop = window.combine_char()['righttop'][config.ui.border]
    local rbottom = window.combine_char()['rightbottom'][config.ui.border]
    local content_opts = {
      contents = content,
      buftype = 'nofile',
      border_side = {
        ['lefttop'] = rtop,
        ['leftbottom'] = rbottom,
      },
      highlight = {
        border = 'finderPreviewBorder',
        normal = 'finderNormal',
      },
    }

    if fn.has('nvim-0.9') == 1 and config.ui.title then
      local path =
        vim.split(self.short_link[current_line].link, libs.path_sep, { trimempty = true })
      opts.title = {
        { path[#path], 'TitleString' },
      }
      local icon_data = libs.icon_from_devicon(vim.bo[self.main_buf].filetype)
      if #icon_data > 0 then
        table.insert(opts.title, 1, { icon_data[1] .. ' ', icon_data[2] })
      end
    end

    self:close_auto_preview_win()

    vim.defer_fn(function()
      opts.noautocmd = true
      self.preview_bufnr, self.preview_winid = window.create_win_with_border(content_opts, opts)
      vim.bo[self.preview_bufnr].filetype = vim.bo[self.main_buf].filetype
      api.nvim_buf_set_option(self.preview_bufnr, 'buflisted', false)
      api.nvim_win_set_var(self.preview_winid, 'finder_preview', self.preview_winid)

      libs.scroll_in_preview(self.bufnr, self.preview_winid)

      if not self.preview_hl_ns then
        self.preview_hl_ns = api.nvim_create_namespace('finderPreview')
      end
      local trimLines = 0
      for _, v in pairs(content) do
        if v == '' then
          trimLines = trimLines + 1
        else
          break
        end
      end

      if not start_pos then
        return
      end

      if 0 + config.preview.lines_above - trimLines >= 0 then
        api.nvim_buf_add_highlight(
          self.preview_bufnr,
          self.preview_hl_ns,
          'finderPreviewSearch',
          0 + config.preview.lines_above - trimLines,
          start_pos - 1,
          _end_col
        )
      end
    end, 10)
  end
end

function finder:close_auto_preview_win()
  if self.preview_hl_ns then
    pcall(api.nvim_buf_clear_namespace, self.preview_bufnr, self.preview_hl_ns, 0, -1)
  end
  if self.preview_bufnr and api.nvim_buf_is_loaded(self.preview_bufnr) then
    api.nvim_buf_delete(self.preview_bufnr, { force = true })
    self.preview_bufnr = nil
  end

  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    api.nvim_win_close(self.preview_winid, true)
    self.preview_winid = nil
  end
end

function finder:open_link(action)
  local current_line = api.nvim_win_get_cursor(0)[1]

  if self.short_link[current_line] then
    vim.notify('[LspSaga] no file link in current line', vim.log.levels.WARN)
    return
  end

  local short_link = self.short_link
  self:quit_float_window()

  -- if buffer not saved save it before jump
  if vim.bo.modified then
    vim.cmd('write')
  end
  vim.cmd(action .. ' ' .. uv.fs_realpath(short_link[current_line].link))
  api.nvim_win_set_cursor(0, { short_link[current_line].row, short_link[current_line].col - 1 })
  local width = #api.nvim_get_current_line()
  libs.jump_beacon({ short_link[current_line].row - 1, 0 }, width)
  self:clear_tmp_data()
end

function finder:quit_float_window()
  if self.bufnr and api.nvim_buf_is_loaded(self.bufnr) then
    api.nvim_buf_delete(self.bufnr, { force = true })
    self.bufnr = nil
  end

  self:close_auto_preview_win()
  if self.winid and self.winid > 0 then
    window.nvim_close_valid_window(self.winid)
    self.winid = nil
  end
end

function finder:clear_tmp_data()
  for k, _ in pairs(ctx) do
    ctx[k] = nil
  end
end

function finder:quit_with_clear()
  self:quit_float_window()
  self:clear_tmp_data()
end

return setmetatable(ctx, finder)
