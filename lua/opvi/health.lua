local M = {}
function M.check()
  vim.health.start('Opvi')
  for _, cmd in ipairs({ 'opencode', 'tmux', 'bash', 'python3', 'jq' }) do
    if vim.fn.executable(cmd) == 1 then vim.health.ok(cmd) else vim.health.error('Missing executable: ' .. cmd) end
  end
  if vim.fn.has('nvim-0.11') == 1 then vim.health.ok('Neovim >= 0.11') else vim.health.error('Neovim >= 0.11 required (getregionpos)') end
  local path = require('opvi.config').opts.tmux.manager_path
  if vim.fn.filereadable(path .. '/scripts/start.sh') == 1 then vim.health.ok('Session manager: ' .. path)
  else vim.health.error('Set tmux.manager_path to session-manager installation') end
  if not vim.env.TMUX_PANE then vim.health.warn('Neovim is outside tmux') end
end
return M
