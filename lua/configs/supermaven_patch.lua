local M = {}

local PATH = vim.fn.stdpath('data')
  .. '/site/pack/packer/start/supermaven-nvim/lua/supermaven-nvim/logger.lua'

local OLD = [[  if conf.log_level == "off" or level_values[conf.log_level] == nil then
    return
  end

  if self.__log_file == nil then
    self.__log_file = create_log_file()
  end

  self:write_log_file(level, msg)
  if level_values[level] >= level_values[conf.log_level] then
    print(self.__notify_fmt(msg))
  end
end]]

local NEW = [[  if conf.log_level == "off" or level_values[conf.log_level] == nil then
    return
  end

  if level_values[level] < level_values[conf.log_level] then
    return
  end

  if self.__log_file == nil then
    self.__log_file = create_log_file()
  end

  self:write_log_file(level, msg)
  print(self.__notify_fmt(msg))
end]]

function M.apply()
  local f = io.open(PATH, 'r')
  if not f then
    vim.notify('supermaven_patch: logger.lua not found at ' .. PATH, vim.log.levels.WARN)
    return
  end
  local src = f:read('*a')
  f:close()

  if src:find(NEW, 1, true) then
    return
  end

  local start_idx, end_idx = src:find(OLD, 1, true)
  if not start_idx then
    vim.notify(
      'supermaven_patch: target block not found; upstream may have changed',
      vim.log.levels.WARN
    )
    return
  end

  src = src:sub(1, start_idx - 1) .. NEW .. src:sub(end_idx + 1)

  local out = io.open(PATH, 'w')
  if not out then
    vim.notify('supermaven_patch: failed to write logger.lua', vim.log.levels.ERROR)
    return
  end
  out:write(src)
  out:close()
  vim.notify('supermaven_patch: applied logger.lua patch')
end

return M
