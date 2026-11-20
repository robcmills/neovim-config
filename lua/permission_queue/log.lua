-- One JSON line per resolved cc.nvim permission prompt, in
-- ~/.claude/permission-resolved.jsonl, next to the `prompted` rows
-- log-permissions.sh writes to permission-prompts.jsonl. `source` and
-- `variant` say who answered and how (local key, api, remote, defer,
-- closed); `elapsed` is seconds the prompt was open. A sub-second local deny
-- is the signature of a prompt answered by accident.
local M = {}

local PATH = vim.fn.expand('~/.claude/permission-resolved.jsonl')

local function compact_input(tool_name, input)
  if type(input) ~= 'table' then return vim.NIL end
  if tool_name == 'Bash' then return { command = input.command } end
  return input
end

function M.resolved(event)
  local row = {
    timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    kind = event.kind, provider = event.provider,
    session_id = event.session_id, session_name = event.session_name,
    cwd = vim.fn.getcwd(), tool = event.tool_name,
    input = compact_input(event.tool_name, event.input),
    behavior = event.behavior, variant = event.variant, source = event.source,
    elapsed = event.elapsed and math.floor(event.elapsed * 1000 + 0.5) / 1000 or vim.NIL,
    deferred = event.deferred == true, timed_out = event.timed_out == true,
    nvim_pid = vim.fn.getpid(),
  }
  local ok, line = pcall(vim.json.encode, row)
  local f = ok and io.open(PATH, 'a')
  if f then f:write(line, '\n'); f:close() end
end

return M
