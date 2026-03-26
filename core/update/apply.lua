local M = {}

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

function M.clearPath(path)
  return deleteTree(path)
end

function M.validateStaging(fileEntries, stagingDir)
  for i, entry in ipairs(fileEntries or {}) do
    local path = normalizePath(entry.path)
    if path == "" then
      return false, "invalid manifest entry at index " .. tostring(i)
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
