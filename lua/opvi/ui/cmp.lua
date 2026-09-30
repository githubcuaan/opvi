-- In-process completion provider, adapted from opencode.nvim (MIT).
return {
  name = 'opvi_ask_cmp',
  cmd = function(_, config)
    local closing = false
    local request_id = 0
    return {
      request = function(method, params, callback)
        request_id = request_id + 1
        if method == 'initialize' then
          callback(nil, { capabilities = { completionProvider = { triggerCharacters = { '@' } } } })
        elseif method == 'textDocument/completion' then
          local items = {}
          local edit_range
          if params.textDocument and params.position then
            -- Snacks prompt buffers may be unnamed; their URI cannot be mapped
            -- back to the original buffer with uri_to_bufnr alone.
            local buf = config and config.opvi_bufnr or vim.uri_to_bufnr(params.textDocument.uri)
            local line = vim.api.nvim_buf_get_lines(buf, params.position.line, params.position.line + 1, false)[1] or ''
            local valid, col = pcall(vim.str_byteindex, line, params.position.character, true)
            if not valid then callback(nil, {}); return true, request_id end
            local first = line:sub(1, col):find('@[%w_]*$')
            if first then
              local _, utf16 = vim.str_utfindex(line, first - 1)
              edit_range = { start = { line = params.position.line, character = utf16 }, ['end'] = params.position }
            end
          end
          for key in pairs(require('opvi.context').builders()) do
            table.insert(items, { label = key, insertText = key,
              textEdit = edit_range and { range = edit_range, newText = key } or nil,
              kind = vim.lsp.protocol.CompletionItemKind.Variable })
          end
          callback(nil, items)
        elseif method == 'shutdown' then callback(nil, nil)
        else callback(nil, nil) end
        return true, request_id
      end,
      notify = function() return true end,
      is_closing = function() return closing end,
      terminate = function() closing = true end,
    }
  end,
}
