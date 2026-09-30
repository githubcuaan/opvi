local M = {}

function M.request(method, path, body)
  local done, value, failure = false, nil, nil
  require('opvi.transport').request(method, path, body, function(result, err)
    value, failure, done = result, err, true
  end, true)
  assert(vim.wait(35000, function() return done end, 10), 'API timed out: ' .. path)
  assert(value, failure)
  return value
end

function M.pin_free_model(id, model)
  local provider, name = model:match('^([^/]+)/(.+)$')
  assert(provider and name, 'Explicit provider/model required')
  local catalog = M.request('get', '/api/model').data
  local free = false
  for _, entry in ipairs(catalog or {}) do
    if entry.providerID == provider and entry.id == name then
      assert(type(entry.cost) == 'table' and #entry.cost > 0, 'Model pricing missing')
      for _, cost in ipairs(entry.cost) do
        assert(cost.input == 0 and cost.output == 0 and cost.cache and cost.cache.read == 0 and cost.cache.write == 0,
          'Live tests require a zero-cost model')
      end
      free = true
    end
  end
  assert(free, 'Free model not found in server catalog: ' .. model)
  M.request('post', '/api/session/' .. id .. '/model', { model = { providerID = provider, id = name } })
  local session = M.request('get', '/api/session/' .. id).data
  assert(session and session.model and session.model.providerID == provider and session.model.id == name,
    'Model switch not confirmed; refusing to send a prompt')
end

return M
