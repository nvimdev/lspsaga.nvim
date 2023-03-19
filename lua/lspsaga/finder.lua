local api, lsp, fn, uv = vim.api, vim.lsp, vim.fn, vim.loop
local config = require('lspsaga').config
local window = require('lspsaga.window')
local libs = require('lspsaga.libs')

local finder = {}
local ctx = {}

local function clean_ctx()
  for k, _ in pairs(ctx) do
    ctx[k] = nil
  end
end

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

local function get_file_icon(bufnr)
  local res = libs.icon_from_devicon(vim.bo[bufnr].filetype)
  return res
end

local function supports_implement(buf)
  local support = false
  for _, client in ipairs(lsp.get_active_clients({ bufnr = buf })) do
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
  for _, method in ipairs(meths) do
    self:do_request(params, method)
  end
  -- make a spinner
  self:loading_bar()
end

function finder:request_done()
  local done = true
  ---@diagnostic disable-next-line: param-type-mismatch
  for _, method in ipairs(methods()) do
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
      normal = 'FinderNormal',
      border = 'FinderBorder',
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
      pcall(api.nvim_buf_add_highlight, spin_buf, 0, 'FinderSpinnerTitle', 0, 0, -1)
      pcall(api.nvim_buf_add_highlight, spin_buf, 0, 'FinderSpinner', 1, 0, -1)
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
    for _, res in ipairs(results or {}) do
      if res.result and not (res.result.uri or res.result.targetUri) then
        libs.merge_table(result, res.result)
      elseif res.result and (res.result.uri or res.result.targetUri) then
        result[#result + 1] = res.result
      end
    end

    self.request_result[method] = result
    self.request_status[method] = true
  end)
end

local function keymap_tip()
  local function gen_str(key)
    if type(key) == 'table' then
      return key[1]
    end
    return key
  end
  local keys = config.finder.keys

  return {
    '[edit] '
      .. gen_str(keys.edit)
      .. ' [vsplit] '
      .. gen_str(keys.vsplit)
      .. ' [split] '
      .. gen_str(keys.split)
      .. ' [tabe] '
      .. gen_str(keys.tabe)
      .. ' [tabnew] '
      .. gen_str(keys.tabnew)
      .. ' [quit] '
      .. gen_str(keys.quit)
      .. ' [jump] '
      .. gen_str(keys.jump_to),
  }
end

