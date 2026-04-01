-- Standalone rescue updater for CC:Tweaked.
-- Use when the main UI/update page cannot start.

local DEFAULT_SOURCE = {
  owner = "viper1331",
  repo = "Fusion-Tom-manage",
  branch = "main",
  manifestPath = "fusion.manifest.json",
}

local PATHS = {
  backupDir = "/backup_rescue",
  stagingDir = "/.rescue_staging",
  logFile = "/rescue_update.log",
}

local PRESERVE_LOCAL = {
  ["fusion_config.lua"] = true,
  ["rescue_update.lua"] = true,
}

local AUTO_LAUNCH_AFTER_UPDATE = false
local LoggerModule = nil
do
  local ok, loaded = pcall(dofile, "core/logging/logger.lua")
  if ok and type(loaded) == "table" and type(loaded.create) == "function" then
    LoggerModule = loaded
  end
end
local rescueLogger = nil

local function nowIso()
  local t = os.date("*t")
  return string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year, t.month, t.day, t.hour, t.min, t.sec)
end

local function parentDir(path)
  return fs.getDir(path)
end

local function ensureDir(path)
  if path == "" or path == "/" or path == "." then
    return
  end

  local current = ""
  for part in string.gmatch(path, "[^/]+") do
    current = current .. "/" .. part
    if not fs.exists(current) then
      fs.makeDir(current)
    end
  end
end

local function normalizeLogLevel(value)
  local raw = string.upper(tostring(value or "INFO"))
  if raw == "DEBUG" or raw == "INFO" or raw == "WARN" or raw == "ERROR" then
    return raw
  end
  return "INFO"
end

local function loggerWrite(level, category, message, context)
  if not rescueLogger then
    return false
  end

  local method = string.lower(normalizeLogLevel(level))
  local fn = rescueLogger[method]
  if type(fn) == "function" then
    fn(category or "RESCUE", tostring(message), context, "rescue")
    return true
  end

  if type(rescueLogger.info) == "function" then
    rescueLogger.info(category or "RESCUE", tostring(message), context, "rescue")
    return true
  end

  return false
end

local function appendLog(level, message, category, context)
  local normalizedLevel = normalizeLogLevel(level)
  local finalCategory = tostring(category or "RESCUE")
  local line = string.format("[%s] [%s] [%s] %s", nowIso(), normalizedLevel, finalCategory, tostring(message))
  print(line)

  if loggerWrite(normalizedLevel, finalCategory, message, context) then
    return
  end

  local dir = parentDir(PATHS.logFile)
  if dir and dir ~= "" then
    ensureDir(dir)
  end

  local h = fs.open(PATHS.logFile, "a")
  if h then
    h.writeLine(line)
    h.close()
  end
end

local function deletePath(path)
  if fs.exists(path) then
    fs.delete(path)
  end
end

local function cleanupStaging()
  deletePath(PATHS.stagingDir)
end

local function readAllBytes(path)
  if not fs.exists(path) then
    return nil
  end
  local h = fs.open(path, "rb")
  if not h then
    return nil
  end
  local data = h.readAll()
  h.close()
  return data
end

local function writeAllBytes(path, data)
  local dir = parentDir(path)
  if dir and dir ~= "" then
    ensureDir(dir)
  end
  local h = assert(fs.open(path, "wb"), "cannot open for write: " .. tostring(path))
  h.write(data)
  h.close()
end

local function firstTruthyString(...)
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if type(value) == "string" and value ~= "" then
      return value
    end
  end
  return nil
end

local function loadRuntimeSource()
  local source = {
    owner = DEFAULT_SOURCE.owner,
    repo = DEFAULT_SOURCE.repo,
    branch = DEFAULT_SOURCE.branch,
    manifestPath = DEFAULT_SOURCE.manifestPath,
    logging = {
      level = "INFO",
      files = {
        runtime = "ui_runtime.log",
        update = "update.log",
        rescue = PATHS.logFile,
      },
    },
  }

  local ok, cfg = pcall(dofile, "fusion_config.lua")
  if ok and type(cfg) == "table" then
    if type(cfg.update) == "table" then
      source.owner = firstTruthyString(cfg.update.owner, source.owner)
      source.repo = firstTruthyString(cfg.update.repo, source.repo)
      source.branch = firstTruthyString(cfg.update.branch, source.branch)
      source.manifestPath = firstTruthyString(cfg.update.manifestPath, source.manifestPath)
    end
    if type(cfg.logging) == "table" then
      source.logging.level = normalizeLogLevel(cfg.logging.level or source.logging.level)
      if type(cfg.logging.files) == "table" then
        source.logging.files.runtime = firstTruthyString(cfg.logging.files.runtime, source.logging.files.runtime)
        source.logging.files.update = firstTruthyString(cfg.logging.files.update, source.logging.files.update)
        source.logging.files.rescue = firstTruthyString(cfg.logging.files.rescue, source.logging.files.rescue)
      end
    end
  end

  PATHS.logFile = source.logging.files.rescue
  return source
