-- Run through python3 tests/live.py: dedicated tmux server and cleanup.
vim.opt.rtp:prepend(vim.fn.getcwd())
local H = dofile('tests/live_helpers.lua')
local function main()
  assert(vim.env.OPVI_LIVE_TEST == '1', 'Run python3 tests/live.py for isolation')
  require('opvi').setup({ status = { interval = 300, timeout = 90000 } })
  local connected, failure
  require('opvi.session').connect(vim.fn.getcwd(), function(s, err) connected, failure = s, err end)
  assert(vim.wait(40000, function() return connected ~= nil or failure ~= nil end, 10), 'Connect timed out')
  assert(connected, failure)
  H.pin_free_model(connected.id, vim.env.OPVI_E2E_MODEL or 'opencode/space-bunny-free')
  -- Explicit title avoids invoking an unrelated title-generation model.
  H.request('patch', '/api/session/' .. connected.id, { title = 'Opvi isolated free-model test' })
  vim.cmd('edit lua/opvi/health.lua')
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  require('opvi.ui.ask').open = function(_, _, cb)
    cb('Read @this. Reply with exactly the vim.health.start call in that file. Do not edit files.')
  end
  require('opvi').ask()
  assert(vim.wait(35000, function() return require('opvi').last_message_id ~= nil end, 10), 'Prompt not accepted')
  local message = require('opvi').last_message_id
  local key = connected.id .. ':' .. message
  assert(vim.wait(95000, function() return require('opvi.status').results[key] ~= nil end, 50), 'Agent completion timed out')
  local result = require('opvi.status').results[key]
  assert(result.state == 'succeeded', result.error or result.state)
  assert(table.concat(result.texts, '\n'):find("vim.health.start('Opvi')", 1, true), 'Expected answer missing')
  local session = H.request('get', '/api/session/' .. connected.id).data
  assert(session.cost == 0, 'Unexpected nonzero session cost')
  print('E2E PASS: confirmed free model, accepted input, actual answer, successful idle, cost=0')
end
local ok, err = xpcall(main, debug.traceback)
require('opvi').disconnect()
if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit 1') else vim.cmd('qa!') end
