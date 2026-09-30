vim.opt.rtp:prepend(vim.fn.getcwd())
local function main()
  require('opvi').setup()
  dofile('plugin/opvi.lua')
  assert(vim.fn.exists(':OpviAsk') == 2 and vim.fn.exists(':OpviConnect') == 2)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'á🙂 some code' })
  local context = require('opvi.context').capture()
  local native
  vim.api.nvim_feedkeys('Explain @buffer\r', 't', false)
  require('opvi.ui.ask').open('', context, function(value) native = value end)
  assert(native == 'Explain @buffer', 'Native input did not submit expected text')
  print('PASS native input and commands')

  local path = vim.env.OPVI_SNACKS_PATH or vim.fn.expand('~/.local/share/nvim/lazy/snacks.nvim')
  assert(vim.fn.isdirectory(path) == 1, 'Set OPVI_SNACKS_PATH to run Snacks integration')
  vim.opt.rtp:prepend(path)
  require('snacks').config.input = { enabled = true }
  local value
  require('opvi.ui.ask').open('Explain @this', context, function(input) value = input or false end)
  local buf
  assert(vim.wait(3000, function()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do if vim.bo[b].filetype == 'opvi_ask' then buf = b; return true end end
  end), 'Snacks input not opened')
  assert(vim.wait(3000, function()
    local clients = vim.lsp.get_clients({ bufnr = buf })
    return clients[1] and clients[1].initialized
  end), 'Completion LSP did not initialize')
  assert(vim.wait(3000,function()
    return vim.api.nvim_buf_get_lines(buf,0,1,false)[1]=='Explain @this'
  end), 'Snacks default text not populated')
  local response
  vim.lsp.get_clients({bufnr=buf})[1]:request('textDocument/completion', {
    textDocument={uri=vim.uri_from_bufnr(buf)},position={line=0,character=13},
  }, function(err, result) assert(not err, vim.inspect(err)); response=result end, buf)
  assert(vim.wait(3000,function() return response~=nil end), 'Completion request timed out')
  assert(response[1].textEdit.range.start.character==8, 'Completion must replace @, not duplicate it')
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
  assert(vim.wait(3000, function() return value ~= nil end), 'Snacks submit timed out')
  assert(value == 'Explain @this', vim.inspect(value))
  value = nil
  require('opvi.ui.ask').open('cancel me', context, function(input) value = input or false end)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc><Esc>', true, false, true), 'x', false)
  assert(vim.wait(3000, function() return value ~= nil end), 'Snacks cancel timed out')
  assert(value == false)
  print('PASS Snacks input, completion startup, submit and cancel')
end
local ok, err = xpcall(main, debug.traceback)
if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit 1') else vim.cmd('qa!') end
