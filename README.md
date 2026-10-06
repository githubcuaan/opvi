# opvi.nvim

Neovim Ask UI for OpenCode V2, bound to conversations managed by
[tmux-opencode-session-manager](https://github.com/githubcuaan/tmux-opencode-session-manager).

## Install

Requires Neovim 0.11+ (`getregionpos` for accurate selections), OpenCode V2, tmux, and the manager's dependencies
(Bash, Python 3, jq, a supported hash utility). Run Neovim inside tmux.
Optional `folke/snacks.nvim` supplies the floating input UI.

Local lazy.nvim configuration:

```lua
{
  dir = '/home/andev/projects/opvi',
  name = 'opvi.nvim',
  opts = {
    tmux = {
      manager_path = '/home/andev/projects/tmux-opencode-session-manager',
    },
  },
  keys = {
    { '<leader>ca', function() require('opvi').ask('@this: ') end,
      mode = { 'n', 'x' }, desc = 'Ask OpenCode' },
    { '<leader>cb', function() require('opvi').ask('@buffer: ') end,
      desc = 'Ask about buffer' },
  },
}
```

## Usage

`:OpviConnect`, `:OpviAsk [initial text]`, `:OpviDisconnect`, `:checkhealth opvi`.

```lua
require('opvi').ask('@this: ') -- input, normal or visual mode
require('opvi').prompt('Explain @buffer') -- send immediately
```

## Statusline

`require('opvi.lualine').component` shows whether this Neovim is bound to a
conversation: `󰚩 <session title>` when connected, `󱚧` otherwise.

A function component with options must be wrapped in its own table:

```lua
lualine_c = {
  {
    require('opvi.lualine').component,
    color = function() return require('opvi.lualine').color() end,
  },
},
```

`require('opvi.lualine').spec()` returns that whole `{ component, color = ... }`
pair, so `lualine_c = { require('opvi.lualine').spec() }` also works.

Icons and color are overridable, all optional:

```lua
require('opvi').setup({
  lualine = { fg = '#999999', connected = '', idle = '' },
})
```

The color defaults to a muted gray `#585858`. Keep one color for every state:
the glyph already carries the state, and a fixed color stays readable on any
statusline background. A highlight group name does not work here, because
lualine resolves component colors with `nvim_get_hl_by_name` and crashes when a
runtime-created group cannot be resolved.

State lives in `require('opvi.state')`: `phase` is `idle`, `connecting`,
`connected`, or `error`, plus `session`, `title`, and `error`. Every change
emits `User OpviStateChanged` with `phase`, `session_id`, and `title` in the
event data, so other consumers only need a redraw:

```lua
vim.api.nvim_create_autocmd('User', {
  pattern = 'OpviStateChanged',
  callback = function() vim.lualine.redrawstatus({ refresh = { 'statusline' } }) end,
})
```

The title refreshes on connect and after each accepted prompt, once OpenCode has
generated it; before that the component shows the session ID. `:OpviDisconnect`
returns it to `󱚧`.

Context placeholders: `@this`, `@buffer`, `@buffers`, `@visible`,
`@diagnostics`, `@quickfix`, `@marks`. Visual selections are captured inline before
connecting, preserving UTF-8, tabs, block selections and exclusive selection.
Unsaved/unnamed buffers are also inline. Saved buffers use file/line/column references.
Native input supports completion; Snacks input starts an in-process LSP completion
provider (enable your completion plugin's LSP source) and supports omnifunc (`<C-x><C-o>`).
Custom contexts are callbacks receiving the captured context:

```lua
require('opvi').setup({
  contexts = { ['@project'] = function(context) return context.directory end },
  ask = { prompt = 'Ask OpenCode: ', snacks = {} },
  api = { timeout = 10000, startup_timeout = 30000, lock_timeout = 60000 }, -- milliseconds
  status = { enabled = true, interval = 1000, timeout = 300000 },
})
```

## Connection behavior

Inside a manager session, use its binding. Else resolve the manager session
from Neovim's current directory and the manager's prefix/hash convention.
Missing sessions are started through `scripts/start.sh`. Existing unbound
sessions receive a new conversation; reopen their TUI through the manager.
Deleted/stale bindings produce an error rather than silently replacing them.
Bindings belong to tmux sessions, shared by clients attached to that session.
Opvi serializes connection creation across Neovim processes with a Python/fcntl
lock keyed by tmux socket and session name. The lock is released on normal exit,
disconnect, or process death. Manager scripts run inside that critical section;
external manager launches/rebinds do not share the lock, so detected binding
changes abort rather than being overwritten. Resolved targets use stable tmux IDs.

API calls inherit `@opencode_api_command`, or `@opencode_command` plus `api`.
CLI stdout is captured in a private anonymous temporary file and then drained
fully to Neovim. This avoids truncated JSON when OpenCode exits before large
piped output is flushed, including a single message containing large tool output.
An explicit `api.command = { 'opencode', 'api', ... }` overrides this for Opvi;
keep its server context identical to the manager. The manager retains its own
startup/request timeout settings. Opvi request timeouts are configured above.

Ask captures selection before asynchronous work and validates the binding again
before sending. Requests use `POST /api/session/{id}/prompt` with `{text=...}`.
Acknowledgement means accepted input, not completed generation. Failed prompts
remain in `require('opvi').last_prompt`; POST requests are never automatically
retried, since a timeout may occur after acceptance.

Each accepted message is tracked separately. For `@this`, extmarks follow edits
and display submitted/running/current tool. Tracking reads paginated history
back to that message and waits for its subsequent `idle` outcome; absence from
the active map is never treated as completion. Failed/interrupted turns retain
an error decoration. Tracking timeout reports unknown, not success, and does not
stop server execution. `:OpviDisconnect` clears decorations and stops polling.
Use `:OpviClearStatus` to dismiss finished/error decorations in the current buffer,
or `:OpviClearStatus!` for all buffers, without disconnecting or stopping active
tracking. Lua: `require('opvi').clear_status()` (current buffer), or
`require('opvi').clear_status(false)` (all buffers). Stored results remain available.
History is fetched in small pages; malformed JSON retries the same read-only
page at a smaller size. A read failure shows `status unavailable (retrying)`,
not an agent failure. Its detail is available in the tracked entry's `last_error`.
Responses, permissions, and questions remain in OpenCode's TUI. V1 TUI commands
and agent mentions are not emulated.

`User OpviPromptAccepted` includes `session_id` and `message_id`.
`User OpviPromptFinished` additionally includes `state` and optional `error`.
`require('opvi').requests` retains submission text, rendered payload, acknowledgement
and ambiguous-error state. Starting another Ask does not discard pending POST
acknowledgements. `require('opvi.status').results` is keyed by `sessionID:messageID`.

## Tests

```sh
nvim --headless -u NONE -l tests/run.lua
nvim --headless -u NONE -l tests/ui.lua
python3 tests/concurrency.py
```

UI tests need Snacks installed (`OPVI_SNACKS_PATH` overrides its path). Unit and
concurrency tests never send real prompts. Live tests create a private tmux server
and a throwaway conversation, verify zero-cost pricing and the actual selected
model before sending, then assert the assistant's answer and successful outcome.
Model defaults to `opencode/space-bunny-free`; `OPVI_E2E_MODEL` may select another
catalog-confirmed zero-cost model. Missing model, switch error, or paid pricing
fails the test before submission. The runner cleans up its own session and tmux
server, including on failure:

```sh
python3 tests/live.py
```

Ask UI/context behavior adapted from Nick van Dyke's MIT-licensed
`opencode.nvim`; see LICENSE.
