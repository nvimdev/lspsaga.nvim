local api, lsp = vim.api, vim.lsp
local config = require('lspsaga').config
local win = require('lspsaga.window')

local function get_action_diff(main_buf, tuple)
  local action = tuple[2]
  if not action then
    return
  end

  local id = tuple[1]
  local client = lsp.get_client_by_id(id)
  if
    not action.edit
    and client
    and vim.tbl_get(client.server_capabilities, 'codeActionProvider', 'resolveProvider')
  then
    local results = lsp.buf_request_sync(main_buf, 'codeAction/resolve', action, 1000)
    ---@diagnostic disable-next-line: need-check-nil
    action = results[client.id].result
    if not action then
      return
    end
    tuple[2] = action
  end

  if not action.edit then
    return
  end

  local all_changes = {}
  if action.edit.documentChanges then
    for _, item in pairs(action.edit.documentChanges) do
      if item.textDocument then
        if not all_changes[item.textDocument.uri] then
          all_changes[item.textDocument.uri] = {}
        end
        for _, edit in pairs(item.edits) do
          all_changes[item.textDocument.uri][#all_changes[item.textDocument.uri] + 1] = edit
        end
      end
    end
  elseif action.edit.changes then
    all_changes = action.edit.changes
  end

  if not (all_changes and not vim.tbl_isempty(all_changes)) then
    return
  end

  local tmp_buf = api.nvim_create_buf(false, false)
  vim.bo[tmp_buf].bufhidden = 'wipe'
  local lines = api.nvim_buf_get_lines(main_buf, 0, -1, false)
  api.nvim_buf_set_lines(tmp_buf, 0, -1, false, lines)

  local srow = 0
  local erow = 0
  for _, changes in pairs(all_changes) do
    lsp.util.apply_text_edits(changes, tmp_buf, client.offset_encoding)
    vim.tbl_map(function(item)
      srow = srow == 0 and item.range.start.line or srow
      erow = erow == 0 and item.range['end'].line or erow
      srow = math.min(srow, item.range.start.line)
      erow = math.max(erow, item.range['end'].line)
    end, changes)
  end

  local data = api.nvim_buf_get_lines(tmp_buf, srow - 1, erow, false)
  data = vim.tbl_map(function(line)
    return line .. '\n'
  end, data)

  lines = vim.list_slice(lines, srow, erow + 1)
  lines = vim.tbl_map(function(line)
    return line .. '\n'
  end, lines)

  api.nvim_buf_delete(tmp_buf, { force = true })
  local diff = vim.diff(table.concat(lines), table.concat(data), {
    algorithm = 'minimal',
    ctxlen = 0,
  })
  diff = vim.tbl_filter(function(item)
    return not item:find('@@%s')
  end, vim.split(diff, '\n'))
  return diff
end

local preview_buf, preview_winid

---create a preview window according given window
---default is under the given window
local function create_preview_win(content, main_winid)
  local win_conf = api.nvim_win_get_config(main_winid)
  local max_height
  local opt = {
    relative = win_conf.relative,
    win = win_conf.win,
    width = win_conf.width,
    col = win_conf.col[false],
    anchor = win_conf.anchor,
    focusable = false,
  }
  local winheight = api.nvim_win_get_height(win_conf.win)

  if win_conf.anchor:find('^S') then
    opt.row = win_conf.row[false] - win_conf.height - 2
    max_height = win_conf.row[false] - win_conf.height
  elseif win_conf.anchor:find('^N') then
    opt.row = win_conf.row[false] + win_conf.height + 2
    max_height = winheight - opt.row
  end

  opt.height = math.min(max_height, #content)

  if config.ui.title then
    opt.title = { { 'Action Preview', 'ActionPreviewTitle' } }
    opt.title_pos = 'center'
  end

  preview_buf, preview_winid = win
    :new_float(opt, false, true)
    :setlines(content)
    :bufopt('filetype', 'diff')
    :bufopt('bufhidden', 'wipe')
    :winopt('winhl', 'NormalFloat:ActionPreviewNormal,Border:ActionPreviewBorder')
    :wininfo()
end

local function action_preview(main_winid, main_buf, tuple)
  local tbl = get_action_diff(main_buf, tuple)
  if not tbl or #tbl == 0 then
    if preview_winid and api.nvim_win_is_valid(preview_winid) then
      api.nvim_win_close(preview_winid, true)
      preview_buf = nil
      preview_winid = nil
    end
    return
  end

  if not preview_winid or not api.nvim_win_is_valid(preview_winid) then
    create_preview_win(tbl, main_winid)
  else
    --reuse before window
    vim.bo[preview_buf].modifiable = true
    api.nvim_buf_set_lines(preview_buf, 0, -1, false, tbl)
    vim.bo[preview_buf].modifiable = false
    api.nvim_win_set_config(preview_winid, { height = #tbl })
  end

  return preview_buf, preview_winid
end

local function preview_win_close()
  if preview_winid and api.nvim_win_is_valid(preview_winid) then
    api.nvim_win_close(preview_winid, true)
    preview_winid = nil
    preview_buf = nil
  end
end

return {
  action_preview = action_preview,
  preview_win_close = preview_win_close,
}
