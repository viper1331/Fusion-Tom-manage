local M = {}
local STAGING_META_NAME = "staging_meta.lua"

local function normalizePath(path)
  path = tostring(path or "")
  path = string.gsub(path, "\\", "/")
  path = string.gsub(path, "^%./", "")
  path = string.gsub(path, "^/", "")
  return path
end

local function ensureParent(path)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function readBinary(path)
  local fh = fs.open(path, "rb")
  if not fh then
    return nil, "cannot read file: " .. tostring(path)
  end
  local data = fh.readAll()
  fh.close()
  return data
end

local function writeBinary(path, data)
  ensureParent(path)
  local fh = fs.open(path, "wb")
  if not fh then
    return false, "cannot write file: " .. tostring(path)
  end
  fh.write(data or "")
  fh.close()
  return true
end

local function copyFile(sourcePath, targetPath)
  local data, err = readBinary(sourcePath)
  if not data then
    return false, err
  end
  return writeBinary(targetPath, data)
end

local function deleteTree(path)
  if not fs.exists(path) then
    return true
  end

  if fs.isDir(path) then
    for _, name in ipairs(fs.list(path)) do
      local ok, err = deleteTree(fs.combine(path, name))
      if not ok then
        return false, err
      end
    end
  end

  fs.delete(path)
  if fs.exists(path) then
    return false, "cannot delete path: " .. tostring(path)
  end

  return true
end

local function loadMeta(metaPath)
  if not fs.exists(metaPath) then
    return nil, "backup meta not found"
  end

  local ok, data = pcall(dofile, metaPath)
  if not ok or type(data) ~= "table" then
    return nil, "invalid backup meta"
  end

  return data
end

local function saveMeta(metaPath, meta)
  ensureParent(metaPath)
  local fh = fs.open(metaPath, "w")
  if not fh then
    return false, "cannot write backup meta"
  end
  fh.write("return ")
  fh.write(textutils.serialize(meta))
  fh.close()
  return true
end

