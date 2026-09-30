-- Read only the history after the accepted user message. Session-wide outcome
-- may belong to an older turn, and an inactive session may still have input queued.
local M = {}

function M.evaluate(messages, message_id)
  local found = false
  local result = { state = 'submitted', texts = {} }
  for _, message in ipairs(messages) do
    if message.id == message_id then found = true
    elseif found then
      if message.type == 'assistant' then
        result.state = 'running'
        if message.error then
          result.error = type(message.error) == 'table' and (message.error.message or vim.inspect(message.error)) or tostring(message.error)
        end
        for _, part in ipairs(message.content or {}) do
          if part.type == 'text' then table.insert(result.texts, part.text or '') end
          if part.type == 'tool' and part.state and (part.state.status == 'running' or part.state.status == 'streaming') then
            result.tool = part.name
          end
        end
      elseif message.type == 'idle' then
        result.state = message.outcome
        result.finished = true
        return result
      end
    end
  end
  result.observed = found
  return result
end

function M.read(session_id, message_id, callback, alive)
  local messages, cursors = {}, {}
  local limit = 20
  local function page(cursor)
    if alive and not alive() then return end
    local query = cursor and ('cursor=' .. cursor:gsub('[^%w%-._~]', function(c) return string.format('%%%02X', c:byte()) end)) or 'order=desc'
    require('opvi.transport').request('get', '/api/session/' .. session_id .. '/message?limit=' .. limit .. '&' .. query, nil, function(body, err, kind)
      if alive and not alive() then return end
      -- Only this idempotent GET may retry. Do not advance its cursor or append
      -- messages until a whole page has been decoded successfully.
      if not body and kind == 'invalid_json' and limit > 1 then
        limit = math.max(1, math.floor(limit / 2))
        return page(cursor)
      end
      if type(body) ~= 'table' or type(body.data) ~= 'table' then return callback(nil, err or 'Invalid message history') end
      local found = false
      for _, message in ipairs(body.data) do
        if type(message) ~= 'table' or type(message.id) ~= 'string' then return callback(nil, 'Invalid message') end
        table.insert(messages, message)
        if message.id == message_id then found = true; break end
      end
      local next_cursor = body.cursor and body.cursor.next
      if not found and #body.data > 0 and type(next_cursor) == 'string' and not cursors[next_cursor] then
        cursors[next_cursor] = true
        return page(next_cursor)
      end
      if not found then return callback({ state = 'submitted', texts = {}, observed = false }) end
      local chronological = {}
      for i = #messages, 1, -1 do table.insert(chronological, messages[i]) end
      callback(M.evaluate(chronological, message_id))
    end)
  end
  page()
end

return M
