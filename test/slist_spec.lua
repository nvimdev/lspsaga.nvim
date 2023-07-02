local eq, same = assert.equal, assert.same
local slist = require('lspsaga.slist')
describe('single linked list module ', function()
  local list = slist.new()

  it('can tail insert node to list', function()
    slist.tail_push(
      list,
      { name = 'test', range = { start = { line = 1, character = 1 } }, winline = 1 }
    )
    slist.tail_push(
      list,
      { name = 'test2', range = { start = { line = 2, character = 2 } }, winline = 2 }
    )
    same({
      value = {
        name = 'test',
        winline = 1,
        range = {
          start = {
            line = 1,
            character = 1,
          },
        },
      },
      next = {
        value = {
          name = 'test2',
          winline = 2,
          range = {
            start = {
              line = 2,
              character = 2,
            },
          },
        },
      },
    }, list)
  end)

  it('can find node', function()
    local node = slist.find_node(list, 2)
    same({
      value = {
        name = 'test2',
        winline = 2,
        range = {
          start = {
            line = 2,
            character = 2,
          },
        },
      },
    }, node)
  end)
end)
