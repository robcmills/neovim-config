-- Save and restore the set of open buffers, including live cc.nvim sessions.
--
-- :SaveSession writes ~/.config/nvim/sessions/<name>.lua, a script that calls
-- M.restore() with the listed file buffers and the id/provider of every
-- cc.nvim session. :LoadSession sources one of those files. Older mksession
-- .vim files in the same directory are still listed and sourced as-is.
--
-- mksession is not used because cc.nvim output buffers are nofile scratch
-- buffers; a session file restores them as empty regular buffers with no
-- subprocess behind them.

local M = {}

local SESSIONS_DIR = vim.fn.stdpath('config') .. '/sessions/'

-- Collect listed buffers in buffer-number order: real files by path, cc.nvim
-- sessions by id. Terminals and cc instances without a session id yet are
-- skipped.
local function snapshot()
  local files, cc_sessions, skipped = {}, {}, 0
  local has_cc, cc = pcall(require, 'cc')
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if vim.bo[bufnr].filetype == 'cc-output' then
        local inst = has_cc and cc.find_instance(bufnr) or nil
        if inst and inst.last_session_id and inst.provider and inst.provider.name then
          table.insert(cc_sessions, { provider = inst.provider.name, id = inst.last_session_id })
        else
          skipped = skipped + 1
        end
      elseif vim.bo[bufnr].buftype == '' and vim.fn.filereadable(name) == 1 then
        table.insert(files, vim.fn.fnamemodify(name, ':p'))
      end
    end
  end
  return { cwd = vim.fn.getcwd(), files = files, cc = cc_sessions }, skipped
end

local function render(snap)
  local lines = {
    '-- Saved by :SaveSession ' .. os.date('%Y-%m-%d %H:%M'),
    "require('sessions').restore({",
    string.format('  cwd = %q,', snap.cwd),
    '  files = {',
  }
  for _, path in ipairs(snap.files) do
    table.insert(lines, string.format('    %q,', path))
  end
  table.insert(lines, '  },')
  table.insert(lines, '  cc = {')
  for _, s in ipairs(snap.cc) do
    table.insert(lines, string.format('    { provider = %q, id = %q },', s.provider, s.id))
  end
  table.insert(lines, '  },')
  table.insert(lines, '})')
  return lines
end

