local uv = vim.version().minor >= 10 and vim.uv or vim.loop
local api = vim.api
local config = require('lspsaga').config
local win = require('lspsaga.window')

local function jump_beacon(bufpos, width)
  if not config.beacon.enable then
    return
  end

  if width == 0 or not width then
    return
  end

  local float_opt = {
    relative = 'win',
    bufpos = bufpos,
    height = 1,
    width = width,
    row = 0,
    col = 0,
    anchor = 'NW',
    focusable = false,
    noautocmd = true,
    border = 'none',
  }

  local _, winid = win
    :new_float(float_opt, false, true)
    :bufopt({
      ['filetype'] = 'beacon',
      ['bufhidden'] = 'wipe',
      ['buftype'] = 'nofile',
    })
    :winopt('winhl', 'NormalFloat:SagaBeacon')
    :wininfo()

  local timer = uv.new_timer()
  timer:start(
    0,
    60,
    vim.schedule_wrap(function()
      if not api.nvim_win_is_valid(winid) then
        return
      end
      local blend = vim.wo[winid].winblend + config.beacon.frequency
      if blend > 100 then
        blend = 100
      end
      vim.wo[winid].winblend = blend
      if vim.wo[winid].winblend == 100 and not timer:is_closing() then
        timer:stop()
        timer:close()
        api.nvim_win_close(winid, true)
      end
    end)
  )
end

return {
  jump_beacon = jump_beacon,
}
