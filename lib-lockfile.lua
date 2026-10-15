-- lib-lockfile.lua

local LOCKFILE = {}

local USER_ID = ya.uid()
local XDG_RUNTIME_DIR = os.getenv("XDG_RUNTIME_DIR") or ("/run/user/" .. USER_ID)
local LOCK_DIR = XDG_RUNTIME_DIR .. "/davfs"

local function lock_path(mount_name)
  return LOCK_DIR .. "/" .. mount_name:gsub("[^%w._%-]", "_") .. ".lock"
end

function LOCKFILE.acquire(mount_name)
  fs.create("dir_all", Url(LOCK_DIR))
  local path = lock_path(mount_name)
  local f = io.open(path, "w")
  if not f then
    local Notify = require(".lib-notify")
    Notify.debug("Failed to acquire lockfile for %s", mount_name)
    return false
  end
  f:write(tostring(USER_ID) .. "\n")
  f:close()
  return true
end

function LOCKFILE.release(mount_name)
  fs.remove("file", Url(lock_path(mount_name)))
end

function LOCKFILE.is_locked(mount_name)
  local f = io.open(lock_path(mount_name))
  if not f then return false end
  f:close()
  return true
end

return LOCKFILE
