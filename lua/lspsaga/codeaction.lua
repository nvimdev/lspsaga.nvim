local api = vim.api
local window = require "lspsaga.window"
local config = require("lspsaga").config_values
local wrap = require "lspsaga.wrap"
local libs = require "lspsaga.libs"

local Action = {}
Action.__index = Action

local get_namespace = function()
  return api.nvim_create_namespace "sagalightbulb"
end

local get_current_winid = function()
  return api.nvim_get_current_win()
end

local SIGN_GROUP = "sagalightbulb"
local SIGN_NAME = "LspSagaLightBulb"

if vim.tbl_isempty(vim.fn.sign_getdefined(SIGN_NAME)) then
  vim.fn.sign_define(SIGN_NAME, { text = config.code_action_icon, texthl = "LspSagaLightBulb" })
end

local function _update_virtual_text(line)
  local namespace = get_namespace()
  api.nvim_buf_clear_namespace(0, namespace, 0, -1)

  if line then
    local icon_with_indent = "  " .. config.code_action_icon
    api.nvim_buf_set_extmark(0, namespace, line, -1, {
      virt_text = { { icon_with_indent, "LspSagaLightBulb" } },
      virt_text_pos = "overlay",
      hl_mode = "combine",
    })
  end
end

local function _update_sign(line)
  local winid = get_current_winid()
  if Action[winid] and Action[winid].lightbulb_line ~= 0 then
    vim.fn.sign_unplace(SIGN_GROUP, { id = Action[winid].lightbulb_line, buffer = "%" })
  end

  if line and Action[winid] then
    vim.fn.sign_place(
      line,
      SIGN_GROUP,
      SIGN_NAME,
      "%",
      { lnum = line + 1, priority = config.code_action_prompt.sign_priority }
    )
    Action[winid].lightbulb_line = line
  end
end

local need_check_diagnostic = {
  ["go"] = true,
  ["python"] = true,
}

function Action:render_action_virtual_text(line, diagnostics)
  return function(_, method, actions)
    if vim.fn.has('nvim-0.5.1') == 1 then
        actions = method
    end

    if actions == nil or type(actions) ~= "table" or vim.tbl_isempty(actions) then
      if config.code_action_prompt.virtual_text then
        _update_virtual_text(nil)
      end
      if config.code_action_prompt.sign then
        _update_sign(nil)
      end
    else
      if config.code_action_prompt.sign then
        if need_check_diagnostic[vim.bo.filetype] then
          if next(diagnostics) == nil then
            _update_sign(nil)
          else
            _update_sign(line)
          end
        else
          _update_sign(line)
        end
      end

      if config.code_action_prompt.virtual_text then
        if need_check_diagnostic[vim.bo.filetype] then
          if next(diagnostics) == nil then
            _update_virtual_text(nil)
          else
            _update_virtual_text(line)
          end
        else
          _update_virtual_text(line)
        end
      end
    end
  end
end

