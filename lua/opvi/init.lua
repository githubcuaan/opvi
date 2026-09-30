local M = {}
local epoch = 0
local connection_epoch = 0
local request_id = 0
M.requests = {}
local function notify(err) vim.notify('Opvi: ' .. tostring(err), vim.log.levels.ERROR) end

function M.setup(opts)
  require('opvi.config').setup(opts)
  vim.api.nvim_set_hl(0, 'OpviContextPlaceholder', { link = 'Special', default = true })
end

function M.connect()
  require('opvi.session').connect(vim.fn.getcwd(), function(session, err)
    if not session then notify(err) else vim.notify('Opvi: connected ' .. session.id) end
  end)
end

local function send(text, context, session, generation)
  if generation ~= epoch then return end
  if not text or vim.trim(text) == '' then
    context:clear(true); return
  end
  M.last_prompt = text
  local lifetime = connection_epoch
  require('opvi.tmux').binding(session.target, function(id, err)
    if generation ~= epoch then return end

    if id ~= session.id then
      context:clear(true); notify(err or 'Session binding changed; ask again'); return
    end

    local ok, rendered = pcall(context.render, context, text)
    if not ok then
      context:clear(true); notify(rendered); return
    end
    request_id = request_id + 1
    local request = { id = request_id, session_id = session.id, text = text, rendered = rendered, state = 'sending' }
    M.requests[request.id] = request
    context:clear()
    require('opvi.transport').request('post', '/api/session/' .. session.id .. '/prompt', { text = rendered },
      function(body, failure)
        if lifetime ~= connection_epoch then return end
        local data = body and body.data
        if type(data) ~= 'table' then
          request.state, request.error = 'unknown', failure or 'Missing acknowledgement'
          if generation == epoch then context:clear(true) end
          notify(request.error .. '; payload retained in require("opvi").requests[' .. request.id
            .. ']; check session before retrying'); return
        end
        if type(data.id) ~= 'string' or not data.id:match('^msg[%w_-]+$') then
          request.state, request.error = 'unknown', 'Invalid acknowledgement'
          notify('Invalid prompt acknowledgement'); return
        end
        M.last_message_id = data.id
        request.state, request.message_id = 'accepted', data.id
        require('opvi.status').track(session, context, data.id, text:match('@this%f[^%w_]') ~= nil)
        vim.api.nvim_exec_autocmds('User',
          { pattern = 'OpviPromptAccepted', data = { session_id = session.id, message_id = data.id } })
        vim.notify('Opvi: prompt accepted')
      end)
  end)
end

local function begin(text, input)
  if M.context then M.context:clear() end

  epoch = epoch + 1
  local generation = epoch
  local context = require('opvi.context').capture()

  M.context = context
  require('opvi.session').connect(context.directory, function(session, err)
    if generation ~= epoch then return end
    if not session then
      context:clear(true); notify(err); return
    end
    context.server = session
    if input then
      require('opvi.ui.ask').open(text, context, function(value) send(value, context, session, generation) end)
    else
      send(text, context, session, generation)
    end
  end)
end

function M.ask(default) begin(default, true) end

function M.prompt(text) begin(text, false) end

function M.disconnect()
  epoch = epoch + 1
  connection_epoch = connection_epoch + 1
  if M.context then
    M.context:clear(); M.context = nil
  end
  require('opvi.status').stop()
  require('opvi.transport').cancel()
  require('opvi.session').disconnect()
  for _, request in pairs(M.requests) do
    if request.state == 'sending' then request.state = 'unknown' end
  end
end

return M
