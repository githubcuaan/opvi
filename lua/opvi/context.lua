-- Context UI and placeholder behavior adapted from nickjvandyke/opencode.nvim.
local M = {}
M.__index = M
local ns = vim.api.nvim_create_namespace('OpviContext')

local function char_end(line, column)
  local last = math.min(column, #line)
  while last < #line do
    local byte = line:byte(last + 1)
    if byte < 128 or byte >= 192 then break end
    last = last + 1
  end
  return last
end

function M.capture()
  assert(vim.fn.exists('*getregionpos') == 1, 'Opvi requires Neovim 0.11+ for accurate visual selections')
  local self = setmetatable({
    buf = vim.api.nvim_get_current_buf(),
    win = vim.api.nvim_get_current_win(),
    cursor = vim.api.nvim_win_get_cursor(0),
    directory = vim.fn.getcwd()
  }, M)
  local mode = vim.fn.mode()
  if mode == 'v' or mode == 'V' or mode == '\22' then
    local anchor = vim.fn.getpos('v')
    local cursor = vim.fn.getcurpos()
    cursor = { self.buf, cursor[2], cursor[3], cursor[4] }
    anchor[1] = self.buf
    self.selection = { anchor = anchor, cursor = cursor, mode = mode }
    local options = { type = mode, exclusive = vim.o.selection == 'exclusive' }
    self.selection_text = table.concat(vim.fn.getregion(anchor, cursor, options), '\n')
    local positions = vim.fn.getregionpos(anchor, cursor, options)
    local a, b = { anchor[2], anchor[3] - 1 }, vim.deepcopy(self.cursor)
    if a[1] > b[1] or (a[1] == b[1] and a[2] > b[2]) then a, b = b, a end
    self.range = { from = a, to = b, kind = mode == 'V' and 'line' or mode == '\22' and 'block' or 'char' }
    if mode == '\22' and a[2] > b[2] then a[2], b[2] = b[2], a[2] end
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
    for _, position in ipairs(positions) do
      local row = position[1][2] - 1
      local line = vim.api.nvim_buf_get_lines(self.buf, row, row + 1, false)[1] or ''
      local first = math.max(0, position[1][3] - 1)
      local last = char_end(line, position[2][3])
      if first < #line then
        vim.api.nvim_buf_set_extmark(self.buf, ns, row, first,
          { end_col = math.min(last, #line), hl_group = 'Visual' })
      end
    end
  end
  return self
end

function M:clear(restore)
  if vim.api.nvim_buf_is_valid(self.buf) then vim.api.nvim_buf_clear_namespace(self.buf, ns, 0, -1) end
  if restore and self.range and vim.api.nvim_win_is_valid(self.win) and vim.api.nvim_win_get_buf(self.win) == self.buf then
    vim.api.nvim_set_current_win(self.win)
    if self.selection then
      vim.fn.setpos('.', self.selection.anchor)
      vim.cmd('normal! ' .. self.selection.mode)
      vim.fn.setpos('.', self.selection.cursor)
    end
  end
end

function M:location(buf, from, to, kind)
  if not vim.api.nvim_buf_is_valid(buf) then return '' end
  local path = vim.api.nvim_buf_get_name(buf)
  local first, last = from and from[1] or 1, to and to[1] or (from and from[1] or vim.api.nvim_buf_line_count(buf))
  local inline = path == '' or not vim.uv.fs_stat(path) or vim.bo[buf].modified or kind == 'block'
  if inline then
    local lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
    for i, line in ipairs(lines) do
      local a = from and from[2] and (i == 1 or kind == 'block') and from[2] or 1
      local b = to and to[2] and (i == #lines or kind == 'block') and to[2] or #line
      lines[i] = line:sub(a, char_end(line, b))
    end
    return (path ~= '' and path or '[unnamed]') ..
        ':' .. first .. '\n```' .. vim.bo[buf].filetype .. '\n' .. table.concat(lines, '\n') .. '\n```'
  end
  local cwd = self.server and self.server.cwd or self.directory
  if path:sub(1, #cwd + 1) == cwd .. '/' then path = path:sub(#cwd + 2) end
  if from then path = path .. ':L' .. from[1] .. (from[2] and ':C' .. from[2] or '') end
  if to then path = path .. '-L' .. to[1] .. (to[2] and ':C' .. to[2] or '') end
  return path
end

M.builtins = {
  ['@this'] = function(c)
    local r = c.range
    if c.selection_text then
      local path = vim.api.nvim_buf_get_name(c.buf)
      return (path ~= '' and path or '[unnamed]') .. ':L' .. r.from[1] .. '-L' .. r.to[1]
          .. '\n```' .. vim.bo[c.buf].filetype .. '\n' .. c.selection_text .. '\n```'
    end
    if r then
      return c:location(c.buf, { r.from[1], r.kind ~= 'line' and r.from[2] + 1 or nil },
        { r.to[1], r.kind ~= 'line' and r.to[2] + 1 or nil }, r.kind)
    end
    return c:location(c.buf, { c.cursor[1], c.cursor[2] + 1 })
  end,
  ['@buffer'] = function(c) return c:location(c.buf) end,
  ['@buffers'] = function(c)
    local out = {}
    for _, b in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do table.insert(out, c:location(b.bufnr)) end
    return table.concat(out, '\n')
  end,
  ['@visible'] = function(c)
    local out = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative == '' then
        table.insert(out,
          c:location(vim.api.nvim_win_get_buf(win), { vim.fn.line('w0', win) }, { vim.fn.line('w$', win) }))
      end
    end
    return table.concat(out, '\n')
  end,
  ['@diagnostics'] = function(c)
    local out = {}
    for _, d in ipairs(vim.diagnostic.get(c.buf)) do
      if not c.range or (d.lnum + 1 <= c.range.to[1] and (d.end_lnum or d.lnum) + 1 >= c.range.from[1]) then
        table.insert(out, c:location(c.buf, { d.lnum + 1, d.col + 1 }) .. ': ' .. d.message)
      end
    end
    return table.concat(out, '\n')
  end,
  ['@quickfix'] = function(c)
    local out = {}
    for _, q in ipairs(vim.fn.getqflist()) do
      if q.bufnr > 0 then
        table.insert(out,
          c:location(q.bufnr, { q.lnum, q.col }))
      end
    end
    return table.concat(out, '\n')
  end,
  ['@marks'] = function(c)
    local out = {}
    for _, mark in ipairs(vim.fn.getmarklist()) do
      if mark.mark:match("^'[A-Z]$") then table.insert(out, c:location(mark.pos[1], { mark.pos[2], mark.pos[3] })) end
    end
    return table.concat(out, '\n')
  end,
}

function M.builders()
  return vim.tbl_extend('force', M.builtins, require('opvi.config').opts.contexts)
end

function M:render(text)
  local builders = M.builders()
  return (text:gsub('@[%w_]+', function(key)
    if not builders[key] then return key end
    local value = builders[key](self)
    return value and value ~= '' and value or key
  end))
end

return M
