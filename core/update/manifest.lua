local M = {}

local function normalizePath(path)
  path = tostring(path or "")
  path = string.gsub(path, "\\", "/")
  path = string.gsub(path, "^%./", "")
  path = string.gsub(path, "^/", "")
  return path
end

local function trim(value)
  value = tostring(value or "")
  value = string.gsub(value, "^%s+", "")
  value = string.gsub(value, "%s+$", "")
  return value
end

local function hasValue(s)
  return type(s) == "string" and string.find(s, "%S") ~= nil
end

local function normalizeHash(value)
  if not hasValue(value) then
    return nil
  end
  local hash = string.lower(trim(value))
  if hash == "" then
    return nil
  end
  return hash
end

local function normalizeHashAlgo(value)
  if not hasValue(value) then
    return nil
  end
  return string.lower(trim(value))
end

local function isSupportedHashAlgo(algo)
  return normalizeHashAlgo(algo) == "sha256"
end

local function isValidHash(hash, algo)
  if type(hash) ~= "string" then
    return false
  end

  local normalizedAlgo = normalizeHashAlgo(algo) or "sha256"
  if normalizedAlgo == "sha256" then
    return #hash == 64 and string.match(hash, "^[0-9a-f]+$") ~= nil
  end

  return false
end

local function normalizeCommit(value)
  if type(value) ~= "string" then
    return nil
  end
  local commit = trim(value)
  if commit == "" then
    return nil
  end
  return string.lower(commit)
end

local function decodeJson(text)
  local ok, data = pcall(textutils.unserializeJSON, text)
  if not ok then
    return nil, data
  end
  if type(data) ~= "table" then
    return nil, "json root is not an object"
  end
  return data
end

