-- Fixture for buffers.lua's priority rows and :FocusNext: fake cc.nvim
-- instances in every state and bucket, plus file buffers. Stubs
-- package.loaded.cc; set the priorities command before calling `load`.
--   require('fixtures.focus_next').load({ cmd = {...} })

local M = {}

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h')
M.json = root .. '/priorities.json'

-- name, state, cwd, sessionId, lastModifiedAt
M.agents = {
  { '2026-10-15T09:01:00-estimation-publish', 'working', '/tmp/fn/delivery/web', 'a1', 100 },
  { '2026-10-15T09:02:00-wake-model', 'unread', '/tmp/fn/voice', 'a2', 300 },
  { '2026-10-15T09:03:00-standup-for-delivery', 'unread', '/Users/robcmills/jarvis', 's-tagged', 400 },
  { '2026-10-15T09:04:00-sidebar-worker', 'monitoring', '/tmp/fn/nvim/lua/cc', 'a4', 100 },
  { '2026-10-15T09:05:00-colemak-visual-mode', 'waiting', '/tmp/fn/nvim', 'a5', 50 },
  { '2026-10-15T09:06:00-side-project', 'unread', '/tmp/fn/side', 'a6', 200 },
  { '2026-10-15T09:07:00-misc-question', 'ready', '/tmp/elsewhere', 'a7', 100 },
  { '2026-10-15T09:08:00-store-cleanup', 'exited', '/Users/robcmills/jarvis/projects', 's-untagged', 100 },
  { '2026-10-15T09:09:00-a-very-long-session-name-that-wraps-in-the-sidebar', 'delegating', '/tmp/fn/delivery', 'a9', 100 },
  { '2026-10-15T09:10:00-stopping', 'interrupting', '/tmp/fn/voice/src', 'a10', 100 },
  { '2026-10-15T09:11:00-new-chat', 'starting', '/tmp/fn/nvim', 'a11', 100 },
}

M.files = { 'init.lua', 'lua/buffers.lua', 'lua/agent_priority.lua', 'README.md' }

local function scratch(name, listed)
  local bufnr = vim.api.nvim_create_buf(listed, true)
  vim.api.nvim_buf_set_name(bufnr, name)
  return bufnr
end

---@param opts { cmd?: string[], files_dir?: string }|nil
function M.load(opts)
  opts = opts or {}
  require('agent_priority').setup({ cmd = opts.cmd or { 'cat', M.json } })
  M.instances = {}
  local dir = opts.files_dir or vim.fn.expand('~/.config/nvim')
  for _, f in ipairs(M.files) do
    vim.cmd('badd ' .. vim.fn.fnameescape(dir .. '/' .. f))
  end
  for _, a in ipairs(M.agents) do
    local out = scratch('cc-' .. a[1], true)
    vim.bo[out].buftype = 'nofile'
    local prompt = scratch('cc-prompt-' .. a[1], false)
    table.insert(M.instances, {
      outputBufnr = out, promptBufnr = prompt, name = a[1], state = a[2], cwd = a[3],
      sessionId = a[4], lastModifiedAt = a[5], provider = 'claude',
    })
  end
  package.loaded.cc = {
    list_instances = function() return vim.deepcopy(M.instances) end,
    mark_unread = function() return true end,
  }
  -- Viewing an unread agent marks it seen, as cc.nvim does
  vim.api.nvim_create_autocmd('BufEnter', {
    callback = function(ev)
      for _, inst in ipairs(M.instances) do
        if inst.outputBufnr == ev.buf and inst.state == 'unread' then
          inst.state = 'ready'
          vim.schedule(function()
            vim.api.nvim_exec_autocmds('User', {
              pattern = 'CcStateChanged',
              data = { bufnr = inst.outputBufnr, prompt_bufnr = inst.promptBufnr, state = 'ready', previous = 'unread' },
            })
          end)
        end
      end
    end,
  })
  return M.instances
end

function M.by_name(fragment)
  for _, inst in ipairs(M.instances) do
    if inst.name:find(fragment, 1, true) then
      return inst
    end
  end
end

return M
