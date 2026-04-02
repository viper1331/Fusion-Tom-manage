local M = {}

local UpdateVersion = assert(dofile("core/update/version.lua"))
local UpdateManifest = assert(dofile("core/update/manifest.lua"))
local UpdateClient = assert(dofile("core/update/client.lua"))
local UpdateApply = assert(dofile("core/update/apply.lua"))

local DEFAULTS = {
  versionFile = "fusion.version",
  manifestFile = "fusion.manifest.json",
  tempDir = "/.update_tmp",
  backupDir = "/.backup_last",
}

local function nowText()
  local ok, value = pcall(os.date, "%Y-%m-%d %H:%M:%S")
  if ok and type(value) == "string" and value ~= "" then
    return value
  end
  return tostring(os.epoch and os.epoch("utc") or 0)
end

local function trim(value)
  value = tostring(value or "")
  value = string.gsub(value, "^%s+", "")
  value = string.gsub(value, "%s+$", "")
  return value
end

local function normalizePath(path)
  path = tostring(path or "")
  path = string.gsub(path, "\\", "/")
  path = string.gsub(path, "^%./", "")
  path = string.gsub(path, "^/", "")
  return path
end

local function normalizeIntegrityMode(value)
  local raw = string.lower(trim(value))
  if raw == "size-only" or raw == "size_only" or raw == "sizeonly" then
    return "size-only"
  end
  return "size+hash"
end

local function appendLog(logger, message)
  if type(logger) == "function" then
    pcall(logger, tostring(message))
  end
end

local function firstLine(value)
  local raw = tostring(value or "")
  local line = string.match(raw, "([^\r\n]+)")
  if line and line ~= "" then
    return line
  end
  return raw
end

local function buildSource(cfg)
  cfg = cfg or {}
  local updateCfg = type(cfg.update) == "table" and cfg.update or {}
  return {
    owner = tostring(updateCfg.owner or ""),
    repo = tostring(updateCfg.repo or ""),
    branch = tostring(updateCfg.branch or "main"),
    manifestPath = tostring(updateCfg.manifestPath or DEFAULTS.manifestFile),
    rawBaseUrl = tostring(updateCfg.rawBaseUrl or ""),
    integrityMode = normalizeIntegrityMode(updateCfg.integrityMode),
  }
end

local function buildPaths(cfg)
  local updateCfg = type(cfg.update) == "table" and cfg.update or {}
  return {
    versionFile = tostring(updateCfg.versionFile or DEFAULTS.versionFile),
    manifestFile = tostring(updateCfg.localManifestPath or DEFAULTS.manifestFile),
    tempDir = tostring(updateCfg.tempDir or DEFAULTS.tempDir),
    backupDir = tostring(updateCfg.backupDir or DEFAULTS.backupDir),
  }
end

local function buildRawManifestUrl(source)
  local manifestPath = normalizePath(source.manifestPath or DEFAULTS.manifestFile)
  local sourceForUrl = {
    owner = source.owner,
    repo = source.repo,
    branch = source.branch,
    rawBaseUrl = source.rawBaseUrl,
  }
  return UpdateClient.buildRawUrl(sourceForUrl, manifestPath)
end

local function basicResult(step, cfg)
  local source = buildSource(cfg)
  local paths = buildPaths(cfg)
  local localVersion = select(1, UpdateVersion.readLocalVersion(paths.versionFile))
  local localManifest = select(1, UpdateManifest.readLocal(paths.manifestFile))
  return {
    ok = false,
    step = step,
    changed = false,
    checkedAt = nowText(),
    localVersionBefore = localVersion,
    localVersionAfter = localVersion,
    remoteVersion = nil,
    remoteCommit = nil,
    remoteBranch = source.branch,
    pendingFiles = 0,
    downloadedFiles = 0,
    detail = "",
    manifestUrl = nil,
    integrityMode = source.integrityMode,
    entrypoint = localManifest and localManifest.entrypoint or "start.lua",
  }
end

local function readRemoteManifest(cfg, logger)
  local source = buildSource(cfg)
  local manifestUrl = buildRawManifestUrl(source)
  appendLog(logger, "manifest url=" .. tostring(manifestUrl))
  local manifest, remoteTextOrErr = UpdateManifest.readRemote(UpdateClient, manifestUrl)
  if not manifest then
    return nil, remoteTextOrErr, manifestUrl
  end

  local validated, commitOrErr = UpdateManifest.validateDownloadManifest(manifest, {
    integrityMode = source.integrityMode,
  })
  if not validated then
    return nil, commitOrErr, manifestUrl
  end

  local runtimeSource = {
    owner = source.owner,
    repo = source.repo,
    branch = source.branch,
    commit = commitOrErr,
    rawBaseUrl = source.rawBaseUrl,
    defaultHashAlgo = type(manifest.integrity) == "table" and manifest.integrity.defaultHashAlgo or "sha256",
  }

  return {
    manifest = manifest,
    manifestText = remoteTextOrErr,
    manifestUrl = manifestUrl,
    runtimeSource = runtimeSource,
    remoteCommit = commitOrErr,
  }
end

function M.check(cfg, logger)
  local result = basicResult("check", cfg)
  local remote, remoteErr, manifestUrl = readRemoteManifest(cfg, logger)
  result.manifestUrl = manifestUrl
  if not remote then
    result.detail = firstLine(remoteErr)
    return result, result.detail
  end

  result.remoteVersion = tostring(remote.manifest.version or "n/a")
  result.remoteCommit = remote.remoteCommit
  result.entrypoint = tostring(remote.manifest.entrypoint or result.entrypoint)

  local localManifest = select(1, UpdateManifest.readLocal(buildPaths(cfg).manifestFile))
  local pending = UpdateManifest.computePendingFiles(localManifest, remote.manifest)
  result.pendingFiles = #pending
  local newer = UpdateVersion.isRemoteNewer(result.localVersionBefore or "", result.remoteVersion)
  result.changed = newer == true or #pending > 0
  result.ok = true
  result.detail = result.changed and "update available" or "up to date"
  return result
