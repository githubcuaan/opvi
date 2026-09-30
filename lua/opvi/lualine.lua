-- lualine component:
--   lualine_c = { require('opvi.lualine').spec() }
--
-- One muted gray for every state. The glyph already carries the state, so extra
-- colors only add noise and can clash with a custom statusline background.
local M = { connected = '󰚩', idle = '󱚧', fg = '#585858', max_width = 40 }

---Cut text to a display width, marking the cut with an ellipsis.
local function truncate(text, limit)
  if not limit or limit <= 0 or vim.fn.strdisplaywidth(text) <= limit then return text end
  local cut = limit - 3
  while cut > 0 and vim.fn.strdisplaywidth(text:sub(1, cut)) > cut do
    cut = cut - 1
  end
  return text:sub(1, cut) .. '...'
end

---Returns the statusline text for the current connection state.
function M.render()
  local state = require('opvi.state')
  if state.phase == 'connected' then
    return M.connected .. ' ' .. truncate(state.title or state.session.id, M.max_width)
  end
  return M.idle
end

---Returns the lualine color for the current connection state.
function M.color()
  return { fg = M.fg }
end

function M.component()
  return M.render()
end

---Returns a ready lualine component table: lualine_c = { require('opvi.lualine').spec() }
function M.spec()
  return { M.component, color = M.color }
end

---Override the glyphs, color, or title width:
---   require('opvi').setup({ lualine = { fg = '#999999', max_width = 30 } })
---   max_width = 0 disables truncation.
function M.setup(opts)
  opts = opts or {}
  M.connected, M.idle = opts.connected or M.connected, opts.idle or M.idle
  M.fg = opts.fg or M.fg
  M.max_width = opts.max_width == nil and M.max_width or opts.max_width
  return M
end

return M