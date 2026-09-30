local process = require('opvi.process')
local M = { run = process.run, cancel = process.cancel }


function M.request(method, path, body, callback, startup)
  local config = require('opvi.config').opts
  require('opvi.tmux').api_command(function(command, err)
    if not command then return callback(nil, err) end
    local args = { method, path }
    if body then vim.list_extend(args, { '--data', vim.json.encode(body) }) end
    local argv
    if type(command) == 'table' then
      argv = vim.list_extend(vim.deepcopy(command), args)
    else
      -- The manager explicitly allows a trusted shell command prefix. Request
      -- arguments remain positional parameters, never interpolated shell text.
      argv = { 'sh', '-c', 'exec ' .. command .. ' "$@"', 'opvi' }
      vim.list_extend(argv, args)
    end
    M.run(argv, { timeout = startup and config.api.startup_timeout or config.api.timeout }, function(output, failure)
      if not output then return callback(nil, failure and (failure.message or tostring(failure)) or 'Request failed') end
      local body = vim.trim(output.stdout or '')
      -- Endpoints differ: some answer with a `data` envelope, /api/info does not,
      -- and 204 responses have no body at all.
      if body == '' then return callback({}) end
      local ok, decoded = pcall(vim.json.decode, body)
      if not ok or type(decoded) ~= 'table' then
        return callback(nil, 'Invalid OpenCode API response')
      end
      if decoded.error ~= nil then
        local detail = type(decoded.error) == 'table' and (decoded.error.message or decoded.error.name) or
            tostring(decoded.error)
        return callback(nil, 'OpenCode API error: ' .. tostring(detail))
      end
      callback(decoded)
    end)
  end)
end

return M
