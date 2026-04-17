local M = {}

local function ancestors(pid)
  local set = {}
  local p = pid
  while p and p > 1 do
    set[p] = true
    local f = io.popen('ps -o ppid= -p ' .. p)
    if not f then break end
    local line = f:read('*l')
    f:close()
    p = tonumber((line or ''):match('%d+'))
  end
  return set
end

function M.focus(cc_pid)
  local anc = ancestors(cc_pid)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == 'terminal' then
      local ok, job_pid = pcall(function() return vim.b[buf].terminal_job_pid end)
      if ok and job_pid and anc[job_pid] then
        vim.api.nvim_set_current_buf(buf)
        return true
      end
    end
  end
  return false
end

return M
