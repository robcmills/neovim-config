-- vim.system throws ENOENT when cwd is gone, e.g. a buffer still attached to a
-- removed git worktree. Fail the git call softly instead. Must run before
-- gitsigns.git.cmd captures system().
local gs_system = require 'gitsigns.system'
local orig_system = gs_system.system
gs_system.system = function(cmd, opts, on_exit)
  if opts and opts.cwd and not vim.uv.fs_stat(opts.cwd) then
    vim.schedule(function()
      on_exit({ code = 128, signal = 0, stdout = '', stderr = 'cwd does not exist: ' .. opts.cwd })
    end)
    return
  end
  return orig_system(cmd, opts, on_exit)
end

-- When a watched repo disappears (e.g. `wt rm`), its gitdir watcher still fires
-- and the handlers crash reading HEAD or running git there. Detach the
-- affected buffers instead.
local Watcher = require 'gitsigns.git.repo.watcher'
local orig_watcher_new = Watcher.new
Watcher.new = function(gitdir)
  local w = orig_watcher_new(gitdir)
  w._gitdir = gitdir
  return w
end
local orig_handler2 = Watcher.handler2
Watcher.handler2 = function(weak_self)
  local w = weak_self.ref
  if w and w._gitdir then
    local gone = not vim.uv.fs_stat(w._gitdir .. '/HEAD')
    for bufnr, bcache in pairs(require('gitsigns.cache').cache) do
      local repo = bcache.git_obj.repo
      if repo.gitdir == w._gitdir and (gone or not vim.uv.fs_stat(repo.toplevel)) then
        require('gitsigns.attach').detach(bufnr)
      end
    end
    if gone then
      w.changed_files = {}
      return
    end
  end
  return orig_handler2(weak_self)
end

require 'gitsigns'.setup {
  on_attach = function(bufnr)
    local gs = package.loaded.gitsigns

    local function map(mode, l, r, opts)
      opts = opts or {}
      opts.buffer = bufnr
      vim.keymap.set(mode, l, r, opts)
    end

    map('n', '<leader>gb', gs.toggle_current_line_blame)
    -- map('n', '<leader>gb', function() gs.blame_line{full=true} end)
    map('n', '<leader>gp', gs.preview_hunk)
    map('n', '<leader>gd', gs.diffthis)
    map('n', '<leader>gD', function() gs.diffthis('~') end)

    -- Navigation
    map('n', '<leader>gn', function()
      if vim.wo.diff then return ']c' end
      vim.schedule(function() gs.next_hunk() end)
      return '<Ignore>'
    end, {expr=true})

    map('n', '<leader>gv', function()
      if vim.wo.diff then return '[c' end
      vim.schedule(function() gs.prev_hunk() end)
      return '<Ignore>'
    end, {expr=true})
  end
}
