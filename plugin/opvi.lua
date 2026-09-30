if vim.g.loaded_opvi then return end
vim.g.loaded_opvi = true

vim.api.nvim_create_user_command('OpviConnect', function() require('opvi').connect() end, {})
vim.api.nvim_create_user_command('OpviAsk', function(opts) require('opvi').ask(opts.args) end, { nargs = '*' })
vim.api.nvim_create_user_command('OpviDisconnect', function() require('opvi').disconnect() end, {})

local group = vim.api.nvim_create_augroup('Opvi', { clear = true })

vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = function() require('opvi').disconnect() end })
vim.api.nvim_create_autocmd('DirChanged', { group = group, callback = function() require('opvi').disconnect() end })
vim.api.nvim_create_autocmd('BufDelete', {
  group = group,
  callback = function(event)
    local status = package.loaded['opvi.status']
    if status then status.stop(event.buf) end
  end
})
