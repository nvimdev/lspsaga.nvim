local api = vim.api
local wrap = {}
local space = ' '

-- If the content too long.
-- auto wrap according width
-- fill the space with wrap text
function wrap.wrap_text(text, width)
  local res = {}
  local tbl = {}
  if text:find('\n') then
    text = text:gsub('\n', '')
  end
  tbl = vim.split(text, '%s', { trimempty = true })
  local index, count = 1, 0
  local scopes = {}
  repeat
    if count > width then
      table.insert(scopes, index - 1)
      count = 0
    else
      count = count + #tbl[index]
      if count > width then
        table.insert(scopes, index - 1)
        count = 0
      elseif index == #tbl then
        table.insert(scopes, index)
      end
    end

    index = index + 1
  until index == #tbl + 1

  for k, v in pairs(scopes) do
    local prev = k == 1 and 1 or scopes[k - 1]
    table.insert(res, table.concat(tbl, ' ', prev, v))
  end
  print(vim.inspect(scopes), #tbl, vim.inspect(tbl))

  return res
end

function wrap.diagnostic_msg(msg, width)
  -- if msg:find('\n') then
  --   local t = vim.tbl_filter(function(s)
  --     return string.len(s) ~= 0
  --   end, vim.split(msg, '\n'))
  --   return t
  -- end

  -- if #msg < width then
  --   return { msg }
  -- end

  return wrap.wrap_text(msg, width)
end

function wrap.wrap_contents(contents, width)
  if type(contents) ~= 'table' then
    error('Wrong params type of function wrap_contents')
    return
  end
  local stripped = {}

  for _, text in ipairs(contents) do
    if #text < width then
      table.insert(stripped, text)
    else
      local tmp = wrap.wrap_text(text, width)
      for _, j in ipairs(tmp) do
        table.insert(stripped, j)
      end
    end
  end

  return stripped
end

function wrap.generate_spe_line(width)
  local char = '─'
  local line = ''
  for _ = 1, width, 1 do
    line = line .. char
  end
  return line
end

function wrap.truncate_line(width, title)
  local char = '─'
  local line = ''
  local t_cent = math.floor(api.nvim_strwidth(title) / 2)
  local w_cent = math.floor(width / 2)
  for _ = 1, width, 1 do
    line = line .. char
  end
  local cell = #line / width
  local start_pos = (w_cent - t_cent) * cell
  line = line:sub(0, start_pos) .. title .. line:sub(#line - start_pos + 1)
  return line, { start_pos, #line - start_pos }
end

function wrap.add_truncate_line(contents)
  local line_widths = {}
  local width = 0
  local char = '─'
  local truncate_line = char

  for i, line in ipairs(contents) do
    line_widths[i] = vim.fn.strdisplaywidth(line)
    width = math.max(line_widths[i], width)
  end

  for _ = 1, width, 1 do
    truncate_line = truncate_line .. char
  end

  return truncate_line
end

return wrap
