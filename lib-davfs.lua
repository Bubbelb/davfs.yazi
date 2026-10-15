-- lib-davfs.lua

local DAVFS = {}

--- Build a filesystem-safe alias from a WebDAV URL.
---@param url string
---@return string
local function url_to_alias(url)
  local rest = url:gsub("^https?://", "")
  return rest:gsub("[^%w%.%-]", "-"):gsub("%-+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
end

--- Assemble mount.davfs -o options from config.
---@param config table
---@return string[]
local function davfs_options(config)
  local opts = {}
  if config.davfs_options then
    for _, o in ipairs(config.davfs_options) do
      opts[#opts + 1] = o
    end
  end
  return opts
end

--- Try a non-interactive mount (succeeds when secrets/cookies are cached).
---@param url string
---@param mount_point string
---@param config table
---@return string|nil err, Output|nil output
local function try_mount(url, mount_point, config)
  local opts = davfs_options(config)
  local args = { url, mount_point }
  if #opts > 0 then
    args[#args + 1] = "-o"
    args[#args + 1] = table.concat(opts, ",")
  end

  local child, spawn_err = Command("mount.davfs"):arg(args):stdout(Command.PIPED):stderr(Command.PIPED):spawn()
  if not child then return tostring(spawn_err), nil end
  local output, out_err = child:wait_with_output()
  if not output then return tostring(out_err), nil end
  if output.status and output.status.success then return nil, output end
  return output.stderr ~= "" and output.stderr or "mount.davfs failed", output
end

--- Try an interactive mount so the user can enter credentials.
---@param url string
---@param mount_point string
---@param config table
---@return boolean
local function try_interactive_mount(url, mount_point, config)
  local opts = davfs_options(config)
  local args = { url, mount_point }
  if #opts > 0 then
    args[#args + 1] = "-o"
    args[#args + 1] = table.concat(opts, ",")
  end

  local permit = ui.hide()

  local status, err = Command("mount.davfs")
    :arg(args)
    :stdin(Command.INHERIT)
    :stdout(Command.INHERIT)
    :stderr(Command.INHERIT)
    :status()

  permit:drop()

  if err then
    Notify.error("Interactive mount failed: %s", tostring(err))
    return false
  end

  return status.success
end

--- Check whether a URL already has an active mount under mount_dir.
---@param url string
---@param mount_dir string
---@return string|nil mount_path
local function find_existing_mount(url, mount_dir)
  local Mount = require(".lib-mount")
  local alias = url_to_alias(url)
  for _, m in ipairs(Mount.list(mount_dir)) do
    if m.alias == alias then return m.path end
  end
  return nil
end

--- Append a suffix path to a base URL without double slashes.
---@param base string
---@param path string|nil
---@return string
local function normalize_appended_path(base, path)
  if not path or path:match("^%s*$") then return base end
  path = path:match("^%s*(.-)%s*$")
  if path:sub(1, 1) ~= "/" then path = "/" .. path end
  if base:sub(-1) == "/" then
    return base .. path:sub(2)
  else
    return base .. path
  end
end

--- Called after a successful mount. Notifies the user and optionally jumps.
---@param entry string display name
---@param mount_point string
---@param config table
---@param jump_override boolean|nil
local function finalize(entry, mount_point, config, jump_override)
  local Notify = require(".lib-notify")
  Notify.info("Mounted %s", entry)
  local do_jump = jump_override ~= nil and jump_override
    or (config.on_mount == nil or config.on_mount.auto_jump ~= false)
  if do_jump then ya.emit("cd", { mount_point, raw = true }) end
end

--- Mount a WebDAV host entry.
---@param entry string host entry, optionally with a path suffix
---@param opts? { jump: boolean|nil }
function DAVFS.mount(entry, opts)
  local Notify = require(".lib-notify")
  local Fs = require(".lib-fileservice")
  local Hosts = require(".lib-hosts")
  local State = require(".lib-state")
  opts = opts or {}
  local config = State.get(State.KEY.CONFIG)
  local mount_dir = config.mount_dir
  Fs.ensure_dir(Url(mount_dir))

  local url, remote_path = Hosts.parse_entry(entry)
  Notify.debug("Mounting: url=%s remote_path=%s", url, remote_path or "nil")

  local existing = find_existing_mount(url, mount_dir)
  if existing then
    Notify.warn("Host already mounted at %s — unmount it first", existing)
    return
  end

  -- Resolve optional sub-path selection
  local target_url = url
  if not remote_path then
    local CUSTOM = "Custom path…"
    local options = { "~ (base URL)", CUSTOM }

    if config.host_paths and config.host_paths[url] then
      local hp = config.host_paths[url]
      if type(hp) == "string" then
        options[#options + 1] = hp
      else
        for _, p in ipairs(hp) do
          options[#options + 1] = p
        end
      end
    end

    if config.global_paths then
      for _, p in ipairs(config.global_paths) do
        options[#options + 1] = p
      end
    end

    local picker = require(".ui-picker")
    local chosen = picker.choose("Mount where?", options, config)
    if not chosen then return end

    if chosen == CUSTOM then
      local typed = require(".ui-prompt").input("URL suffix:")
      if not typed then return end
      target_url = normalize_appended_path(url, typed)
    elseif chosen ~= "~ (base URL)" then
      target_url = normalize_appended_path(url, chosen)
    end
  else
    target_url = normalize_appended_path(url, remote_path)
  end

  local alias = url_to_alias(target_url)
  local mount_point = mount_dir .. "/" .. alias
  local mount_url = Url(mount_point)
  Fs.ensure_dir(mount_url)

  local Mount = require(".lib-mount")
  if Mount.is_active(mount_point, mount_url, mount_dir) then
    Notify.info("Already mounted at %s", mount_point)
    return finalize(entry, mount_point, config, opts.jump)
  end

  local key_err, _ = try_mount(target_url, mount_point, config)
  if not key_err then
    local Lockfile = require(".lib-lockfile")
    Lockfile.acquire(alias)
    return finalize(entry, mount_point, config, opts.jump)
  end

  -- Interactive fallback for authentication
  if try_interactive_mount(target_url, mount_point, config) then
    local Lockfile = require(".lib-lockfile")
    Lockfile.acquire(alias)
    return finalize(entry, mount_point, config, opts.jump)
  end

  Notify.error("Mount failed: %s", key_err)
  fs.remove("dir_clean", mount_url)
end

return DAVFS

