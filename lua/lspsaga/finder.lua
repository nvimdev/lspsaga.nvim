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
  local support = false
  for _, client in pairs(lsp.get_active_clients({ bufnr = buf })) do
    if client.supports_method('textDocument/implementation') then
      support = true
      break
    end
  end
  return support
end

function finder:lsp_finder()
  -- push a tag stack
  local pos = api.nvim_win_get_cursor(0)
  self.current_word = fn.expand('<cword>')
  self.main_buf = api.nvim_get_current_buf()
  self.main_win = api.nvim_get_current_win()
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
      break
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
      if res.result and not (res.result.uri or res.result.targetUri) then
        libs.merge_table(result, res.result)
      elseif res.result and (res.result.uri or res.result.targetUri) then
        table.insert(result, res.result)
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

  self:get_file_icon()
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
  local contents = {}
  local title = get_titles(libs.tbl_index(methods(), method))
  insert(contents, { title .. '  ' .. #result, false })
  insert(contents, { ' ', false })

  if #result == 0 then
    insert(contents, { '    ' .. self.f_icon .. get_msg(method), false })
    insert(contents, { ' ', false })
    self.short_link[#contents - 1] = {
      content = { 'Sorry does not any Definition Found' },
      link = api.nvim_buf_get_name(0),
    }
    return contents
  end

  local root_dir = libs.get_lsp_root_dir()
  --ignore the FileType event avoid trigger the lsp
  vim.opt.eventignore:append({ 'FileType' })
  for _, res in ipairs(result) do
    local uri = res.targetUri or res.uri
    if not uri then
      vim.notify('miss uri in server response')
      return
    end
    local bufnr = vim.uri_to_bufnr(uri)
    local link = vim.uri_to_fname(uri) -- returns lowercase drive letters on Windows
    if not api.nvim_buf_is_loaded(bufnr) then
      -- ignore the FilType event
      fn.bufload(bufnr)
    end

    if libs.iswin then
      link = link:gsub('^%l', link:sub(1, 1):upper())
    end
    local short_name
    local path_sep = libs.path_sep
    -- reduce filename length by root_dir or home dir
    if root_dir and link:find(root_dir, 1, true) then
      short_name = link:sub(root_dir:len() + #libs.path_sep)
    else
      local _split = vim.split(link, path_sep)
      if #_split >= 4 then
        short_name = table.concat(_split, path_sep, #_split - 2, #_split)
      end
    end

    local target_line = '    ' .. self.f_icon .. short_name

    local range = res.targetRange or res.range

    local link_with_preview = {
      bufnr = bufnr,
      link = link,
      row = range.start.line,
      col = range.start.character,
      _end_col = range['end'].character,
    }

    insert(contents, { target_line, link_with_preview })
  end
  --restore eventignore
  vim.opt.eventignore:remove({ 'FileType' })
  insert(contents, { ' ', false })
  return contents
end

function finder:render_finder_result()
  --clean data
  self.request_result = nil
  self.request_status = nil

  if vim.tbl_isempty(self.contents) then
    return
  end

  local opt = {
    relative = 'win',
    width = window.get_max_content_length(self.contents),
  }

  local max_height = math.floor(vim.o.lines * config.finder.max_height)
  opt.height = #self.contents > max_height and max_height or #self.contents
  if opt.height <= 0 or not opt.height then
    opt.height = max_height
  end

  local winline = fn.winline()
  if vim.o.lines - 6 - opt.height - winline <= 0 then
    vim.cmd('normal! zz')
    local keycode = api.nvim_replace_termcodes('6<C-e>', true, false, true)
    api.nvim_feedkeys(keycode, 'x', false)
  end
  winline = fn.winline()
  opt.row = winline + 1
  opt.col = 10

  local side_char = window.border_chars()['top'][config.ui.border]
  local content_opts = {
    contents = self.contents,
    filetype = 'lspsagafinder',
    bufhidden = 'wipe',
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
  --clean contents
  self.contents = nil

  if fn.has('nvim-0.9') == 1 and config.ui.title then
    opt.title = {
      { ' ', 'TitleIcon' },
      { self.current_word, 'TitleString' },
    }
  end
  --clean
  self.current_word = nil

  self.bufnr, self.winid = window.create_win_with_border(content_opts, opt)
  api.nvim_win_set_option(self.winid, 'cursorline', false)

  -- make sure close preview window by using wincmd
  api.nvim_create_autocmd('WinClosed', {
    buffer = self.bufnr,
    once = true,
    callback = function()
      self:close_auto_preview_win()
    end,
  })

  self:set_cursor()

  api.nvim_create_autocmd('CursorMoved', {
    buffer = self.bufnr,
    callback = function()
      self:set_cursor()
      self:auto_open_preview()
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
      api.nvim_buf_add_highlight(self.bufnr, -1, self.f_hl, i, 0, 4 + #self.f_icon)
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
        api.nvim_buf_add_highlight(self.bufnr, -1, self.f_hl, i, 0, 4 + #self.f_icon)
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
      api.nvim_buf_add_highlight(self.bufnr, -1, self.f_hl, i, 0, 4 + #self.f_icon)
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

  --clean
  self.f_hl = nil

  -- disable some move keys in finder window
  libs.disable_move_keys(self.bufnr)
  -- load float window map
  self:apply_map()
  self:lsp_finder_highlight()
end

local function unpack_map()
  local map = {}
  for k, v in pairs(config.finder.keys) do
    if k ~= 'jump_to' then
      map[k] = v
    end
  end
  return map
end

function finder:apply_map()
  local opts = {
    buffer = self.bufnr,
    nowait = true,
    silent = true,
  }
  local unpacked = unpack_map()

  for action, map in pairs(unpacked) do
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

  for _, key in pairs(config.finder.keys.quit) do
    vim.keymap.set('n', key, function()
      pcall(api.nvim_buf_clear_namespace, self.preview_bufnr, self.preview_hl_ns, 0, -1)
      window.nvim_close_valid_window({ self.winid, self.preview_winid })
    end, opts)
  end

  vim.keymap.set('n', config.finder.keys.jump_to, function()
    if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
      api.nvim_set_current_win(self.preview_winid)
    end
  end, opts)
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
  local column = 5 + #self.f_icon

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
    api.nvim_buf_add_highlight(0, finder_ns, 'finderSelection', 2, 4 + #self.f_icon, -1)
  end

  api.nvim_buf_clear_namespace(0, finder_ns, 0, -1)
  api.nvim_buf_add_highlight(0, finder_ns, 'finderSelection', actual_line - 1, 4 + #self.f_icon, -1)
end

function finder:auto_open_preview()
  self:close_auto_preview_win()
  local current_line = api.nvim_win_get_cursor(0)[1]
  if not self.short_link[current_line] then
    return
  end

  local data = self.short_link[current_line]

  local opts = {
    relative = 'win',
    win = self.main_win,
    no_size_override = true,
  }

  local winconfig = api.nvim_win_get_config(self.winid)
  opts.col = winconfig.col[false] + winconfig.width + 2
  opts.row = winconfig.row[false]
  opts.height = winconfig.height
  local max_width = api.nvim_win_get_width(self.main_win) - opts.col - 4
  local textwidth = vim.bo[self.main_buf].textwidth == 0 and 80 or vim.bo[self.main_buf].textwidth
  opts.width = max_width > textwidth and textwidth or max_width

  local rtop = window.combine_char()['righttop'][config.ui.border]
  local rbottom = window.combine_char()['rightbottom'][config.ui.border]
  local content_opts = {
    contents = data.content or {},
    bufnr = data.bufnr or nil,
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
    local path = vim.split(self.short_link[current_line].link, libs.path_sep, { trimempty = true })
    opts.title = {
      { path[#path], 'TitleString' },
    }
    local icon_data = libs.icon_from_devicon(vim.bo[self.main_buf].filetype)
    if #icon_data > 0 then
      table.insert(opts.title, 1, { icon_data[1] .. ' ', icon_data[2] })
    end
  end

  vim.defer_fn(function()
    -- opts.noautocmd = true
    self.preview_bufnr, self.preview_winid = window.create_win_with_border(content_opts, opts)
    vim.bo[self.preview_bufnr].filetype = vim.bo[self.main_buf].filetype
    self.wipe_buffers = {}

    if #fn.win_findbuf(data.bufnr) == 1 then
      api.nvim_buf_call(data.bufnr, function()
        pcall(vim.cmd, 'TSBufEnable highlight')
      end)
      table.insert(self.wipe_buffers, data.bufnr)
    end

    if data.row then
      api.nvim_win_set_cursor(self.preview_winid, { data.row + 1, data.col })
    end

    libs.scroll_in_preview(self.bufnr, self.preview_winid)

    if not self.preview_hl_ns then
      self.preview_hl_ns = api.nvim_create_namespace('finderPreview')
    end

    if data.row then
      api.nvim_buf_add_highlight(
        self.preview_bufnr,
        self.preview_hl_ns,
        'finderPreviewSearch',
        data.row,
        data.col,
        data._end_col
      )
    end
  end, 10)
end

function finder:close_auto_preview_win()
  if self.preview_hl_ns then
    pcall(api.nvim_buf_clear_namespace, self.preview_bufnr, self.preview_hl_ns, 0, -1)
  end

  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    api.nvim_win_close(self.preview_winid, true)
    self.preview_winid = nil
  end
end

function finder:open_link(action)
  local current_line = api.nvim_win_get_cursor(0)[1]

  if not self.short_link[current_line] then
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
  api.nvim_win_set_cursor(0, { short_link[current_line].row + 1, short_link[current_line].col })
  local width = #api.nvim_get_current_line()
  libs.jump_beacon({ short_link[current_line].row, 0 }, width)
  self:clear_tmp_data()
end

function finder:quit_float_window()
  pcall(api.nvim_buf_clear_namespace, self.preview_bufnr, self.preview_hl_ns, 0, -1)
  self:close_auto_preview_win()
  for _, buf in pairs(self.wipe_buffers or {}) do
    if api.nvim_buf_is_loaded(buf) then
      api.nvim_buf_delete(buf, { force = true })
    end
  end

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