end

local function percentEncodeSegment(segment)
  return (segment:gsub("([^%w%-%.%_~])", function(ch)
    return string.format("%%%02X", string.byte(ch))
  end))
end

local function encodeRelativePath(path)
  local out = {}
  for segment in string.gmatch(path, "[^/]+") do
    out[#out + 1] = percentEncodeSegment(segment)
  end
  return table.concat(out, "/")
end

local function buildRawUrl(source, ref, relativePath)
  return string.format(
    "https://raw.githubusercontent.com/%s/%s/%s/%s",
    source.owner,
    source.repo,
    ref,
    encodeRelativePath(relativePath)
  )
end

local function httpReadAll(url)
  local response, err = http.get(url, nil, true)
  if not response then
    return nil, err or "http request failed"
  end

  local body = response.readAll()
  response.close()
  if not body then
    return nil, "empty response body"
  end
  return body
end

local function normalizePath(path)
  if type(path) ~= "string" then
    return ""
  end
  local out = path:gsub("\\", "/")
  out = out:gsub("^%./", "")
  out = out:gsub("^/", "")
  return out
end

local function parseManifest(jsonText)
  local ok, manifest = pcall(textutils.unserializeJSON, jsonText)
  if not ok or type(manifest) ~= "table" then
    return nil, "invalid manifest JSON"
  end

  if type(manifest.files) ~= "table" then
    return nil, "manifest missing files"
  end

  local commit = firstTruthyString(
    manifest.commit,
    type(manifest.source) == "table" and manifest.source.commit or nil
  )
  manifest.__resolvedCommit = commit
  return manifest
end

local function normalizeManifestFiles(files)
  local normalized = {}
  local seen = {}

  for _, entry in ipairs(files) do
    local rawPath = nil
    local size = nil
    local hash = nil
    local hashAlgo = nil

    if type(entry) == "string" then
      rawPath = entry
    elseif type(entry) == "table" and type(entry.path) == "string" then
      rawPath = entry.path
      size = entry.size
      hash = entry.hash
      hashAlgo = entry.hashAlgo
    end

    local path = normalizePath(rawPath or "")
    if path ~= "" and not seen[path] then
      seen[path] = true
      normalized[#normalized + 1] = {
        path = path,
        size = type(size) == "number" and size or nil,
        hash = type(hash) == "string" and hash:lower() or nil,
        hashAlgo = type(hashAlgo) == "string" and hashAlgo:lower() or nil,
      }
    end
  end

  return normalized
end

local function optionalHashModule()
  local ok, mod = pcall(dofile, "core/update/hash.lua")
  if ok and type(mod) == "table" and type(mod.sha256Hex) == "function" then
    return mod
  end
  return nil
end

local function verifyPayload(fileEntry, payload, hashModule)
  if type(fileEntry.size) == "number" and #payload ~= fileEntry.size then
    return false, string.format("size mismatch expected=%d received=%d", fileEntry.size, #payload)
  end

  if fileEntry.hash and fileEntry.hashAlgo == "sha256" and hashModule then
    local computed = hashModule.sha256Hex(payload)
    if computed ~= fileEntry.hash then
      return false, string.format("hash mismatch expected=%s received=%s", fileEntry.hash, computed)
    end
  end

  return true, "ok"
end

local function backupFile(path)
  if not fs.exists(path) then
    return
  end
  local data = readAllBytes(path)
  if not data then
    return
  end
  local backupPath = PATHS.backupDir .. "/" .. path
  writeAllBytes(backupPath, data)
  appendLog("INFO", "backup " .. path)
end

local function restoreBackup(path)
  local backupPath = PATHS.backupDir .. "/" .. path
  if not fs.exists(backupPath) then
    return
  end
  local data = readAllBytes(backupPath)
  if not data then
    return
  end
  writeAllBytes(path, data)
  appendLog("WARN", "rollback " .. path)
end

local function confirm(question)
  write(question .. " [o/N] ")
  local answer = tostring(read() or ""):lower()
  return answer == "o" or answer == "oui" or answer == "y" or answer == "yes"
end

local function resolveEntrypoint(manifest)
  local path = normalizePath(manifest and manifest.entrypoint or "")
  if path ~= "" then
    return path
  end
  return "start.lua"
end

local function main()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)

  appendLog("INFO", "rescue update started")
  if not http then
    error("HTTP unavailable. Enable http in CC:Tweaked config.")
  end

  local source = loadRuntimeSource()
  if LoggerModule then
    rescueLogger = LoggerModule.create({
      level = source.logging.level,
      defaultSink = "rescue",
      files = source.logging.files,
    })
  end
  appendLog("INFO", "source owner=" .. source.owner .. " repo=" .. source.repo .. " branch=" .. source.branch)

  cleanupStaging()
  ensureDir(PATHS.backupDir)
  ensureDir(PATHS.stagingDir)

  local manifestUrl = buildRawUrl(source, source.branch, source.manifestPath)
  appendLog("INFO", "manifest url=" .. manifestUrl)
  local manifestBody, manifestErr = httpReadAll(manifestUrl)
  if not manifestBody then
    error("manifest download failed: " .. tostring(manifestErr))
  end

  local manifest, parseErr = parseManifest(manifestBody)
  if not manifest then
    error(parseErr)
  end

  local files = normalizeManifestFiles(manifest.files)
  if #files < 1 then
    error("manifest files list empty")
  end

  local pinnedRef = firstTruthyString(manifest.__resolvedCommit, source.branch)
  local entrypoint = resolveEntrypoint(manifest)
  local hashModule = optionalHashModule()

  appendLog("INFO", string.format(
    "manifest version=%s pinnedRef=%s files=%d entrypoint=%s hashRuntime=%s",
    tostring(manifest.version or "n/a"),
    tostring(pinnedRef),
    #files,
    entrypoint,
    hashModule and "sha256" or "disabled"
  ))

  writeAllBytes(PATHS.stagingDir .. "/" .. source.manifestPath, manifestBody)

  for index, fileEntry in ipairs(files) do
    local url = buildRawUrl(source, pinnedRef, fileEntry.path)
    appendLog("INFO", string.format("download (%d/%d) path=%s", index, #files, fileEntry.path))
    appendLog("INFO", "download url=" .. url)
    local payload, err = httpReadAll(url)
    if not payload then
      cleanupStaging()
      error("download failed " .. fileEntry.path .. ": " .. tostring(err))
    end

    local ok, reason = verifyPayload(fileEntry, payload, hashModule)
    if not ok then
      cleanupStaging()
      error("validation failed " .. fileEntry.path .. ": " .. reason)
    end

    writeAllBytes(PATHS.stagingDir .. "/" .. fileEntry.path, payload)
  end

  appendLog("INFO", "download complete")
  if not confirm("Apply rescue update now?") then
    appendLog("WARN", "cancelled by user")
    return
  end

  local applied = {}
  local ok, err = pcall(function()
    for _, fileEntry in ipairs(files) do
      if not PRESERVE_LOCAL[fileEntry.path] then
        backupFile(fileEntry.path)
      else
        appendLog("INFO", "preserve local " .. fileEntry.path)
      end
    end

    for _, fileEntry in ipairs(files) do
      if not PRESERVE_LOCAL[fileEntry.path] then
        local stagedPath = PATHS.stagingDir .. "/" .. fileEntry.path
        local payload = readAllBytes(stagedPath)
        if not payload then
          error("missing staged file " .. fileEntry.path)
        end
        writeAllBytes(fileEntry.path, payload)
        applied[#applied + 1] = fileEntry.path
        appendLog("INFO", "applied " .. fileEntry.path)
      end
    end

    local stagedManifestPath = PATHS.stagingDir .. "/" .. source.manifestPath
    local stagedManifest = readAllBytes(stagedManifestPath)
    if stagedManifest and not PRESERVE_LOCAL[source.manifestPath] then
      writeAllBytes(source.manifestPath, stagedManifest)
      appendLog("INFO", "manifest synced " .. source.manifestPath)
    end

    cleanupStaging()
  end)

  if not ok then
    appendLog("ERROR", "apply failed: " .. tostring(err))
    for i = #applied, 1, -1 do
      restoreBackup(applied[i])
    end
    cleanupStaging()
    error(err)
  end

  appendLog("INFO", "rescue update applied successfully")
  if AUTO_LAUNCH_AFTER_UPDATE and confirm("Launch " .. entrypoint .. " now?") then
    appendLog("INFO", "launch " .. entrypoint)
    shell.run(entrypoint)
  else
    print("")
    print("Rescue update complete.")
    print("Recommended entrypoint: " .. entrypoint)
  end
end

local ok, err = pcall(main)
if not ok then
  appendLog("ERROR", tostring(err))
  print("")
  print("RESCUE UPDATE FAILED")
  print(tostring(err))
  print("Check log: " .. PATHS.logFile)
end