function M.save(name)
  local snap, skipped = snapshot()
  vim.fn.mkdir(SESSIONS_DIR, 'p')
  local path = SESSIONS_DIR .. name .. '.lua'
  vim.fn.writefile(render(snap), path)
  local msg = string.format('Session saved: %s (%d files, %d cc sessions)', name, #snap.files, #snap.cc)
  if skipped > 0 then
    msg = msg .. string.format(', skipped %d cc buffers with no session id', skipped)
  end
  vim.notify(msg)
end

-- Resume one cc.nvim session without disturbing the current layout. cc.resume
-- splits the current window into output + prompt, so run it in a throwaway
-- tab and close the tab afterwards. The buffers are bufhidden=hide and the
-- subprocess keeps running; selecting the output buffer later recreates the
-- prompt window. cc.close() is not usable here because it kills the process.
local function resume_hidden(cc, entry)
  vim.cmd('tabnew')
  vim.bo.bufhidden = 'wipe'
  local tab = vim.api.nvim_get_current_tabpage()
  local ok, err = pcall(cc.resume, entry.id, entry.provider)
  if not ok then
    vim.notify('sessions: failed to resume ' .. entry.id .. ': ' .. tostring(err), vim.log.levels.WARN)
  end
  if vim.api.nvim_tabpage_is_valid(tab) then
    vim.api.nvim_set_current_tabpage(tab)
    vim.cmd('tabclose')
  end
  return ok
end

function M.restore(snap)
  if snap.cwd and vim.fn.isdirectory(snap.cwd) == 1 then
    vim.cmd.cd(vim.fn.fnameescape(snap.cwd))
  end

  local first
  local files = 0
  for _, path in ipairs(snap.files or {}) do
    if vim.fn.filereadable(path) == 1 then
      vim.cmd.badd(vim.fn.fnameescape(path))
      first = first or path
      files = files + 1
    else
      vim.notify('sessions: missing file ' .. path, vim.log.levels.WARN)
    end
  end

  local resumed = 0
  if #(snap.cc or {}) > 0 then
    local has_cc, cc = pcall(require, 'cc')
    if has_cc then
      for _, entry in ipairs(snap.cc) do
        if resume_hidden(cc, entry) then resumed = resumed + 1 end
      end
      vim.cmd('stopinsert')
    else
      vim.notify('sessions: cc.nvim not loaded, skipping cc sessions', vim.log.levels.WARN)
    end
  end

  -- Show the first file only if the current window holds a listed buffer,
  -- so we never load a file into the buffers sidebar or a floating window.
  if first and vim.bo.buflisted then
    vim.cmd.edit(vim.fn.fnameescape(first))
  end
  if vim.fn.exists(':BuffersShow') == 2 then
    vim.cmd('BuffersShow')
    vim.cmd('wincmd p')
  end

  vim.notify(string.format('Session restored: %d files, %d cc sessions', files, resumed))
end

-- Newest first by file creation time (birthtime on macOS), falling back to
-- mtime where the filesystem does not report one.
local function created_at(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then return 0 end
  local t = stat.birthtime and stat.birthtime.sec or 0
  return t > 0 and t or stat.mtime.sec
end

local function list_sessions()
  local entries = {}
  for _, path in ipairs(vim.fn.glob(SESSIONS_DIR .. '*.lua', false, true)) do
    table.insert(entries, { name = vim.fn.fnamemodify(path, ':t:r'), label = vim.fn.fnamemodify(path, ':t:r'), path = path })
  end
  for _, path in ipairs(vim.fn.glob(SESSIONS_DIR .. '*.vim', false, true)) do
    table.insert(entries, { name = vim.fn.fnamemodify(path, ':t:r'), label = vim.fn.fnamemodify(path, ':t:r') .. ' (mksession)', path = path })
  end
  for _, e in ipairs(entries) do e.created_at = created_at(e.path) end
  table.sort(entries, function(a, b) return a.created_at > b.created_at end)
  return entries
end

local function complete_sessions(arg_lead)
  local names = {}
  for _, e in ipairs(list_sessions()) do
    if vim.startswith(e.name, arg_lead) then table.insert(names, e.name) end
  end
  return names
end

local function load(entry)
  vim.cmd.source(vim.fn.fnameescape(entry.path))
end

function M.setup()
  -- :SaveSession [name] saves under name, or prompts for one.
  vim.api.nvim_create_user_command('SaveSession', function(opts)
    if opts.args ~= '' then return M.save(opts.args) end
    vim.ui.input({ prompt = 'Session name: ' }, function(input)
      if input and input ~= '' then M.save(input) end
    end)
  end, { nargs = '?', complete = complete_sessions })

  -- :LoadSession [name] loads that session, or picks one (newest first).
  vim.api.nvim_create_user_command('LoadSession', function(opts)
    local entries = list_sessions()
    if #entries == 0 then
      vim.notify('No sessions found')
      return
    end
    if opts.args ~= '' then
      for _, e in ipairs(entries) do
        if e.name == opts.args then return load(e) end
      end
      vim.notify('No session named ' .. opts.args, vim.log.levels.WARN)
      return
    end
    vim.ui.select(entries, {
      prompt = 'Select session: ',
      format_item = function(e) return e.label end,
    }, function(choice)
      if choice then load(choice) end
    end)
  end, { nargs = '?', complete = complete_sessions })

  -- :SaveSessionNow saves a session named by the current date and time.
  vim.api.nvim_create_user_command('SaveSessionNow', function()
    vim.cmd.SaveSession(os.date('%Y-%m-%d_%H-%M-%S'))
  end, {})

  -- :LoadSessionLatest loads the most recently created session.
  vim.api.nvim_create_user_command('LoadSessionLatest', function()
    local latest = list_sessions()[1]
    if not latest then
      vim.notify('No sessions found')
      return
    end
    vim.cmd.LoadSession(latest.name)
  end, {})
end

return M
