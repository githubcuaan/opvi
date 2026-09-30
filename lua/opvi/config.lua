local M = {}
M.opts = {}

function M.setup(opts)
  M.opts = vim.tbl_deep_extend('force', {
    tmux = { manager_path = vim.fn.expand('~/.tmux/plugins/tmux-opencode-session-manager') },
    api = { command = nil, timeout = 10000, startup_timeout = 30000, lock_timeout = 60000 },
    ask = { prompt = 'Ask OpenCode: ', snacks = {} },
    contexts = {},
    status = { enabled = true, interval = 1000, timeout = 300000 },
  }, opts or {})
end

M.setup()
return M
