local M = {}

local function trim(value)
  value = tostring(value or "")
  value = string.gsub(value, "^%s+", "")
  value = string.gsub(value, "%s+$", "")
  return value
end

local function parsePart(raw)
  local n = tonumber(raw)
  if not n then
    return nil
  end
  return math.max(0, math.floor(n))
end

function M.parse(version)
  local normalized = trim(version)
  if normalized == "" then
    return nil, "empty version"
  end

  local cleaned = normalized
  local dash = string.find(cleaned, "-", 1, true)
  if dash then
    cleaned = string.sub(cleaned, 1, dash - 1)
  end

  local parts = {}
  for token in string.gmatch(cleaned, "[^%.]+") do
    parts[#parts + 1] = token
  end

  if #parts == 0 then
    return nil, "invalid version format"
  end

  local major = parsePart(parts[1])
  local minor = parsePart(parts[2] or "0")
  local patch = parsePart(parts[3] or "0")

  if major == nil or minor == nil or patch == nil then
    return nil, "invalid numeric version parts"
  end

  return {
    raw = normalized,
    major = major,
    minor = minor,
    patch = patch,
  }
end

function M.compare(a, b)
  local pa, errA = M.parse(a)
  if not pa then
    return nil, "invalid local version: " .. tostring(errA)
  end

  local pb, errB = M.parse(b)
  if not pb then
    return nil, "invalid remote version: " .. tostring(errB)
  end

  if pa.major ~= pb.major then
    return pa.major < pb.major and -1 or 1
  end
  if pa.minor ~= pb.minor then
    return pa.minor < pb.minor and -1 or 1
  end
  if pa.patch ~= pb.patch then
    return pa.patch < pb.patch and -1 or 1
  end

  return 0
end

function M.isRemoteNewer(localVersion, remoteVersion)
  local cmp, err = M.compare(localVersion, remoteVersion)
  if cmp == nil then
    return nil, err
  end
  return cmp < 0
end

function M.readLocalVersion(path)
  path = path or "fusion.version"
  if not fs.exists(path) then
    return nil, "missing version file: " .. tostring(path)
  end

  local fh = fs.open(path, "r")
  if not fh then
    return nil, "cannot open version file: " .. tostring(path)
  end

  local raw = fh.readAll() or ""
  fh.close()

  local version = trim(raw)
  if version == "" then
    return nil, "version file is empty"
  end

  return version
end

return M
