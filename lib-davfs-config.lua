-- lib-davfs-config.lua

local DAVCONFIG = {}

--- davfs2 has no native host registry; custom_hosts_file is the source of truth.
---@return string[]
function DAVCONFIG.list_hosts()
  return {}
end

return DAVCONFIG
