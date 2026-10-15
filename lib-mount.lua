-- lib-mount.lua

local MOUNT = {}

--- Parse `mount` output for davfs entries under a given root directory.
---@param mount_output string
---@param root string
---@return { path: string, remote: string }[]
local function parse_mount_output(mount_output, root)
  local mounts = {}
  local root_esc = root:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  local pattern = ("^(.+)%son%s(" .. root_esc .. "/[^%s]+)%s+type%s+davfs")

  for line in mount_output:gmatch("[^\r\n]+") do
    local remote, path = line:match(pattern)
    if path and remote then mounts[#mounts + 1] = { path = path, remote = remote } end
  end
  return mounts
end

--- Try findmnt first, fall back to parsing `mount` output.
---@param mount_dir string
---@return { path: string, remote: string }[]
local function get_davfs_mounts(mount_dir)
  local root_pat = "^" .. mount_dir:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "/"

  local child, _ = Command("findmnt")
    :arg({ "-t", "davfs", "-o", "SOURCE,TARGET", "--noheadings", "-l" })
    :stdout(Command.PIPED)
    :stderr(Command.PIPED)
    :spawn()
  if child then
    local output = child:wait_with_output()
    if output and output.status.success then
      local mounts = {}
      for line in output.stdout:gmatch("[^\r\n]+") do
        local remote, path = line:match("^(%S+)%s+(%S+)$")
        if path and remote and path:match(root_pat) then mounts[#mounts + 1] = { path = path, remote = remote } end
      end
      return mounts
    end
  end

  local mount_child, _ = Command("mount"):stdout(Command.PIPED):stderr(Command.PIPED):spawn()
  if mount_child then
    local mout = mount_child:wait_with_output()
    if mout then return parse_mount_output(mout.stdout, mount_dir) end
  end

  return {}
end

--- Return true if `path` is an active davfs mount point.
---@param path string
---@param url Url
---@param mount_dir string
---@return boolean
function MOUNT.is_active(path, url, mount_dir)
  local Fs = require(".lib-fileservice")
  if not Fs.is_dir(url) then return false end
  local mounts = get_davfs_mounts(mount_dir)
  if #mounts > 0 then
    for _, m in ipairs(mounts) do
      if m.path == path then return true end
    end
    return false
  end
  return not Fs.is_dir_empty(url)
end

--- List all active davfs mounts under mount_dir.
---@param mount_dir string
---@return { alias: string, path: string, remote: string|nil }[]
function MOUNT.list(mount_dir)
  local Notify = require(".lib-notify")
  local mounts = {}
  local parsed = get_davfs_mounts(mount_dir)

  if #parsed > 0 then
    for _, m in ipairs(parsed) do
      local alias = m.path:match("([^/]+)$")
      if alias then
        Notify.debug("Active mount: %s → %s", m.remote, m.path)
        mounts[#mounts + 1] = { alias = alias, path = m.path, remote = m.remote }
      end
    end
  else
    local files, err = fs.read_dir(Url(mount_dir), { resolve = false })
    if not files then
      Notify.debug("Could not read mount_dir: %s", tostring(err))
      return mounts
    end
    for _, file in ipairs(files) do
      local url = file.url
      local path = tostring(url)
      local Fs = require(".lib-fileservice")
      if Fs.is_dir(url) and MOUNT.is_active(path, url, mount_dir) then
        mounts[#mounts + 1] = { alias = file.name, path = path, remote = nil }
      end
    end
  end

  Notify.debug("Found %d active mount(s)", #mounts)
  return mounts
end

--- Unmount a mount point, trying several unmount commands in order.
---@param path string
---@param clean_dir? boolean
---@return boolean
function MOUNT.remove(path, clean_dir)
  local attempts = {
    { "fusermount", { "-u", path } },
    { "fusermount3", { "-u", path } },
    { "umount", { path } },
    { "diskutil", { "unmount", path } },

    { "fusermount", { "-uz", path } },
    { "fusermount3", { "-uz", path } },
    { "umount", { "-l", path } },

    { "diskutil", { "unmount", "force", path } },
    { "umount", { "-f", path } },
  }
  for _, cmd in ipairs(attempts) do
    local status, err = Command(cmd[1]):arg(cmd[2]):status()
    if err == nil and status and status.success then
      if clean_dir then fs.remove("dir_clean", Url(path)) end
      return true
    end
  end
  return false
end

return MOUNT