function Action:action_callback()
  return function(_, method, response)
    if vim.fn.has('nvim-0.5.1') == 1 then
        response = method
    end

    if response == nil or vim.tbl_isempty(response) then
      print "No code actions available"
      return
    end

    local contents = {}
    local title = config["code_action_icon"] .. "CodeActions:"
    table.insert(contents, title)

    local from_other_servers = function()
      local actions = {}
      for _, action in pairs(response) do
        self.actions[#self.actions + 1] = action
        local action_title = "[" .. #self.actions .. "]" .. " " .. action.title
        actions[#actions + 1] = action_title
      end
      return actions
    end

    if self.actions and next(self.actions) ~= nil then
      local other_actions = from_other_servers()
      if next(other_actions) ~= nil then
        vim.tbl_extend("force", self.actions, other_actions)
      end
      api.nvim_buf_set_option(self.action_bufnr, "modifiable", true)
      vim.fn.append(vim.fn.line "$", other_actions)
      vim.cmd("resize " .. #self.actions + 2)
      for i, _ in pairs(other_actions) do
        vim.fn.matchadd("LspSagaCodeActionContent", "\\%" .. #self.actions + 1 + i .. "l")
      end
    else
      self.actions = response
      for index, action in pairs(response) do
        local action_title = "[" .. index .. "]" .. " " .. action.title
        table.insert(contents, action_title)
      end
    end

    if #contents == 1 then
      return
    end

    -- insert blank line
    local truncate_line = wrap.add_truncate_line(contents)
    table.insert(contents, 2, truncate_line)

    local content_opts = {
      contents = contents,
      filetype = "LspSagaCodeAction",
      enter = true,
      highlight = "LspSagaCodeActionBorder",
    }

    self.action_bufnr, self.action_winid = window.create_win_with_border(content_opts)
    api.nvim_command 'autocmd CursorMoved <buffer> lua require("lspsaga.codeaction").set_cursor()'
    api.nvim_command "autocmd QuitPre <buffer> lua require('lspsaga.codeaction').quit_action_window()"

    api.nvim_buf_add_highlight(self.action_bufnr, -1, "LspSagaCodeActionTitle", 0, 0, -1)
    api.nvim_buf_add_highlight(self.action_bufnr, -1, "LspSagaCodeActionTruncateLine", 1, 0, -1)
    for i = 1, #contents - 2, 1 do
      api.nvim_buf_add_highlight(self.action_bufnr, -1, "LspSagaCodeActionContent", 1 + i, 0, -1)
    end
    self:apply_action_keys()
  end
end

local apply_keys = libs.apply_keys "codeaction"

local apply_keys = libs.apply_keys "codeaction"

function Action:apply_action_keys()
  local actions = {
    ["quit_action_window"] = config.code_action_keys.quit,
    ["do_code_action"] = config.code_action_keys.exec,
  }
  for func, keys in pairs(actions) do
    apply_keys(func, keys)
  end
end

local action_call_back = function(_, _)
  return Action:action_callback()
end

local action_virtual_call_back = function(line, diagnostics)
  return Action:render_action_virtual_text(line, diagnostics)
end

function Action:code_action(_call_back_fn, diagnostics)
  local active, _ = libs.check_lsp_active()
  if not active then
    return
  end
  self.bufnr = vim.fn.bufnr()
  local context = { diagnostics = diagnostics }
  local params = vim.lsp.util.make_range_params()
  params.context = context
  local line = params.range.start.line
  local callback = _call_back_fn(line, diagnostics)
  vim.lsp.buf_request(0, "textDocument/codeAction", params, callback)
end

function Action:range_code_action(context, start_pos, end_pos)
  local active, msg = libs.check_lsp_active()
  if not active then
    print(msg)
    return
  end

  self.bufnr = vim.fn.bufnr()
  vim.validate { context = { context, "t", true } }
  context = context or { diagnostics = vim.lsp.diagnostic.get_line_diagnostics() }
  local params = vim.lsp.util.make_given_range_params(start_pos, end_pos)
  params.context = context
  local call_back = self:action_callback()
  vim.lsp.buf_request(0, "textDocument/codeAction", params, call_back)
end

function Action:set_cursor()
  local column = 2
  local current_line = vim.fn.line "."

  if current_line == 1 then
    vim.fn.cursor(3, column)
  elseif current_line == 2 then
    vim.fn.cursor(2 + #self.actions, column)
  elseif current_line == #self.actions + 3 then
    vim.fn.cursor(3, column)
  end
end

local function lsp_execute_command(bn, command)
  vim.lsp.buf_request(bn, "workspace/executeCommand", command)
end

function Action:do_code_action()
  local number = tonumber(vim.fn.expand "<cword>")
  local action = self.actions[number]

  if action.edit or type(action.command) == "table" then
    if action.edit then
      vim.lsp.util.apply_workspace_edit(action.edit)
    end
    if type(action.command) == "table" then
      lsp_execute_command(self.bufnr, action.command)
    end
  else
    lsp_execute_command(self.bufnr, action)
  end
  self:quit_action_window()
end

function Action:clear_tmp_data()
  self.actions = {}
  self.bufnr = 0
  self.action_bufnr = 0
  self.action_winid = 0
end

function Action:quit_action_window()
  if self.action_bufnr == 0 and self.action_winid == 0 then
    return
  end
  window.nvim_close_valid_window(self.action_winid)
  self:clear_tmp_data()
end

local lspaction = {}

local special_buffers = {
  ["LspSagaCodeAction"] = true,
  ["lspsagafinder"] = true,
  ["NvimTree"] = true,
  ["vist"] = true,
  ["lspinfo"] = true,
  ["markdown"] = true,
  ["text"] = true,
}

lspaction.code_action = function()
  local diagnostics = vim.lsp.diagnostic.get_line_diagnostics()
  Action:code_action(action_call_back, diagnostics)
end

lspaction.code_action_prompt = function()
  if special_buffers[vim.bo.filetype] then
    return
  end
  local active_lsp, _ = libs.check_lsp_active()
  if not active_lsp then
    return
  end

  local diagnostics = vim.lsp.diagnostic.get_line_diagnostics()
  local winid = get_current_winid()
  Action[winid] = Action[winid] or {}
  Action[winid].lightbulb_line = Action[winid].lightbulb_line or 0
  Action:code_action(action_virtual_call_back, diagnostics)
end

lspaction.do_code_action = function()
  Action:do_code_action()
end

lspaction.quit_action_window = function()
  Action:quit_action_window()
end

lspaction.range_code_action = function()
  Action:range_code_action()
end

lspaction.set_cursor = function()
  Action:set_cursor()
end

return lspaction
