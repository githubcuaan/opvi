-- Adapted from opencode.nvim's Snacks/native Ask UI (MIT, Nick van Dyke).
local M = {}
function M.open(default, context, callback)
  local config = require('opvi.config').opts.ask
  local opts = { prompt = config.prompt, default = default or '', completion = 'customlist,v:lua.opvi_completion' }
  local ok, snacks = pcall(require, 'snacks')
  if ok and snacks.config.get('input', {}).enabled then
    opts = vim.tbl_deep_extend('force', opts, {
      icon = '󰚩 ',
      win = { title_pos = 'left', relative = 'cursor', row = -3, col = 0,
        bo = { filetype = 'opvi_ask' },
        on_buf = function(win)
          vim.bo[win.buf].omnifunc = 'v:lua.opvi_omnifunc'
          vim.lsp.start(vim.tbl_extend('force', require('opvi.ui.cmp'), { opvi_bufnr = win.buf }), {
            bufnr = win.buf,
            reuse_client = function(client) return client.config.opvi_bufnr == win.buf end,
          })
        end },
      highlight = function(text)
        local highlights = {}
        for start, token, finish in text:gmatch('()(@[%w_]+)()') do
          if require('opvi.context').builders()[token] then table.insert(highlights, { start - 1, finish - 1, 'OpviContextPlaceholder' }) end
        end
        return highlights
      end,
    }, config.snacks)
    snacks.input(opts, callback)
  else
    vim.ui.input(opts, callback)
  end
end
_G.opvi_completion = function(_, line)
  local prefix, word = line:match('^(.-)(@[%w_]*)$')
  if not prefix then return {} end
  local out = {}
  for key in pairs(require('opvi.context').builders()) do
    if key:sub(1, #word) == word then table.insert(out, prefix .. key) end
  end
  table.sort(out)
  return out
end
_G.opvi_omnifunc = function(findstart, base)
  if findstart == 1 then
    local before = vim.api.nvim_get_current_line():sub(1, vim.api.nvim_win_get_cursor(0)[2])
    return (before:find('@[%w_]*$') or (#before + 1)) - 1
  end
  return _G.opvi_completion('', base)
end
return M
