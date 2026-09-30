# Opvi - Opencode w nvim

a nvim plugin connect nvim w opencode v2

## Idea

this plugin will take the ui of `/home/andev/.local/share/nvim/lazy/opencode.nvim`

we cannot using that plugin cus it only support opencode v1

## Features

### Connect to session

opencode session is open by `/home/andev/projects/tmux-opencode-session-manager`

each client have it own binded `@opencode_session_id`.

flow:
connect to sesssion:
- if not have session -> create w Post api/session/
- if have session -> conect the session w `@opencode_session_id`

### Ask

the ask features is like the ask of opencode.nvim -> using same ui of that and take its logic of @this and @buffer ... 

using post api/{sesssion_id}/prompt for send the promtp

### Notes
i got additional config for this plguins in v1, migreate it to v2, add to this plugin `nvim/lua/dnhfan/plugins/configs/opencode/server.lua` 

