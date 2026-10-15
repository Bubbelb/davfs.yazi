-- lib-hosts.lua

local HOSTS = {}

local CACHE = {
  hosts = nil,
  save_file_mtime = 0,
}

local function unique(list)
  local seen, out = {}, {}
  for _, v in ipairs(list) do
    if not seen[v] then
      seen[v] = true
      out[#out + 1] = v
    end
  end
  return out
end

local function is_cache_valid(hosts_file)
  local Fs = require(".lib-fileservice")
  return CACHE.hosts ~= nil
    and CACHE.save_file_mtime == Fs.get_mtime(hosts_file)
end

local function update_cache(hosts, hosts_file)
  local Fs = require(".lib-fileservice")
  CACHE.hosts = hosts
  CACHE.save_file_mtime = Fs.get_mtime(hosts_file)
end

--- Force the host list to be re-read on the next call to get_all().
function HOSTS.invalidate()
  CACHE.hosts = nil
end

--- Return all available hosts from the custom saved URL list.
---@param hosts_file string
---@return string[]
function HOSTS.get_all(hosts_file)
  if is_cache_valid(hosts_file) then return CACHE.hosts end

  local cha, _ = fs.cha(Url(hosts_file))
  local hosts
  if cha then
    local State = require(".lib-state")
    local saved = State.read_lines(hosts_file)
    hosts = unique(saved)
  else
    hosts = {}
  end

  update_cache(hosts, hosts_file)
  return hosts
end

--- Parse an entry of the form "url" or "url /path".
--- Returns the base URL and an optional appended path.
---@param entry string
---@return string url, string|nil remote_path
function HOSTS.parse_entry(entry)
  local url, path = entry:match("^(%S+)%s+(/.*)$")
  if url and path then return url, path end
  return entry, nil
end

--- Generate a short mount-point suffix from a remote path.
---@param remote_path string
---@return string
function HOSTS.mount_suffix(remote_path)
  if not remote_path or remote_path == "" then return "" end
  remote_path = remote_path:gsub("/+$", "")
  if remote_path == "/" or remote_path == "" then return "root" end

  local components = {}
  for c in remote_path:gmatch("[^/]+") do
    components[#components + 1] = c
  end

  local count = math.min(2, #components)
  local parts = {}
  for i = #components - count + 1, #components do
    parts[#parts + 1] = components[i]
  end

  local suffix = table.concat(parts, "-"):gsub("[^%w%-_]", "-"):gsub("%-+", "-")
  return suffix
end

return HOSTS
