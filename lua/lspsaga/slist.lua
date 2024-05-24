---@class Node
---@field value NodeValue
---@field next Node
---@field prev Node

---@class NodeValue
---@field range? Range
---@field bufnr? number
---@field client_id number
---@field inlevel number
---@field line string
---@field uri string
---@field winline number

---@class Range
---@field start Position
---@field end Position

---@alias Position  {character:number, line:number}

---single linked list module
local M = {}

function M.new()
  return { value = nil, next = nil, prev = nil }
end

function M.tail_push(list, node)
  local tmp = list
  if not tmp.value then
    tmp.value = node
    return
  end

  while true do
    if not tmp.next then
      break
    end
    tmp = tmp.next
  end
  tmp.next = { value = node }
end

--- Finds a node in the linked list that matches the given predicate function.
---@param list Node  -- The linked list to search.
---@param predicate fun(node: Node): boolean  -- The predicate function to match the node.
---@return Node | nil  -- The found node or nil if not found.
function M.find_node_by(list, predicate)
  local current = list
  while current do
    if predicate(current) then
      return current
    end
    current = current.next
  end

  return nil
end

function M.find_node(list, curlnum)
  local tmp = list
  if not tmp.value then
    return
  end
  while tmp do
    if tmp.value.winline == curlnum then
      return tmp
    end
    tmp = tmp.next
  end
end

function M.insert_node(curnode, node)
  local tmp = curnode.next
  curnode.next = {
    value = node,
    next = tmp,
  }
end

function M.update_winline(node, count)
  node = node.next
  local total = count < 0 and math.abs(count) or 0
  while node do
    if total ~= 0 then
      node.value.winline = -1
      total = total - 1
      if node.value.expand then
        node.value.expand = false
      end
    else
      if node.value.winline ~= -1 then
        node.value.winline = node.value.winline + count
      end
    end
    node = node.next
  end
end

function M.list_map(list, fn)
  local node = list
  while node do
    fn(node)
    node = node.next
  end
end

return M