local function normalizeFiles(list)
  if type(list) ~= "table" then
    return nil, "manifest.files must be an array"
  end

  local out = {}
  local seen = {}

  for i, entry in ipairs(list) do
    local item
    if type(entry) == "string" then
      item = {
        path = normalizePath(entry),
      }
    elseif type(entry) == "table" then
      local hash = normalizeHash(entry.hash or entry.sha256)
      local hashAlgo = hash and (normalizeHashAlgo(entry.hashAlgo) or "sha256") or nil
      if hash and not isSupportedHashAlgo(hashAlgo) then
        return nil, "unsupported hash algorithm at index " .. tostring(i) .. ": " .. tostring(hashAlgo)
      end
      if hash and not isValidHash(hash, hashAlgo) then
        return nil, "invalid hash format at index " .. tostring(i) .. ": " .. tostring(hash)
      end
      item = {
        path = normalizePath(entry.path),
        size = tonumber(entry.size) and math.max(0, math.floor(tonumber(entry.size))) or nil,
        hash = hash,
        hashAlgo = hashAlgo,
      }
    else
      return nil, "invalid file entry at index " .. tostring(i)
    end

    if not hasValue(item.path) then
      return nil, "empty file path at index " .. tostring(i)
    end
    if seen[item.path] then
      return nil, "duplicate file path in manifest: " .. tostring(item.path)
    end

    seen[item.path] = true
    out[#out + 1] = item
  end

  return out
end

function M.isValidCommit(commit)
  local normalized = normalizeCommit(commit)
  if not normalized then
    return false
  end
  return string.match(normalized, "^[0-9a-f]+$") ~= nil and #normalized == 40
end

function M.resolveCommit(manifest)
  if type(manifest) ~= "table" then
    return nil
  end

  local commit = normalizeCommit(manifest.commit)
  if commit then
    return commit
  end

  if type(manifest.source) == "table" then
    return normalizeCommit(manifest.source.commit)
  end

  return nil
end

function M.validate(raw)
  if type(raw) ~= "table" then
    return nil, "manifest is not a table"
  end

  local files, filesErr = normalizeFiles(raw.files)
  if not files then
    return nil, filesErr
  end

  if not hasValue(raw.name) then
    return nil, "manifest.name missing"
  end
  if not hasValue(raw.version) then
    return nil, "manifest.version missing"
  end
  if not hasValue(raw.entrypoint) then
    return nil, "manifest.entrypoint missing"
  end

  local commit = normalizeCommit(raw.commit)
  if not commit and type(raw.source) == "table" then
    commit = normalizeCommit(raw.source.commit)
  end

  local source = {}
  if type(raw.source) == "table" then
    source.owner = hasValue(raw.source.owner) and raw.source.owner or nil
    source.repo = hasValue(raw.source.repo) and raw.source.repo or nil
    source.branch = hasValue(raw.source.branch) and raw.source.branch or nil
    source.manifestPath = hasValue(raw.source.manifestPath) and normalizePath(raw.source.manifestPath) or nil
    source.rawBaseUrl = hasValue(raw.source.rawBaseUrl) and raw.source.rawBaseUrl or nil
  end
  source.commit = commit

  local integrity = {}
  if type(raw.integrity) == "table" then
    local defaultHashAlgo = normalizeHashAlgo(raw.integrity.defaultHashAlgo) or "sha256"
    if not isSupportedHashAlgo(defaultHashAlgo) then
      return nil, "manifest integrity default hash algorithm unsupported: " .. tostring(defaultHashAlgo)
    end

    integrity.mode = hasValue(raw.integrity.mode) and tostring(raw.integrity.mode) or "hash+size"
    integrity.hashPlanned = raw.integrity.hashPlanned == true
    integrity.hashRequired = raw.integrity.hashRequired ~= false
    integrity.defaultHashAlgo = defaultHashAlgo
    integrity.hashAlgorithms = type(raw.integrity.hashAlgorithms) == "table" and raw.integrity.hashAlgorithms or { "sha256" }
  else
    integrity.mode = "hash+size"
    integrity.hashPlanned = false
    integrity.hashRequired = true
    integrity.defaultHashAlgo = "sha256"
    integrity.hashAlgorithms = { "sha256" }
  end

  return {
    name = tostring(raw.name),
    version = tostring(raw.version),
    channel = hasValue(raw.channel) and tostring(raw.channel) or "stable",
    entrypoint = normalizePath(raw.entrypoint),
    files = files,
    source = source,
    commit = commit,
    integrity = integrity,
  }
end

function M.readLocal(path)
  path = path or "fusion.manifest.json"
  if not fs.exists(path) then
    return nil, "missing local manifest: " .. tostring(path)
  end

  local fh = fs.open(path, "r")
  if not fh then
    return nil, "cannot open local manifest: " .. tostring(path)
  end

  local text = fh.readAll() or ""
  fh.close()

  local raw, decodeErr = decodeJson(text)
  if not raw then
    return nil, "invalid local manifest json: " .. tostring(decodeErr)
  end

  local manifest, validErr = M.validate(raw)
  if not manifest then
    return nil, "invalid local manifest: " .. tostring(validErr)
  end

  return manifest, text
end

function M.readRemote(client, manifestUrl)
  local text, fetchErr = client.fetchText(manifestUrl)
  if not text then
    return nil, "manifest download failed: " .. tostring(fetchErr)
  end

  local raw, decodeErr = decodeJson(text)
  if not raw then
    return nil, "invalid remote manifest json: " .. tostring(decodeErr)
  end

  local manifest, validErr = M.validate(raw)
  if not manifest then
    return nil, "invalid remote manifest: " .. tostring(validErr)
  end

  return manifest, text
end

function M.mapByPath(manifest)
  local map = {}
  if type(manifest) ~= "table" or type(manifest.files) ~= "table" then
    return map
  end

  for _, entry in ipairs(manifest.files) do
    map[entry.path] = entry
  end
  return map
end

function M.computePendingFiles(localManifest, remoteManifest)
  local pending = {}
  local localMap = M.mapByPath(localManifest)

  if type(remoteManifest) ~= "table" or type(remoteManifest.files) ~= "table" then
    return pending
  end

  for _, remoteEntry in ipairs(remoteManifest.files) do
    local localEntry = localMap[remoteEntry.path]
    local exists = fs.exists(remoteEntry.path)
    local currentSize = exists and fs.getSize(remoteEntry.path) or nil

    local needsUpdate = false
    if not exists then
      needsUpdate = true
    elseif remoteEntry.size and currentSize and currentSize ~= remoteEntry.size then
      needsUpdate = true
    elseif localEntry and localEntry.size and remoteEntry.size and localEntry.size ~= remoteEntry.size then
      needsUpdate = true
    elseif localEntry and localEntry.hash and remoteEntry.hash and localEntry.hash ~= remoteEntry.hash then
      needsUpdate = true
    elseif not localEntry then
      needsUpdate = true
    end

    if needsUpdate then
      pending[#pending + 1] = remoteEntry
    end
  end

  return pending
end

function M.validateDownloadManifest(manifest)
  if type(manifest) ~= "table" then
    return false, "manifest invalid for download"
  end
  if not hasValue(manifest.version) then
    return false, "manifest version missing"
  end
  if not hasValue(manifest.entrypoint) then
    return false, "manifest entrypoint missing"
  end
  if type(manifest.files) ~= "table" or #manifest.files == 0 then
    return false, "manifest files missing"
  end

  local commit = M.resolveCommit(manifest)
  if not M.isValidCommit(commit) then
    return false, "manifest commit missing or invalid (expected 40-hex sha)"
  end

  local defaultAlgo = "sha256"
  if type(manifest.integrity) == "table" and hasValue(manifest.integrity.defaultHashAlgo) then
    defaultAlgo = normalizeHashAlgo(manifest.integrity.defaultHashAlgo) or "sha256"
  end
  if not isSupportedHashAlgo(defaultAlgo) then
    return false, "manifest integrity default hash algorithm unsupported: " .. tostring(defaultAlgo)
  end

  for i, entry in ipairs(manifest.files) do
    local path = normalizePath(entry.path)
    if path == "" then
      return false, "manifest file path invalid at index " .. tostring(i)
    end
    if type(entry.size) ~= "number" or entry.size < 0 then
      return false, "manifest size missing for " .. tostring(path)
    end

    local hash = normalizeHash(entry.hash)
    if not hash then
      return false, "manifest hash missing for " .. tostring(path)
    end

    local hashAlgo = normalizeHashAlgo(entry.hashAlgo) or defaultAlgo
    if not isSupportedHashAlgo(hashAlgo) then
      return false, "manifest hash algorithm unsupported for " .. tostring(path) .. ": " .. tostring(hashAlgo)
    end
    if not isValidHash(hash, hashAlgo) then
      return false, "manifest hash format invalid for " .. tostring(path) .. ": " .. tostring(hash)
    end

    entry.hash = hash
    entry.hashAlgo = hashAlgo
  end

  return true, commit
end

return M
