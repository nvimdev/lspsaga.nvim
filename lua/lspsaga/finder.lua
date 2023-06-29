local api, lsp, fn, uv = vim.api, vim.lsp, vim.fn, vim.loop
local config = require('lspsaga').config
local ui = config.ui
local window = require('lspsaga.window')
local util = require('lspsaga.util')
local nvim_buf_set_extmark = api.nvim_buf_set_extmark
local nvim_buf_set_keymap = api.nvim_buf_set_keymap
local ns_id = api.nvim_create_namespace('lspsagafinder')
local co = coroutine

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
    '● References',
  }
  return t[index]
end

local function methods(index)
  local t = {
    'textDocument/definition',
    'textDocument/references',
  }

  return index and t[index] or t
end

function finder:lsp_finder()
  -- push a tag stack
  local pos = api.nvim_win_get_cursor(0)
  self.main_buf = api.nvim_get_current_buf()
  self.main_win = api.nvim_get_current_win()
  local from = { self.main_buf, pos[1], pos[2], 0 }
  local items = { { tagname = fn.expand('<cword>'), from = from } }
  fn.settagstack(self.main_win, { items = items }, 't')

  self.request_status = {}
  self.lspdata = {}

  local params = lsp.util.make_position_params()
  local meths = methods()
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
    params.context = { includeDeclaration = false }
  end
  lsp.buf_request_all(self.current_buf, method, params, function(results)
    local result = {}
    for _, res in pairs(results or {}) do
      if res.result and not (res.result.uri or res.result.targetUri) then
        util.merge_table(result, res.result)
      elseif res.result and (res.result.uri or res.result.targetUri) then
        result[#result + 1] = res.result
      end
    end

    if vim.tbl_isempty(result) then
      self.request_status[method] = true
      return
    end

    local uri = result[1].uri or result[1].targetUri
    local range = result[1].targetRange or result[1].range
    local line = api.nvim_win_get_cursor(0)[1]
    if
      method == methods(1)
      and vim.uri_to_bufnr(uri) == api.nvim_get_current_buf()
      and range.start.line == line
    then
      local col = api.nvim_win_get_cursor(0)[2]
      if col >= range.start.character and col <= range['end'].character then
        self.request_status[method] = true
        return
      end
    end

    self:create_finder_data(result, method)
    self.request_status[method] = true
  end)
end

function finder:create_finder_data(result, method)
  if #result == 1 and result[1].inline then
    return
  end
  if not self.wipe_buffers then
    self.wipe_buffers = {}
  end

  if not self.lspdata[method] then
    self.lspdata[method] = {}
    local title = get_titles(util.tbl_index(methods(), method))
    self.lspdata[method].title = title .. '  ' .. #result
    self.lspdata[method].count = #result
  end
  local parent = self.lspdata[method]
  parent.data = {}

  for i, res in ipairs(result) do
    local uri = res.targetUri or res.uri
    if not uri then
      vim.notify('[Lspsaga] miss uri in server response', vim.log.levels.WARN)
      return
    end

    local bufnr = vim.uri_to_bufnr(uri)
    local fname = vim.uri_to_fname(uri) -- returns lowercase drive letters on Windows
    local range = res.targetSelectionRange or res.targetRange or res.range
    if util.iswin then
      fname = fname:gsub('^%l', fname:sub(1, 1):upper())
    end
    fname = table.concat(util.get_path_info(bufnr, 2), util.path_sep)

    local node = {
      bufnr = bufnr,
      fname = fname,
      row = range.start.line,
      col = range.start.character,
      ecol = range['end'].character,
      method = method,
      winline = -1,
    }

    if not api.nvim_buf_is_loaded(bufnr) then
      node.wipe = true
      --ignore the FileType event avoid trigger the lsp
      vim.opt.eventignore:append({ 'FileType' })
      fn.bufload(bufnr)
      --restore eventignore
      vim.opt.eventignore:remove({ 'FileType' })
      if not vim.tbl_contains(self.wipe_buffers, bufnr) then
        self.wipe_buffers[#self.wipe_buffers + 1] = bufnr
      end
    end

    local start_col = 0
    --avoid the preview code too long
    if node.col > 15 then
      start_col = node.col - 10
    end
    node.word = api.nvim_buf_get_text(node.bufnr, node.row, start_col, node.row, node.ecol, {})[1]
    if node.word:find('^%s') then
      node.word = node.word:sub(node.word:find('%S'), #node.word)
    end

    if not parent.data[node.fname] then
      parent.data[node.fname] = {
        expand = true,
        nodes = {},
      }
    end
    if i == #result then
      node.tail = true
    end
    parent.data[node.fname].nodes[#parent.data[node.fname].nodes + 1] = node
  end
end

local function get_max_height()
  return math.floor(vim.o.lines * config.finder.max_height)
end

function finder:render_finder()
  local width = {}
  self.bufnr = api.nvim_create_buf(false, false)
  local float_height = get_max_height()

  self.render_fn = co.create(function(need_yield)
    local indent = (' '):rep(2)
    local virt_hi = 'Finderlines'
    local line_count = 0

    ---@diagnostic disable-next-line: param-type-mismatch
    for i, method in pairs(methods()) do
      local meth_data = self.lspdata[method]
      if not meth_data then
        goto skip
      end
      local title = { meth_data.title }
      if i > 1 and api.nvim_buf_line_count(self.bufnr) ~= 1 then
        table.insert(title, 1, '')
      end
      api.nvim_buf_set_lines(self.bufnr, line_count, line_count, false, title)
      width[#width + 1] = #meth_data.title
      line_count = line_count + #title
      api.nvim_buf_add_highlight(self.bufnr, ns_id, 'FinderType', line_count - 1, 4, 16)
      api.nvim_buf_add_highlight(self.bufnr, ns_id, 'FinderIcon', line_count - 1, 0, 4)
      api.nvim_buf_add_highlight(self.bufnr, ns_id, 'FinderCount', line_count - 1, 16, -1)

      local first = true
      for fname, item in pairs(meth_data.data) do
        local text = indent .. ui.collapse .. ' ' .. fname .. ' ' .. #item.nodes
        indent = (' '):rep(5)
        api.nvim_buf_set_lines(self.bufnr, line_count, line_count + 1, false, { text })
        width[#width + 1] = #text
        line_count = line_count + 1
        local start = line_count
        api.nvim_buf_add_highlight(self.bufnr, ns_id, 'SagaCollapse', line_count - 1, 0, 5)
        api.nvim_buf_add_highlight(self.bufnr, ns_id, 'FinderFname', line_count - 1, 6, -1)

        for k, v in pairs(item.nodes) do
          local tbl = {
            { k == #item.nodes and ui.lines[1] or ui.lines[2], virt_hi },
            { ui.lines[4]:rep(2), virt_hi },
          }
          if first then
            v.first = true
            first = false
            meth_data.start = start
          end
          v.start = start
          text = indent .. v.word
          api.nvim_buf_set_lines(self.bufnr, line_count, line_count + 1, false, { text })
          width[#width + 1] = #text
          line_count = line_count + 1
          api.nvim_buf_add_highlight(self.bufnr, ns_id, 'FinderCode', line_count - 1, 5, -1)
          v.winline = v.winline > -1 and v.winline or line_count
          nvim_buf_set_extmark(self.bufnr, ns_id, line_count - 1, 2, {
            virt_text = tbl,
            virt_text_pos = 'overlay',
          })

          if line_count > float_height + 10 and need_yield then
            table.sort(width)
            need_yield = co.yield(width[#width])
          end
        end
        indent = '  '
      end
      ::skip::
    end

    if api.nvim_buf_line_count(self.bufnr) == 0 then
      clean_ctx()
      vim.notify('[Lspsaga] finder nothing to show', vim.log.levels.WARN)
      return
    end
    api.nvim_buf_set_lines(self.bufnr, line_count, line_count + 1, false, { '' })
    vim.bo[self.bufnr].modifiable = false
  end)

  self:apply_map()

  while true do
    local _, float_width = co.resume(self.render_fn, true)
    if not float_width and co.status(self.render_fn) == 'dead' then
      table.sort(width)
      float_width = width[#width]
    end

    if not float_width then
      print('[lspsaga] no data to show')
      return
    end
    self:create_finder_win(float_width)
    break
  end
end

function finder:create_finder_win(width)
  self.group = api.nvim_create_augroup('lspsaga_finder', { clear = true })

  local opt = {
    relative = 'editor',
    width = width,
    height = get_max_height(),
    no_size_override = true,
  }

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
    contents = {},
    filetype = 'lspsagafinder',
    bufhidden = 'wipe',
    bufnr = self.bufnr,
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
  vim.bo[self.bufnr].buftype = 'nofile'

  self.restore_opts = window.restore_option()
  _, self.winid = window.create_win_with_border(content_opts, opt)

  -- make sure close preview window by using wincmd
  api.nvim_create_autocmd('WinClosed', {
    buffer = self.bufnr,
    once = true,
    callback = function()
      local ok, buf = pcall(api.nvim_win_get_buf, self.peek_winid)
      if ok then
        pcall(api.nvim_buf_clear_namespace, buf, self.preview_hl_ns, 0, -1)
      end
      pcall(api.nvim_del_augroup_by_id, self.group)
      self:close_auto_preview_win()
      self:clean_data()
      clean_ctx()
    end,
  })

  local before, start = 0, 0
  local ns_select = api.nvim_create_namespace('FinderSelect')
  api.nvim_create_autocmd('CursorMoved', {
    buffer = self.bufnr,
    callback = function()
      local curline = api.nvim_win_get_cursor(self.winid)[1]
      api.nvim_buf_clear_namespace(self.bufnr, ns_select, 0, -1)
      local col = 5
      local buf_lines = api.nvim_buf_line_count(self.bufnr)
      local text = api.nvim_get_current_line()
      local in_fname = text:find(ui.expand) or text:find(ui.collapse)
      local node

      if curline == 1 or curline > buf_lines - 1 then
        curline = 3
        start = 2
        node = self:get_node({ lnum = 3 })
      elseif curline == 2 and curline < before then
        curline = buf_lines - 1
        node = self:get_node({ lnum = curline })
        start = node.start
      elseif text:find('%sDef') or text:find('%sRef') or #text == 0 then
        local increase = curline > before and 1 or -1
        for _, v in ipairs({
          curline,
          curline + increase,
          curline + increase * 2,
          curline + increase * 3,
        }) do
          node = self:get_node({ lnum = v })
          if node then
            curline = node.winline
            start = node.start
          end
        end
      elseif not in_fname then
        node = self:get_node({ lnum = curline })
        start = node.start
      end

      col = in_fname and 7 or col
      before = curline
      api.nvim_win_set_cursor(self.winid, { curline, col })
      api.nvim_buf_add_highlight(
        self.bufnr,
        ns_select,
        'FinderStart',
        start - 1,
        #ui.collapse + 2,
        -1
      )
      api.nvim_buf_add_highlight(self.bufnr, ns_select, 'FinderSelection', curline - 1, 5, -1)

      if node then
        self:open_preview(node)
      end
    end,
  })

  if self.render_fn and co.status(self.render_fn) == 'suspended' then
    co.resume(self.render_fn, false)
  end
end

local function unpack_map()
  local map = {}
  for k, v in pairs(config.finder.keys) do
    if k ~= 'jump_to' and k ~= 'close_in_preview' and k ~= 'expand_or_jump' then
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
          local curline = api.nvim_win_get_cursor(self.winid)[1]
          local node = self:get_node({ lnum = curline })
          if not node then
            return
          end
          self:do_action(node, action)
        end, opts)
      end
    end
  end

  for _, key in pairs(config.finder.keys.quit) do
    vim.keymap.set('n', key, function()
      local ok, buf = pcall(api.nvim_win_get_buf, self.peek_winid)
      if ok then
        pcall(api.nvim_buf_clear_namespace, buf, self.preview_hl_ns, 0, -1)
      end
      window.nvim_close_valid_window({ self.winid, self.peek_winid })
      self:clean_data()
      clean_ctx()
    end, opts)
  end

  vim.keymap.set('n', config.finder.keys.jump_to, function()
    if self.peek_winid and api.nvim_win_is_valid(self.peek_winid) then
      api.nvim_set_current_win(self.peek_winid)
    end
  end, opts)

  local function expand_or_collapse(text, curline)
    local fname = text:match(ui.expand .. '%s(.+)%s')
    if not fname then
      fname = text:match(ui.collapse .. '%s(.+)%s')
    end
    if not fname then
      return
    end

    local nodes = self:find_nodes_by_fname(fname)
    vim.bo[self.bufnr].modifiable = true

    if not self.lspdata[nodes[1].method].data[nodes[1].fname].expand then
      text = text:gsub(ui.expand, ui.collapse)
      local lines = vim.tbl_map(function(i)
        return (' '):rep(5) .. i.word
      end, nodes)
      table.insert(lines, 1, text)
      api.nvim_buf_set_lines(self.bufnr, curline - 1, curline, false, lines)
      for i = 1, #nodes do
        api.nvim_buf_set_extmark(self.bufnr, ns_id, curline - 1 + i, 2, {
          virt_text = {
            { i == #nodes and ui.lines[1] or ui.lines[2], 'FinderLines' },
            { ui.lines[4]:rep(2), 'FinderLines' },
          },
          virt_text_pos = 'overlay',
        })
        api.nvim_buf_add_highlight(self.bufnr, ns_id, 'FinderCode', curline - 1 + i, 5, -1)
      end
      self:change_node_winline(function(item)
        return item.winline > curline
      end, #nodes)
      for i, v in ipairs(nodes) do
        v.winline = curline + i
      end
      api.nvim_win_set_cursor(self.winid, { curline + 1, 5 })
      api.nvim_buf_add_highlight(self.bufnr, ns_id, 'SagaCollapse', curline - 1, 0, 5)
      vim.bo[self.bufnr].modifiable = false
      self.lspdata[nodes[1].method].data[nodes[1].fname].expand = true
      return
    end

    text = text:gsub(ui.collapse, ui.expand)
    api.nvim_buf_clear_namespace(self.bufnr, ns_id, curline - 1, curline + #nodes)
    api.nvim_buf_set_lines(self.bufnr, curline - 1, curline + #nodes, false, { text })
    api.nvim_buf_add_highlight(self.bufnr, ns_id, 'SagaToggle', nodes[1].start - 1, 0, 5)
    self.lspdata[nodes[1].method].data[fname].expand = false
    self:change_node_winline(function(item)
      return item.winline > curline + #nodes
    end, -#nodes)
    for _, v in ipairs(nodes) do
      v.winline = -1
    end
    vim.bo[self.bufnr].modifiable = false
  end

  nvim_buf_set_keymap(self.bufnr, 'n', config.finder.keys.expand_or_jump, '', {
    noremap = true,
    nowait = true,
    callback = function()
      local curline = api.nvim_win_get_cursor(self.winid)[1]
      local text = api.nvim_get_current_line()
      local in_fname = text:find(ui.expand) or text:find(ui.collapse)
      if in_fname then
        expand_or_collapse(text, curline)
        return
      end
      local node = self:get_node({ lnum = curline })
      if not node then
        return
      end
      self:do_action(node, 'edit')
    end,
  })
end

function finder:find_nodes_by_fname(fname)
  for _, meth_data in pairs(self.lspdata) do
    for f, item in pairs(meth_data.data) do
      if f == fname then
        return item.nodes
      end
    end
  end
end

function finder:next_node_in_meth(method, cur_fname, lnum)
  for fname, item in pairs(self.lspdata[method].data) do
    if fname ~= cur_fname then
      for i = 1, #item.nodes do
        if i == 1 and item.nodes[i].winline > lnum then
          return item.nodes[i]
        end
      end
    end
  end
end

function finder:change_node_winline(cond, increase)
  for _, meth_data in pairs(self.lspdata) do
    for _, item in pairs(meth_data.data) do
      for _, node in ipairs(item.nodes) do
        if cond(node) then
          node.winline = node.winline + increase
          node.start = node.start + increase
        end
      end
    end
  end
end

function finder:get_node(opt)
  local node
  for meth, meth_data in pairs(self.lspdata) do
    if opt.meth and opt.meth ~= meth then
      goto skip
    end
    for _, item in pairs(meth_data.data) do
      for _, v in ipairs(item.nodes) do
        if
          (opt.lnum and v.winline == opt.lnum)
          or (opt.first and v.first)
          or (opt.tail and v.tail)
        then
          node = v
          break
        end
      end
    end
    ::skip::
  end
  return node
end

function finder:node_in_range(range)
  for _, lnum in ipairs(range) do
    local node = self:get_node({ lnum = lnum })
    if node then
      return node
    end
  end
end

local function create_preview_window(finder_winid)
  if not finder_winid or not api.nvim_win_is_valid(finder_winid) then
    return
  end

  local opts = {
    relative = 'editor',
    no_size_override = true,
    zindex = 80,
  }

  local winconfig = api.nvim_win_get_config(finder_winid)
  opts.row = winconfig.row[false]
  opts.height = winconfig.height

  local border_side = {}
  local top = window.combine_char()['top'][config.ui.border]
  local bottom = window.combine_char()['bottom'][config.ui.border]

  --in right
  if vim.o.columns - winconfig.col[false] - winconfig.width >= config.finder.min_width then
    local adjust = config.ui.border == 'shadow' and -2 or 2
    opts.col = winconfig.col[false] + winconfig.width + adjust
    opts.width = vim.o.columns - opts.col - 2
    border_side = {
      ['lefttop'] = top,
      ['leftbottom'] = bottom,
    }
  --in left
  elseif winconfig.col[false] >= config.finder.min_width then
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

  if not opts.col then
    vim.notify(
      '[Lspsaga] finder previee get col failed try change finder.min_width',
      vim.log.levels.WARN
    )
    return
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

function finder:open_preview(node)
  if self.peek_winid and api.nvim_win_is_valid(self.peek_winid) then
    local before_buf = api.nvim_win_get_buf(self.peek_winid)
    clear_preview_ns(ns_id, before_buf)
  end

  if not node then
    return
  end

  if not self.peek_winid or not api.nvim_win_is_valid(self.peek_winid) then
    self.preview_bufnr, self.peek_winid = create_preview_window(self.winid)
    if not self.peek_winid then
      return
    end
    api.nvim_win_set_hl_ns(self.peek_winid, ns_id)
  end

  local function highlight_word()
    api.nvim_buf_add_highlight(node.bufnr, ns_id, 'FinderPreview', node.row, node.col, node.ecol)
  end

  local buf_in_peek = api.nvim_win_get_buf(self.peek_winid)
  if buf_in_peek == node.bufnr then
    api.nvim_win_set_cursor(self.peek_winid, { node.row + 1, node.col })
    highlight_word()
    return
  end

  api.nvim_win_set_buf(self.peek_winid, node.bufnr)
  api.nvim_win_set_cursor(self.peek_winid, { node.row + 1, node.col })
  highlight_word()

  api.nvim_set_option_value('winbar', '', {
    scope = 'local',
    win = self.peek_winid,
  })

  api.nvim_set_option_value(
    'winhl',
    'Normal:finderNormal,FloatBorder:finderPreviewBorder',
    { scope = 'local', win = self.peek_winid }
  )

  if node.wipe then
    local lang = vim.treesitter.language.get_lang(vim.bo[self.main_buf].filetype)
    vim.defer_fn(function()
      vim.treesitter.start(node.bufnr, lang)
    end, 5)
    node.loaded = true
  end
end

function finder:close_auto_preview_win()
  if self.peek_winid and api.nvim_win_is_valid(self.peek_winid) then
    local buf = api.nvim_win_get_buf(self.peek_winid)
    clear_preview_ns(ns_id, buf)
    api.nvim_win_close(self.peek_winid, true)
    self.peek_winid = nil
  end
end

function finder:do_action(node, action)
  if self.peek_winid and api.nvim_win_is_valid(self.peek_winid) then
    local pbuf = api.nvim_win_get_buf(self.peek_winid)
    clear_preview_ns(ns_id, pbuf)
  end
  local restore_opts
  local data = vim.deepcopy(node)
  local fname = api.nvim_buf_get_name(data.bufnr)
  if not data.wipe then
    restore_opts = self.restore_opts
  end

  window.nvim_close_valid_window({ self.winid, self.peek_winid, self.tip_winid or nil })
  self:clean_data()

  -- if buffer not saved save it before jump
  if fname == api.nvim_buf_get_name(0) and vim.bo.modified then
    vim.cmd('write')
  end

  vim.cmd(action .. ' ' .. fn.fnameescape(fname))

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
    util.jump_beacon({ data.row, 0 }, width)
  end
  clean_ctx()
end

function finder:clean_data()
  for _, buf in ipairs(self.wipe_buffers or {}) do
    api.nvim_buf_delete(buf, { force = true })
    pcall(vim.keymap.del, 'n', config.finder.keys.close_in_preview, { buffer = buf })
  end

  if self.preview_bufnr and api.nvim_buf_is_loaded(self.preview_bufnr) then
    api.nvim_buf_delete(self.preview_bufnr, { force = true })
  end

  if self.group then
    pcall(api.nvim_del_augroup_by_id, self.group)
  end
end

return setmetatable(ctx, finder)
