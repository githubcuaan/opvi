-- Shared subprocess layer. No dependency on tmux or the HTTP client.
local M = { jobs = {}, generation = 0 }

function M.run(argv, opts, callback)
  local generation, job = M.generation, nil
  local ok, err = pcall(function()
    job = vim.system(argv, vim.tbl_extend('force', { text = true, timeout = 10000 }, opts or {}), function(result)
      vim.schedule(function()
        M.jobs[job] = nil
        if generation ~= M.generation then return end
        if result.code ~= 0 then
          local detail = vim.trim(result.stderr or '')
          callback(nil, { code = result.code, message = detail ~= '' and detail or ('Command failed: ' .. result.code) })
        else
          callback(result)
        end
      end)
    end)
    M.jobs[job] = true
  end)
  if not ok then callback(nil, { code = -1, message = tostring(err) }) end
end

function M.cancel()
  M.generation = M.generation + 1
  for job in pairs(M.jobs) do job:kill(15) end
end

return M
