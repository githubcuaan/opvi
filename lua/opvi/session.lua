local M = { pending = {}, generation = 0 }

function M.connect(directory, callback)
  local generation = M.generation
  local tmux, api = require('opvi.tmux'), require('opvi.transport')
  tmux.resolve(directory, function(target, err)
    if generation ~= M.generation then return end
    if not target then return callback(nil, err) end
    local key = (target.socket or '') .. ':' .. target.target
    if M.pending[key] then table.insert(M.pending[key], callback); return end
    M.pending[key] = { callback }
    require('opvi.lock').acquire(key, function(release, lock_error)
      if generation ~= M.generation then if release then release() end; return end
      local function finish(value, failure)
        if release then release() end
        if generation ~= M.generation then return end
        local callbacks = M.pending[key] or {}
        M.pending[key] = nil
        if value then M.connected = value end
        for _, cb in ipairs(callbacks) do cb(value, failure) end
      end
      if not release then return finish(nil, lock_error) end
      -- The lock spans startup, the binding re-read, creation, and binding write.
      tmux.ensure(target, function(tmux_id, failure)
        if not tmux_id then return finish(nil, failure) end
        tmux.binding(tmux_id, function(id, binding_error)
          if not id then return finish(nil, binding_error) end
          local function validate(session_id)
            api.request('get', '/api/session/' .. session_id, nil, function(body, api_error)
              local data = body and body.data
              if type(data) ~= 'table' or data.id ~= session_id or type(data.location) ~= 'table'
                  or type(data.location.directory) ~= 'string' then
                return finish(nil, api_error or 'Invalid or stale session binding')
              end
              finish({ id = session_id, target = tmux_id, cwd = data.location.directory })
            end)
          end
          if id ~= '' then return validate(id) end
          api.request('get', '/api/info', nil, function(info, ready_error)
            if not info then return finish(nil, ready_error) end
            api.request('post', '/api/session', { location = { directory = directory } }, function(body, create_error)
              local data = body and body.data
              if type(data) ~= 'table' or type(data.id) ~= 'string' or not data.id:match('^ses[%w_-]+$') then
                return finish(nil, create_error or 'Invalid created session ID')
              end
              -- External manager rebinds do not participate in our lock. Never
              -- overwrite a binding that appeared while the API was creating.
              tmux.binding(tmux_id, function(current, read_error)
                if not current then return finish(nil, read_error) end
                if current ~= '' then
                  return finish(nil, 'Binding changed during creation; reconnect. Unbound conversation: ' .. data.id)
                end
                tmux.bind(tmux_id, data.id, function(result, bind_error)
                  if result == nil then return finish(nil, bind_error) end
                  vim.notify('Opvi: conversation bound; reopen existing TUI through manager to display it')
                  validate(data.id)
                end)
              end)
            end)
          end, true)
        end)
      end)
    end)
  end)
end

function M.disconnect()
  M.generation = M.generation + 1
  M.pending = {}
  M.connected = nil
  require('opvi.lock').cancel()
end

return M