local function listPaths(fileEntries)
  local out = {}
  for _, entry in ipairs(fileEntries or {}) do
    local path = normalizePath(entry.path)
    if path ~= "" then
      out[#out + 1] = path
    end
  end
  return out
end

local function mapByPath(list)
  local map = {}
  for _, entry in ipairs(list or {}) do
    if type(entry) == "table" and type(entry.path) == "string" and entry.path ~= "" then
      map[entry.path] = entry
    end
  end
  return map
end

function M.clearPath(path)
  return deleteTree(path)
end

function M.readStagingMeta(stagingDir)
  local metaPath = fs.combine(stagingDir, STAGING_META_NAME)
  return loadMeta(metaPath)
end

function M.writeStagingMeta(stagingDir, meta)
  local metaPath = fs.combine(stagingDir, STAGING_META_NAME)
  return saveMeta(metaPath, meta)
end

function M.markStagingReady(fileEntries, stagingDir, context)
  local files = {}

  for _, entry in ipairs(fileEntries or {}) do
    local path = normalizePath(entry.path)
    if path ~= "" then
      files[#files + 1] = {
        path = path,
        size = type(entry.size) == "number" and math.max(0, math.floor(entry.size)) or nil,
        hash = type(entry.hash) == "string" and entry.hash or nil,
        hashAlgo = type(entry.hashAlgo) == "string" and entry.hashAlgo or nil,
      }
    end
  end

  local meta = {
    createdAt = os.date("%Y-%m-%d %H:%M:%S"),
    complete = true,
    fileCount = #files,
    files = files,
    context = type(context) == "table" and context or {},
  }

  return M.writeStagingMeta(stagingDir, meta)
end

function M.validateStaging(fileEntries, stagingDir, expectedContext)
  if type(stagingDir) ~= "string" or stagingDir == "" then
    return false, "invalid staging directory"
  end

  if not fs.exists(stagingDir) or not fs.isDir(stagingDir) then
    return false, "staging directory missing: " .. tostring(stagingDir)
  end

  local meta, metaErr = M.readStagingMeta(stagingDir)
  if not meta then
    return false, "staging meta missing: " .. tostring(metaErr)
  end

  if meta.complete ~= true then
    return false, "staging is not finalized"
  end

  if type(meta.files) ~= "table" then
    return false, "staging meta invalid: files list missing"
  end

  local expectedList = listPaths(fileEntries)
  local metaMap = mapByPath(meta.files)
  if type(meta.fileCount) == "number" and meta.fileCount ~= #expectedList then
    return false, "staging meta fileCount mismatch"
  end

  if type(expectedContext) == "table" then
    local stagedContext = type(meta.context) == "table" and meta.context or {}
    if type(expectedContext.remoteVersion) == "string" and expectedContext.remoteVersion ~= "" and stagedContext.remoteVersion ~= expectedContext.remoteVersion then
      return false, "staging version mismatch"
    end
    if type(expectedContext.manifestVersion) == "string" and expectedContext.manifestVersion ~= "" and stagedContext.manifestVersion ~= expectedContext.manifestVersion then
      return false, "staging manifest mismatch"
    end
  end

  for i, entry in ipairs(fileEntries or {}) do
    local path = normalizePath(entry.path)
    if path == "" then
      return false, "invalid manifest entry at index " .. tostring(i)
    end

    if not metaMap[path] then
      return false, "staging meta missing path: " .. tostring(path)
    end

    local stagedPath = fs.combine(stagingDir, path)
    if not fs.exists(stagedPath) then
      return false, "missing staged file: " .. tostring(path)
    end

    if type(entry.size) == "number" and entry.size >= 0 then
      local size = fs.getSize(stagedPath)
      if size ~= entry.size then
        return false, "size mismatch in staging for " .. tostring(path)
      end
    end

    local stagedMeta = metaMap[path]
    if type(stagedMeta.size) == "number" and stagedMeta.size >= 0 and type(entry.size) == "number" and entry.size >= 0 and stagedMeta.size ~= entry.size then
      return false, "staging meta size mismatch for " .. tostring(path)
    end
  end

  return true
end

function M.createBackup(fileEntries, backupDir, context, logger)
  local backupFilesDir = fs.combine(backupDir, "files")
  local metaPath = fs.combine(backupDir, "backup_meta.lua")
  local ok, err = deleteTree(backupDir)
  if not ok then
    return nil, err
  end
  fs.makeDir(backupFilesDir)

  local meta = {
    createdAt = os.date("%Y-%m-%d %H:%M:%S"),
    context = type(context) == "table" and context or {},
    appliedFiles = {},
    backedUp = {},
  }

  for _, entry in ipairs(fileEntries or {}) do
    local path = normalizePath(entry.path)
    if path ~= "" then
      meta.appliedFiles[#meta.appliedFiles + 1] = path
      if fs.exists(path) then
        local sourcePath = path
        local targetPath = fs.combine(backupFilesDir, path)
        local copyOk, copyErr = copyFile(sourcePath, targetPath)
        if not copyOk then
          return nil, copyErr
        end
        meta.backedUp[path] = true
        if logger then
          logger("backup " .. tostring(path))
        end
      else
        meta.backedUp[path] = false
      end
    end
  end

  local metaOk, metaErr = saveMeta(metaPath, meta)
  if not metaOk then
    return nil, metaErr
  end

  return {
    backupDir = backupDir,
    filesDir = backupFilesDir,
    metaPath = metaPath,
    meta = meta,
  }
end

function M.applyFromStaging(fileEntries, stagingDir, logger)
  local valid, validErr = M.validateStaging(fileEntries, stagingDir)
  if not valid then
    return false, validErr
  end

  for _, entry in ipairs(fileEntries or {}) do
    local path = normalizePath(entry.path)
    local sourcePath = fs.combine(stagingDir, path)
    local targetPath = path
    local ok, err = copyFile(sourcePath, targetPath)
    if not ok then
      return false, err
    end

    if logger then
      logger("applied " .. tostring(path))
    end
  end

  return true
end

function M.rollback(backupDir, logger)
  local metaPath = fs.combine(backupDir, "backup_meta.lua")
  local filesDir = fs.combine(backupDir, "files")
  local meta, metaErr = loadMeta(metaPath)
  if not meta then
    return false, metaErr
  end

  for _, path in ipairs(meta.appliedFiles or {}) do
    local normalizedPath = normalizePath(path)
    local hadBackup = meta.backedUp and meta.backedUp[normalizedPath] == true
    local backupPath = fs.combine(filesDir, normalizedPath)

    if hadBackup then
      if not fs.exists(backupPath) then
        return false, "missing backup file: " .. tostring(normalizedPath)
      end

      local ok, err = copyFile(backupPath, normalizedPath)
      if not ok then
        return false, err
      end

      if logger then
        logger("rollback restore " .. tostring(normalizedPath))
      end
    else
      if fs.exists(normalizedPath) then
        fs.delete(normalizedPath)
      end
      if logger then
        logger("rollback remove " .. tostring(normalizedPath))
      end
    end
  end

  return true
end

function M.loadBackupMeta(backupDir)
  local metaPath = fs.combine(backupDir, "backup_meta.lua")
  return loadMeta(metaPath)
end

return M