end

function M.download(cfg, logger)
  local result = basicResult("download", cfg)
  local remote, remoteErr, manifestUrl = readRemoteManifest(cfg, logger)
  result.manifestUrl = manifestUrl
  if not remote then
    result.detail = firstLine(remoteErr)
    return result, result.detail
  end

  result.remoteVersion = tostring(remote.manifest.version or "n/a")
  result.remoteCommit = remote.remoteCommit

  local paths = buildPaths(cfg)
  UpdateApply.clearPath(paths.tempDir)
  if not fs.exists(paths.tempDir) then
    fs.makeDir(paths.tempDir)
  end

  local downloaded, err = UpdateClient.downloadFiles(remote.runtimeSource, remote.manifest.files, paths.tempDir, logger)
  if not downloaded then
    result.detail = firstLine(err)
    UpdateApply.clearPath(paths.tempDir)
    return result, result.detail
  end

  if result.integrityMode ~= "size-only" then
    local validated, validationErr = UpdateClient.validateDownloadedHashes(remote.runtimeSource, remote.manifest.files, paths.tempDir, logger)
    if not validated then
      result.detail = firstLine(validationErr)
      UpdateApply.clearPath(paths.tempDir)
      return result, result.detail
    end
  end

  local marked, markedErr = UpdateApply.markStagingReady(remote.manifest.files, paths.tempDir, {
    remoteVersion = remote.manifest.version,
    manifestVersion = remote.manifest.version,
    remoteCommit = remote.remoteCommit,
    checkedAt = nowText(),
    integrityMode = result.integrityMode,
  })
  if not marked then
    result.detail = firstLine(markedErr)
    UpdateApply.clearPath(paths.tempDir)
    return result, result.detail
  end

  result.ok = true
  result.changed = #downloaded > 0
  result.downloadedFiles = #downloaded
  result.pendingFiles = #downloaded
  result.detail = "download ready"
  return result
end

function M.apply(cfg, logger)
  local result = basicResult("apply", cfg)
  local remote, remoteErr, manifestUrl = readRemoteManifest(cfg, logger)
  result.manifestUrl = manifestUrl
  if not remote then
    result.detail = firstLine(remoteErr)
    return result, result.detail
  end

  result.remoteVersion = tostring(remote.manifest.version or "n/a")
  result.remoteCommit = remote.remoteCommit

  local paths = buildPaths(cfg)
  local stageOk, stageErr = UpdateApply.validateStaging(remote.manifest.files, paths.tempDir, {
    remoteVersion = remote.manifest.version,
    manifestVersion = remote.manifest.version,
    remoteCommit = remote.remoteCommit,
    integrityMode = result.integrityMode,
  }, logger, "orchestrator apply", {
    skipHash = result.integrityMode == "size-only",
  })
  if not stageOk then
    result.detail = firstLine(stageErr)
    return result, result.detail
  end

  local backup, backupErr = UpdateApply.createBackup(remote.manifest.files, paths.backupDir, {
    previousVersion = result.localVersionBefore,
    previousManifestVersion = result.localVersionBefore,
  }, logger)
  if not backup then
    result.detail = firstLine(backupErr)
    return result, result.detail
  end

  local applied, applyErr = UpdateApply.applyFromStaging(remote.manifest.files, paths.tempDir, logger, {
    skipHash = result.integrityMode == "size-only",
  })
  if not applied then
    UpdateApply.rollback(paths.backupDir, logger)
    result.detail = firstLine(applyErr)
    return result, result.detail
  end

  if type(remote.manifestText) == "string" and remote.manifestText ~= "" then
    local fh = fs.open(paths.manifestFile, "w")
    if fh then
      fh.write(remote.manifestText)
      fh.close()
    end
  end

  UpdateApply.clearPath(paths.tempDir)

  local localVersionAfter = select(1, UpdateVersion.readLocalVersion(paths.versionFile))
  result.ok = true
  result.changed = true
  result.localVersionAfter = localVersionAfter
  result.pendingFiles = 0
  result.downloadedFiles = #remote.manifest.files
  result.detail = "apply done"
  return result
end

function M.rollback(cfg, logger)
  local result = basicResult("rollback", cfg)
  local paths = buildPaths(cfg)
  local ok, err = UpdateApply.rollback(paths.backupDir, logger)
  if not ok then
    result.detail = firstLine(err)
    return result, result.detail
  end

  UpdateApply.clearPath(paths.tempDir)
  local localVersionAfter = select(1, UpdateVersion.readLocalVersion(paths.versionFile))
  result.ok = true
  result.changed = true
  result.localVersionAfter = localVersionAfter
  result.detail = "rollback done"
  return result
end

function M.sync(cfg, logger)
  local checked = M.check(cfg, logger)
  if not checked.ok then
    checked.step = "sync"
    return checked, checked.detail
  end

  if not checked.changed then
    checked.step = "sync"
    checked.detail = "already up to date"
    return checked
  end

  local downloaded = M.download(cfg, logger)
  if not downloaded.ok then
    downloaded.step = "sync"
    return downloaded, downloaded.detail
  end

  local applied = M.apply(cfg, logger)
  if not applied.ok then
    applied.step = "sync"
    return applied, applied.detail
  end

  applied.step = "sync"
  applied.detail = "sync done"
  return applied
end

return M
