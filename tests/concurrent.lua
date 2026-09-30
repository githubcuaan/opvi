local root = assert(vim.env.OPVI_TEST_ROOT)
vim.opt.rtp:prepend(root)
require('opvi').setup({ api = { command = { 'python3', root .. '/tests/fake_api.py', assert(vim.env.OPVI_TEST_STATE) } } })
local result, failure
require('opvi.session').connect(vim.fn.getcwd(), function(s,e) result,failure=s,e end)
local ok = vim.wait(10000,function() return result~=nil or failure~=nil end,10)
if not ok or not result or result.id~='ses_fixture' then
  io.stderr:write(tostring(failure or 'connection failed') .. '\n')
  vim.cmd('cquit 1')
end
require('opvi').disconnect()
print('connected ' .. result.id)
vim.cmd('qa!')
