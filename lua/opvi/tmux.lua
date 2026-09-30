local M = {}
local function run(args, cb)
  require('opvi.process').run(vim.list_extend({ 'tmux' }, args), {}, function(out, err)
    if out then return cb(vim.trim(out.stdout or '')) end
    cb(nil, err and err.message or 'tmux request failed')
  end)
end
function M.option(name, cb)
  run({ 'show-option', '-gqv', name }, cb)
end
function M.api_command(cb)
  local override = require('opvi.config').opts.api.command
  if override then return cb(override) end
  M.option('@opencode_api_command', function(value, err)
    if not value then return cb(nil, err) end
    if value ~= '' then return cb(value) end
    M.option('@opencode_command', function(cmd, failure)
      if not cmd then return cb(nil, failure) end
      cb((cmd ~= '' and cmd or 'opencode') .. ' api')
    end)
  end)
end
function M.binding(target, cb)
  run({ 'show-option', '-qv', '-t', target, '@opencode_session_id' }, function(id, err)
    if id and id ~= '' and not id:match('^ses[%w_-]+$') then return cb(nil, 'Invalid session binding') end
    cb(id, err)
  end)
end
function M.resolve(directory, cb)
  local pane = vim.env.TMUX_PANE
  if not pane then return cb(nil, 'Opvi requires Neovim inside tmux') end
  run({ 'display-message', '-p', '-t', pane, '#{session_name}\t#{window_id}\t#{socket_path}' }, function(info, err)
    if not info then return cb(nil, err) end
    local name, window, socket = info:match('^(.-)\t(.-)\t(.*)$')
    if not name then return cb(nil, 'Cannot resolve invoking tmux pane') end
    M.option('@opencode_session_prefix', function(prefix, failure)
      if not prefix then return cb(nil, failure) end
      prefix = prefix ~= '' and prefix or 'opencode-'
      if name:sub(1, #prefix) == prefix then return cb({ target = name, socket = socket, directory = directory, window = window }) end
      local manager = require('opvi.config').opts.tmux.manager_path
      require('opvi.process').run({ 'bash', '-c', 'set -e; . "$1/scripts/helpers.sh"; session_hash "$2"', 'opvi', manager, directory }, {}, function(hash, hash_error)
        if not hash then return cb(nil, hash_error and (hash_error.message or tostring(hash_error)) or 'Cannot hash project directory') end
        cb({ target = prefix .. vim.trim(hash.stdout or ''), socket = socket, directory = directory, window = window })
      end)
    end)
  end)
end
function M.ensure(target, cb)
  local function lookup(done)
    run({ 'list-sessions', '-F', '#{session_name}\t#{session_id}' }, function(out, err)
      if not out then return done(nil, err) end
      for line in out:gmatch('[^\n]+') do
        local name, id = line:match('^(.-)\t(.*)$')
        if name == target.target then return done(id) end
      end
      done(false)
    end)
  end
  lookup(function(id, failure)
    if id == nil then return cb(nil, failure) end
    if id then return cb(id) end
    local opts = require('opvi.config').opts
    require('opvi.process').run({ opts.tmux.manager_path .. '/scripts/start.sh', target.directory, target.window },
      { timeout = opts.api.startup_timeout + opts.api.timeout * 2 }, function(result, err)
        if not result then return cb(nil, err and err.message or 'Manager startup failed') end
        lookup(function(created, lookup_error) cb(created or nil, lookup_error or (not created and 'Manager did not create target session' or nil)) end)
      end)
  end)
end
function M.bind(target, id, cb)
  run({ 'set-option', '-t', target, '@opencode_session_id', id }, cb)
end
return M
