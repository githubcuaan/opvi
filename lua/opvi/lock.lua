local M = { holders = {} }
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h:h')

function M.acquire(key, callback)
  local directory = vim.fn.stdpath('cache') .. '/opvi-locks'
  vim.fn.mkdir(directory, 'p', 448)
  local path = directory .. '/' .. vim.fn.sha256(key)
  local job, released, ready = nil, false, false
  local function release()
    if released then return end
    released = true
    if job then job:write(nil); M.holders[job] = nil end
  end
  local ok, err = pcall(function()
    job = vim.system({ 'python3', root .. '/scripts/lock.py', path,
      tostring(require('opvi.config').opts.api.lock_timeout / 1000) }, {
      text = true, stdin = true,
      stdout = function(failure, chunk)
        if failure or not chunk or ready then return end
        ready = true
        vim.schedule(function()
          if not released then callback(release) end
        end)
      end,
    }, function(result)
      vim.schedule(function()
        M.holders[job] = nil
        if not ready and not released then
          released = true
          callback(nil, vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr) or 'Session lock failed')
        end
      end)
    end)
    M.holders[job] = release
  end)
  if not ok then callback(nil, tostring(err)) end
end

function M.cancel()
  local releases = vim.tbl_values(M.holders)
  for _, release in ipairs(releases) do release() end
end

return M
