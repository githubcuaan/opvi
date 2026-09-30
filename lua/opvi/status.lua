local M = { entries = {}, results = {} }
local ns = vim.api.nvim_create_namespace('OpviStatus')

local function remove(entry, keep_mark)
  M.entries[entry.key] = nil
  if entry.timer then entry.timer:stop(); entry.timer:close(); entry.timer = nil end
  if not keep_mark and entry.mark and vim.api.nvim_buf_is_valid(entry.buf) then
    vim.api.nvim_buf_del_extmark(entry.buf, ns, entry.mark)
  end
end

function M.stop(buf)
  for _, entry in pairs(vim.tbl_extend('force', {}, M.entries)) do
    if not buf or entry.buf == buf then remove(entry) end
  end
  if buf then
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1) end
  else
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buffer) then vim.api.nvim_buf_clear_namespace(buffer, ns, 0, -1) end
    end
  end
end

local function draw(entry, text, group)
  if not entry.decorate or not vim.api.nvim_buf_is_valid(entry.buf) then return end
  local row = entry.row
  if entry.mark then
    local position = vim.api.nvim_buf_get_extmark_by_id(entry.buf, ns, entry.mark, {})
    if #position > 0 then row = position[1] end
  end
  row = math.min(row, vim.api.nvim_buf_line_count(entry.buf) - 1)
  entry.mark = vim.api.nvim_buf_set_extmark(entry.buf, ns, row, 0, {
    id = entry.mark, virt_lines = { { { 'opvi: ' .. text, group } } }, virt_lines_above = true,
  })
end

function M.track(session, context, message_id, decorate)
  if not require('opvi.config').opts.status.enabled then return end
  local key = session.id .. ':' .. message_id
  local entry = { key = key, buf = context.buf, decorate = decorate,
    row = (context.range and context.range.from[1] or context.cursor[1]) - 1, started = vim.uv.now() }
  if M.entries[key] then remove(M.entries[key]) end
  M.entries[key] = entry
  draw(entry, 'submitted', 'Comment')
  local config = require('opvi.config').opts.status
  local function alive() return M.entries[key] == entry end
  local function finish(result)
    if result.state ~= 'succeeded' then
      draw(entry, result.error or result.state, 'DiagnosticError')
      vim.notify('Opvi: ' .. result.state .. (result.error and (': ' .. result.error) or ''), vim.log.levels.ERROR)
    end
    remove(entry, result.state ~= 'succeeded')
    M.results[key] = result
    vim.api.nvim_exec_autocmds('User', { pattern = 'OpviPromptFinished', data = {
      session_id = session.id, message_id = message_id, state = result.state, error = result.error,
    } })
  end
  entry.timer = vim.uv.new_timer()
  entry.timer:start(0, config.interval, vim.schedule_wrap(function()
    if not alive() or entry.inflight then return end
    if not vim.api.nvim_buf_is_valid(entry.buf) then remove(entry); return end
    if vim.uv.now() - entry.started > config.timeout then
      return finish({ state = 'unknown', error = 'Status tracking timed out; execution may still be running' })
    end
    entry.inflight = true
    require('opvi.tmux').binding(session.target, function(id, binding_error)
      if not alive() then return end
      if not id then
        entry.inflight, entry.last_error = false, binding_error
        draw(entry, 'status unavailable (retrying)', 'DiagnosticWarn')
        return
      end
      if id ~= session.id then remove(entry); return end
      require('opvi.progress').read(session.id, message_id, function(result, err)
        entry.inflight = false
        if not alive() then return end
        if not result then
          entry.last_error = err
          draw(entry, 'status unavailable (retrying)', 'DiagnosticWarn')
          return
        end
        entry.last_error = nil
        if result.finished then return finish(result) end
        draw(entry, result.tool and ('using ' .. result.tool) or result.state, 'Comment')
      end, alive)
    end)
  end))
end

return M