function finder:render_finder()
  self.short_link = {}
  self.contents = {}
  self.wipe_buffers = {}

  local method_scopes = {}
  ---@diagnostic disable-next-line: param-type-mismatch
  for _, method in ipairs(methods()) do
    if #self.request_result[method] ~= 0 then
      local content = self:create_finder_contents(self.request_result[method], method)
      local start = #self.contents + 1
      for _, data in ipairs(content) do
        self.contents[#self.contents + 1] = data[1]
        if data[2] then
          self.short_link[#self.contents] = data[2]
        end
      end
      method_scopes[method] = { start, start + #content - 1 }
    end
  end
  --clean data
  self.request_result = nil
  self.request_status = nil
  self:render_finder_result(method_scopes)
end

local function get_msg(method)
  local idx = libs.tbl_index(methods(), method)
  local t = {
    'No Definition Found',
    'No Implementation  Found',
    'No Reference  Found',
  }
  return t[idx]
end

function finder:create_finder_contents(result, method)
  local contents = {}
  local title = get_titles(libs.tbl_index(methods(), method))
  contents[#contents + 1] = { title .. '  ' .. #result }

  local icon_data = get_file_icon(self.main_buf)
  if #result == 0 then
    contents[#contents + 1] = {
      '    ' .. icon_data[1] .. get_msg(method),
      {
        content = { 'No Content Found' },
        link = api.nvim_buf_get_name(0),
      },
    }
    contents[#contents + 1] = { ' ' }
    return contents
  end

  local wipe = false
  for _, res in ipairs(result) do
    local uri = res.targetUri or res.uri
    if not uri then
      vim.notify('miss uri in server response')
      return contents
    end
    local bufnr = vim.uri_to_bufnr(uri)
    local link = vim.uri_to_fname(uri) -- returns lowercase drive letters on Windows
    if not api.nvim_buf_is_loaded(bufnr) then
      wipe = true
      --ignore the FileType event avoid trigger the lsp
      vim.opt.eventignore:append({ 'FileType' })
      fn.bufload(bufnr)
      --restore eventignore
      vim.opt.eventignore:remove({ 'FileType' })
      if not vim.tbl_contains(self.wipe_buffers, bufnr) then
        self.wipe_buffers[#self.wipe_buffers + 1] = bufnr
      end
    end

    if libs.iswin then
      link = link:gsub('^%l', link:sub(1, 1):upper())
    end
    local short_name = table.concat(libs.get_path_info(bufnr, 2), libs.path_sep)

    local line = '    ' .. icon_data[1] .. short_name

    local range = res.targetRange or res.range

    local link_with_preview = {
      bufnr = bufnr,
      link = link,
      wipe = wipe,
      row = range.start.line,
      col = range.start.character,
      _end_col = range['end'].character,
    }

    contents[#contents + 1] = { line, link_with_preview }
  end
  contents[#contents + 1] = { ' ' }
  return contents
end

function finder:render_finder_result(method_scopes)
  if #self.contents == 0 then
    clean_ctx()
    return
  end

  self.group = api.nvim_create_augroup('lspsaga_finder', { clear = true })

  local opt = {
    relative = 'editor',
  }

  local max_height = math.floor(vim.o.lines * config.finder.max_height)
  opt.height = #self.contents > max_height and max_height or #self.contents
  if opt.height <= 0 or not opt.height or config.finder.force_max_height then
    opt.height = max_height
  end

  local winline = fn.winline()
  if vim.o.lines - 6 - opt.height - winline <= 0 then
    api.nvim_win_call(self.main_win, function()
      vim.cmd('normal! zz')
      local keycode = api.nvim_replace_termcodes('6<C-e>', true, false, true)
      api.nvim_feedkeys(keycode, 'x', false)
    end)
  end
  winline = fn.winline()
  opt.row = winline + 1
  local wincol = fn.wincol()
  opt.col = fn.screencol() - math.floor(wincol * 0.4)

  local side_char = window.border_chars()['top'][config.ui.border]
  local normal_right_side = ' '
  local content_opts = {
    contents = self.contents,
    filetype = 'lspsagafinder',
    bufhidden = 'wipe',
    enter = true,
    border_side = {
      ['right'] = config.ui.border == 'shadow' and '' or normal_right_side,
      ['righttop'] = config.ui.border == 'shadow' and '' or side_char,
      ['rightbottom'] = config.ui.border == 'shadow' and '' or side_char,
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

  self.restore_opts = window.restore_option()
  self.bufnr, self.winid = window.create_win_with_border(content_opts, opt)
  api.nvim_win_set_option(self.winid, 'cursorline', false)

  -- make sure close preview window by using wincmd
  api.nvim_create_autocmd('WinClosed', {
    buffer = self.bufnr,
    once = true,
    callback = function()
      local ok, buf = pcall(api.nvim_win_get_buf, self.preview_winid)
      if ok then
        pcall(api.nvim_buf_clear_namespace, buf, self.preview_hl_ns, 0, -1)
      end
      self:close_auto_preview_win()
      api.nvim_del_augroup_by_id(self.group)
      self:clean_data()
      clean_ctx()
    end,
  })

  opt.row = opt.row - 3
  local maptip = keymap_tip()
  opt.width = #maptip[1] > vim.o.columns and vim.o.columns or #maptip[1]
  opt.height = 1
  opt.no_size_override = true
  opt.title = nil
  opt.title_pos = nil
  opt.border = 'solid'

  if config.finder.show_tip then
    _, self.tip_winid = window.create_win_with_border({
      contents = maptip,
      bufhidden = 'wipe',
      highlight = {
        border = 'FinderBorder',
        normal = 'FinderNormal',
      },
    }, opt)
    api.nvim_win_call(self.tip_winid, function()
      self.match_ids = {}
      self.match_ids[#self.match_ids + 1] = vim.fn.matchadd('FinderTips', '\\[\\w\\+\\]')
    end)
  end

  local def_scope = method_scopes[methods(1)]
  local imp_scope = method_scopes[methods(2)]
  local ref_scope = method_scopes[methods(3)]

  self:set_cursor(def_scope, ref_scope, imp_scope)
  self:open_preview()

  api.nvim_create_autocmd('CursorMoved', {
    buffer = self.bufnr,
    callback = function()
      self:set_cursor(def_scope, ref_scope, imp_scope)
      self:open_preview()
    end,
  })

  local virt_hi = 'Finderlines'

  local ns_id = api.nvim_create_namespace('lspsagafinder')

  local icon, icon_hl = unpack(get_file_icon(self.main_buf))

  for i = def_scope[1] + 1, def_scope[2] - 1, 1 do
    local virt_texts = {}
    api.nvim_buf_add_highlight(self.bufnr, 0, 'FinderFileName', i - 1, 0, -1)
    if icon_hl then
      api.nvim_buf_add_highlight(self.bufnr, 0, icon_hl, i - 1, 0, 4 + #icon)
    end

    if i == def_scope[2] - 1 then
      virt_texts[#virt_texts + 1] = { '└', virt_hi }
      virt_texts[#virt_texts + 1] = { '───', virt_hi }
    else
      virt_texts[#virt_texts + 1] = { '├', virt_hi }
      virt_texts[#virt_texts + 1] = { '───', virt_hi }
    end

    api.nvim_buf_set_extmark(0, ns_id, i - 1, 0, {
      virt_text = virt_texts,
      virt_text_pos = 'overlay',
    })
  end

  if imp_scope then
    for i = imp_scope[1] + 1, imp_scope[2] - 1, 1 do
      local virt_texts = {}
      api.nvim_buf_add_highlight(self.bufnr, -1, 'FinderFileName', i - 1, 0, -1)
      if icon_hl then
        api.nvim_buf_add_highlight(self.bufnr, -1, icon_hl, i - 1, 0, 4 + #icon)
      end

      if i == imp_scope[2] - 1 then
        virt_texts[#virt_texts + 1] = { '└', virt_hi }
        virt_texts[#virt_texts + 1] = { '───', virt_hi }
      else
        virt_texts[#virt_texts + 1] = { '├', virt_hi }
        virt_texts[#virt_texts + 1] = { '───', virt_hi }
      end

      api.nvim_buf_set_extmark(0, ns_id, i - 1, 0, {
        virt_text = virt_texts,
        virt_text_pos = 'overlay',
      })
    end
  end

  api.nvim_buf_set_extmark(0, ns_id, ref_scope[1] + 1, 0, {
    virt_text = { { '│', virt_hi } },
    virt_text_pos = 'overlay',
  })

  for i = ref_scope[1] + 1, ref_scope[2] - 1 do
    local virt_texts = {}
    api.nvim_buf_add_highlight(self.bufnr, -1, 'FinderFileName', i - 1, 0, -1)
    if icon_hl then
      api.nvim_buf_add_highlight(self.bufnr, -1, icon_hl, i - 1, 0, 4 + #icon)
    end

    if i == ref_scope[2] - 1 then
      virt_texts[#virt_texts + 1] = { '└', virt_hi }
      virt_texts[#virt_texts + 1] = { '───', virt_hi }
    else
      virt_texts[#virt_texts + 1] = { '├', virt_hi }
      virt_texts[#virt_texts + 1] = { '───', virt_hi }
    end

    api.nvim_buf_set_extmark(0, ns_id, i - 1, 0, {
      virt_text = virt_texts,
      virt_text_pos = 'overlay',
    })
  end

  -- disable some move keys in finder window
  libs.disable_move_keys(self.bufnr)
  -- load float window map
  self:apply_map()
  local len = string.len('Definition')

  for _, v in ipairs({ def_scope[1] - 1, ref_scope[1] - 1, imp_scope and imp_scope[1] - 1 or nil }) do
    api.nvim_buf_add_highlight(self.bufnr, -1, 'FinderIcon', v, 0, 3)
    api.nvim_buf_add_highlight(self.bufnr, -1, 'FinderType', v, 4, 4 + len)
    api.nvim_buf_add_highlight(self.bufnr, -1, 'FinderCount', v, 4 + len, -1)
  end
end

local function unpack_map()
  local map = {}
  for k, v in pairs(config.finder.keys) do
    if k ~= 'jump_to' and k ~= 'close_in_preview' then
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
      local ok, buf = pcall(api.nvim_win_get_buf, self.preview_winid)
      if ok then
        pcall(api.nvim_buf_clear_namespace, buf, self.preview_hl_ns, 0, -1)
      end
      window.nvim_close_valid_window({ self.winid, self.preview_winid, self.tip_winid or nil })
      self:clean_data()
      clean_ctx()
    end, opts)
  end

  vim.keymap.set('n', config.finder.keys.jump_to, function()
    if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
      local lnum = api.nvim_win_get_cursor(0)[1]
      api.nvim_set_current_win(self.preview_winid)
      local data = self.short_link[lnum]
      if data then
        api.nvim_win_set_cursor(0, { data.row + 1, data.col })
      end
    end
  end, opts)
end

local finder_ns = api.nvim_create_namespace('finder_select')

function finder:set_cursor(def_scope, ref_scope, imp_scope)
  local current_line = api.nvim_win_get_cursor(0)[1]
  local icon = get_file_icon(self.main_buf)[1]
  local column = 4 + #icon

  local first_def_uri_lnum = def_scope[1] + 1
  local last_def_uri_lnum = def_scope[2] - 1
  local first_ref_uri_lnum = ref_scope[1] + 1
  local last_ref_uri_lnum = ref_scope[2] - 1

  local first_imp_uri_lnum = imp_scope and imp_scope[1] + 1 or -2
  local last_imp_uri_lnum = imp_scope and imp_scope[2] - 1 or -2

  local new_pos = {}

  if current_line == 1 then
    new_pos = { first_def_uri_lnum, column }
  elseif current_line == last_def_uri_lnum + 1 then
    new_pos = { first_imp_uri_lnum > 0 and first_imp_uri_lnum or first_ref_uri_lnum, column }
  elseif current_line == last_imp_uri_lnum + 1 then
    new_pos = { first_ref_uri_lnum, column }
  elseif current_line == last_ref_uri_lnum + 1 then
    new_pos = { first_def_uri_lnum, column }
  elseif current_line == first_ref_uri_lnum - 1 then
    new_pos = { last_imp_uri_lnum > 0 and last_imp_uri_lnum or last_def_uri_lnum, column }
  elseif current_line == first_imp_uri_lnum - 1 then
    new_pos = { last_def_uri_lnum, column }
  elseif current_line == first_def_uri_lnum - 1 then
    new_pos = { last_ref_uri_lnum, column }
  end

  if #new_pos > 0 then
    api.nvim_win_set_cursor(self.winid, new_pos)
  end

  local actual = api.nvim_win_get_cursor(0)[1] - 1
  if new_pos[1] == first_def_uri_lnum then
    api.nvim_buf_add_highlight(0, finder_ns, 'FinderSelection', actual, 4 + #icon, -1)
  end

  api.nvim_buf_clear_namespace(0, finder_ns, 0, -1)
  api.nvim_buf_add_highlight(0, finder_ns, 'FinderSelection', actual, 4 + #icon, -1)
end

local function create_preview_window(finder_winid)
  if not finder_winid or not api.nvim_win_is_valid(finder_winid) then
    return
  end

  local opts = {
    relative = 'editor',
    no_size_override = true,
  }

  local winconfig = api.nvim_win_get_config(finder_winid)
  opts.row = winconfig.row[false]
  opts.height = winconfig.height

  local border_side = {}
  local top = window.combine_char()['top'][config.ui.border]
  local bottom = window.combine_char()['bottom'][config.ui.border]

  --in right
  if vim.o.columns - winconfig.col[false] - winconfig.width > config.finder.min_width then
    local adjust = config.ui.border == 'shadow' and -2 or 2
    opts.col = winconfig.col[false] + winconfig.width + adjust
    opts.width = vim.o.columns - opts.col - 2
    border_side = {
      ['lefttop'] = top,
      ['leftbottom'] = bottom,
    }
  --in left
  elseif winconfig.col[false] > config.finder.min_width then
    opts.width = math.floor(winconfig.col[false] * 0.8)
    local adjust = config.ui.border == 'shadow' and -2 or 0
    opts.col = winconfig.col[false] - opts.width - adjust
    border_side = {
      ['righttop'] = top,
      ['rightbottom'] = bottom,
    }
    api.nvim_win_set_config(finder_winid, {
      border = window.combine_border(config.ui.border, {
        ['lefttop'] = '',
        ['left'] = '',
        ['leftbottom'] = '',
      }, 'FinderBorder'),
    })
  end

  local content_opts = {
    contents = {},
    border_side = border_side,
    bufhidden = '',
    highlight = {
      border = 'FinderPreviewBorder',
      normal = 'FinderNormal',
    },
  }

  return window.create_win_with_border(content_opts, opts)
end

local function clear_preview_ns(ns, buf)
  pcall(api.nvim_buf_clear_namespace, buf, ns, 0, -1)
end

function finder:open_preview()
  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    local before_buf = api.nvim_win_get_buf(self.preview_winid)
    clear_preview_ns(self.preview_hl_ns, before_buf)
  end

  local current_line = api.nvim_win_get_cursor(self.winid)[1]
  if not self.short_link[current_line] then
    return
  end

  local data = self.short_link[current_line]

  if not self.preview_winid or not api.nvim_win_is_valid(self.preview_winid) then
    self.preview_bufnr, self.preview_winid = create_preview_window(self.winid)
  end

  if not self.preview_winid then
    return
  end

  if data.content then
    if not data.bufnr then
      data.bufnr = self.preview_bufnr
    end
    api.nvim_win_set_buf(self.preview_winid, data.bufnr)
    api.nvim_set_option_value('bufhidden', '', { buf = self.preview_bufnr })
    vim.bo[self.preview_bufnr].modifiable = true
    api.nvim_buf_set_lines(self.preview_bufnr, 0, -1, false, data.content)
    vim.bo[self.preview_bufnr].modifiable = false
    return
  end

  if data.bufnr then
    api.nvim_win_set_buf(self.preview_winid, data.bufnr)
    if config.ui.title and fn.has('nvim-0.9') == 1 then
      local path = vim.split(data.link, libs.path_sep, { trimempty = true })
      local icon = get_file_icon(self.main_buf)
      api.nvim_win_set_config(self.preview_winid, {
        title = {
          { icon[1], icon[2] or 'TitleString' },
          { path[#path], 'TitleString' },
        },
        title_pos = 'center',
      })
    end
    api.nvim_set_option_value('winbar', '', { scope = 'local', win = self.preview_winid })
  end

  api.nvim_set_option_value(
    'winhl',
    'Normal:finderNormal,FloatBorder:finderPreviewBorder',
    { scope = 'local', win = self.preview_winid }
  )

  if data.row then
    api.nvim_win_set_cursor(self.preview_winid, { data.row + 1, data.col })
  end

  local lang = require('nvim-treesitter.parsers').ft_to_lang(vim.bo[self.main_buf].filetype)
  if fn.has('nvim-0.9') then
    vim.treesitter.start(data.bufnr, lang)
  else
    vim.bo[data.bufnr].syntax = 'on'
    pcall(
      ---@diagnostic disable-next-line: param-type-mismatch
      vim.cmd,
      string.format('syntax include %s syntax/%s.vim', '@' .. lang, vim.bo[self.main_buf].filetype)
    )
  end

  libs.scroll_in_preview(self.bufnr, self.preview_winid)

  if not self.preview_hl_ns then
    self.preview_hl_ns = api.nvim_create_namespace('finderPreview')
  end

  if data.row then
    api.nvim_buf_add_highlight(
      data.bufnr,
      self.preview_hl_ns,
      'finderPreviewSearch',
      data.row,
      data.col,
      data._end_col
    )
  end

  vim.keymap.set('n', config.finder.keys.close_in_preview, function()
    window.nvim_close_valid_window({ self.winid, self.preview_winid, self.tip_winid or nil })
    self:clean_data()
    clean_ctx()
  end, { buffer = data.bufnr, nowait = true, silent = true })

  api.nvim_create_autocmd('WinClosed', {
    group = self.group,
    buffer = data.bufnr,
    callback = function(opt)
      local curwin = api.nvim_get_current_win()
      if curwin == self.preview_winid then
        clear_preview_ns(self.preview_hl_ns, opt.buf)

        if self.winid and api.nvim_win_is_valid(self.winid) then
          api.nvim_set_current_win(self.winid)
          vim.defer_fn(function()
            self:open_preview()
          end, 0)
        end

        self.preview_winid = nil
        self.preview_bufnr = nil
      end
    end,
  })
end

function finder:close_auto_preview_win()
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

  local data = self.short_link[current_line]

  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    local pbuf = api.nvim_win_get_buf(self.preview_winid)
    clear_preview_ns(self.preview_hl_ns, pbuf)
  end
  local restore_opts

  if not data.wipe then
    restore_opts = self.restore_opts
  end

  window.nvim_close_valid_window({ self.winid, self.preview_winid, self.tip_winid or nil })
  self:clean_data()

  -- if buffer not saved save it before jump
  if vim.bo.modified then
    vim.cmd('write')
  end

  local special = { 'edit', 'tab', 'tabnew' }
  if vim.tbl_contains(special, action) and not data.wipe then
    local wins = fn.win_findbuf(data.bufnr)
    local winid = wins[#wins] or api.nvim_get_current_win()
    api.nvim_set_current_win(winid)
    api.nvim_win_set_buf(winid, data.bufnr)
  else
    vim.cmd(action .. ' ' .. uv.fs_realpath(data.link))
  end

  if restore_opts then
    restore_opts.restore()
  end

  if data.row then
    api.nvim_win_set_cursor(0, { data.row + 1, data.col })
  end
  local width = #api.nvim_get_current_line()
  if not width or width <= 0 then
    width = 10
  end
  if data.row then
    libs.jump_beacon({ data.row, 0 }, width)
  end
  clean_ctx()
end

function finder:clean_data()
  for _, buf in ipairs(self.wipe_buffers or {}) do
    api.nvim_buf_delete(buf, { force = true })
    pcall(vim.keymap.del, 'n', config.finder.keys.close_in_preview, { buffer = buf })
  end

  for _, id in ipairs(self.match_ids or {}) do
    pcall(vim.fn.matchdelete, id)
  end

  if self.preview_bufnr and api.nvim_buf_is_loaded(self.preview_bufnr) then
    api.nvim_buf_delete(self.preview_bufnr, { force = true })
  end

  if self.group then
    pcall(api.nvim_del_augroup_by_id, self.group)
  end
end

return setmetatable(ctx, finder)
