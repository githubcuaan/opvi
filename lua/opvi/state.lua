-- Connection state for statusline consumers (lualine, winbar, others).
-- Emits User OpviStateChanged whenever a consumer must redraw.
local M = { phase = 'idle', session = nil, title = nil, error = nil }

local function emit()
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'OpviStateChanged',
    data = { phase = M.phase, session_id = M.session and M.session.id or nil, title = M.title },
  })
end

local function clean(value)
  if type(value) ~= 'string' then return nil end
  local text = vim.trim(value:gsub('%s+', ' '))
  return text ~= '' and text or nil
end

function M.set(phase, session, title, err)
  local changed = M.phase ~= phase
    or (M.session and M.session.id) ~= (session and session.id)
    or clean(title) ~= M.title
    or M.error ~= err
  M.phase, M.session, M.title, M.error = phase, session, clean(title), err
  if changed then emit() end
  return changed
end

function M.clear()
  return M.set('idle', nil, nil, nil)
end

---Refresh the bound session title. OpenCode titles a conversation after a turn.
function M.refresh_title()
  local session = M.session
  if not session then return end
  require('opvi.transport').request('get', '/api/session/' .. session.id, nil, function(body)
    if M.session ~= session then return end
    local data = body and body.data
    if type(data) ~= 'table' or data.id ~= session.id then return end
    M.set(M.phase, session, data.title)
  end)
end

return M