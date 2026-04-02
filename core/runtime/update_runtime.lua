local M = {}
local UpdateFormat = assert(dofile("core/update/format.lua"))

function M.create(args)
  local state = args.state
  local colors = type(args.colors) == "table" and args.colors or {}
  local C = {
    green = tonumber(colors.green) or 0xFF40D46A,
    orange = tonumber(colors.orange) or 0xFFE3A33D,
    cyan = tonumber(colors.cyan) or 0xFF52C7FF,
    yellow = tonumber(colors.yellow) or 0xFFE4C84A,
    red = tonumber(colors.red) or 0xFFE05252,
    muted = tonumber(colors.muted) or 0xFF9AA8B8,
  }
  local UPDATE_CFG = args.updateCfg
  local UPDATE_STATUS = args.updateStatus
  local INTEGRITY_STATUS = args.integrityStatus
  local UPDATE_VERSION_FILE = args.updateVersionFile
  local UPDATE_MANIFEST_FILE = args.updateManifestFile
  local UPDATE_LOG_FILE = args.updateLogFile
  local UPDATE_TEMP_DIR = args.updateTempDir
  local UPDATE_BACKUP_DIR = args.updateBackupDir
  local UpdateVersion = args.updateVersion
  local UpdateManifest = args.updateManifest
  local UpdateClient = args.updateClient
  local UpdateApply = args.updateApply
  local normalizeIntegrityMode = args.normalizeIntegrityMode
  local firstLine = args.firstLine
  local nowMs = args.nowMs
  local logWithLevel = args.logWithLevel

local function clamp(value, minValue, maxValue)
  local n = tonumber(value) or 0
  local minN = tonumber(minValue) or 0
  local maxN = tonumber(maxValue) or minN
  if n < minN then
    return minN
  end
  if n > maxN then
    return maxN
  end
  return n
end

local function round(value, precision)
  local p = math.max(0, math.floor(tonumber(precision) or 0))
  local factor = 10 ^ p
  local n = tonumber(value) or 0
  if n >= 0 then
    return math.floor(n * factor + 0.5) / factor
  end
  return math.ceil(n * factor - 0.5) / factor
end

local function nowText()
  local ok, value = pcall(os.date, "%Y-%m-%d %H:%M:%S")
  if ok and type(value) == "string" and value ~= "" then
    return value
  end
  return tostring(nowMs())
end

local function loadUpdateLogTail(maxLines)
  maxLines = math.max(1, math.floor(maxLines or 10))
  state.update.logs = {}

  if not fs.exists(UPDATE_LOG_FILE) then
    return
  end

  local fh = fs.open(UPDATE_LOG_FILE, "r")
  if not fh then
    return
  end

  local text = fh.readAll() or ""
  fh.close()

  local lines = {}
  for line in string.gmatch(text, "[^\r\n]+") do
    lines[#lines + 1] = line
  end

  local startAt = math.max(1, #lines - maxLines + 1)
  for i = startAt, #lines do
    state.update.logs[#state.update.logs + 1] = lines[i]
  end
end

local function inferUpdateLogLevel(messageText)
  local lower = string.lower(tostring(messageText or ""))
  if string.find(lower, " failed", 1, true) ~= nil
    or string.find(lower, "error", 1, true) ~= nil
    or string.find(lower, "mismatch", 1, true) ~= nil then
    return "ERROR"
  end
  if string.find(lower, "warning", 1, true) ~= nil
    or string.find(lower, "skipped", 1, true) ~= nil
    or string.find(lower, "rollback", 1, true) ~= nil then
    return "WARN"
  end
  return "INFO"
end

local function appendUpdateLogLine(message)
  local text = tostring(message or "event")
  local level = inferUpdateLogLevel(text)
  local ok = logWithLevel(level, "UPDATE", text, nil, "update")
  if not ok then
    local entry = "[" .. nowText() .. "] [" .. level .. "] [UPDATE] " .. text
    local fh = fs.open(UPDATE_LOG_FILE, "a")
    if fh then
      fh.writeLine(entry)
      fh.close()
    end
  end
  loadUpdateLogTail(12)
end

local function updateStatusColor(status)
  local mutedColor = (type(C) == "table" and tonumber(C.muted)) or 0xFF9AA8B8
  if status == UPDATE_STATUS.UP_TO_DATE then
    return (type(C) == "table" and tonumber(C.green)) or 0xFF40D46A
  end
  if status == UPDATE_STATUS.UPDATE_AVAILABLE or status == UPDATE_STATUS.READY_TO_APPLY then
    return (type(C) == "table" and tonumber(C.orange)) or 0xFFE3A33D
  end
  if status == UPDATE_STATUS.CHECKING or status == UPDATE_STATUS.DOWNLOADING or status == UPDATE_STATUS.APPLYING then
    return (type(C) == "table" and tonumber(C.cyan)) or 0xFF52C7FF
  end
  if status == UPDATE_STATUS.VALIDATING then
    return (type(C) == "table" and tonumber(C.yellow)) or 0xFFE4C84A
  end
  if status == UPDATE_STATUS.ROLLBACK_DONE then
    return (type(C) == "table" and tonumber(C.yellow)) or 0xFFE4C84A
  end
  if status == UPDATE_STATUS.CHECK_FAILED
    or status == UPDATE_STATUS.DOWNLOAD_FAILED
    or status == UPDATE_STATUS.VALIDATION_FAILED
    or status == UPDATE_STATUS.APPLY_FAILED
    or status == UPDATE_STATUS.ROLLBACK_FAILED
  then
    return (type(C) == "table" and tonumber(C.red)) or 0xFFE05252
  end
  return mutedColor
end

local function setUpdateStatus(status, detail, logIt)
  state.update.remoteStatus = status or UPDATE_STATUS.IDLE
  state.update.statusDetail = firstLine(detail or "")
  state.update.statusAt = nowText()
  if logIt then
    appendUpdateLogLine("STATUS " .. tostring(state.update.remoteStatus) .. " | " .. tostring(state.update.statusDetail))
  end
end

local function setDownloadedState(flag, count)
  state.update.downloaded = flag == true
  state.update.downloadedFiles = state.update.downloaded and math.max(0, math.floor(count or 0)) or 0
  if not state.update.downloaded then
    state.update.hashValidated = false
    state.update.applyConfirmArmed = false
  end
end

local function setDownloadProgress(progress)
  if type(state.update.downloadProgress) ~= "table" then
    state.update.downloadProgress = {}
  end

  local current = state.update.downloadProgress
  if type(progress) == "table" then
    if type(progress.phase) == "string" and progress.phase ~= "" then
      current.phase = progress.phase
    end
    if type(progress.totalFiles) == "number" then
      current.totalFiles = math.max(0, math.floor(progress.totalFiles))
    end
    if type(progress.completedFiles) == "number" then
      current.completedFiles = math.max(0, math.floor(progress.completedFiles))
    end
    if type(progress.totalBytesExpected) == "number" then
      current.totalBytesExpected = math.max(0, math.floor(progress.totalBytesExpected))
    end
    if type(progress.totalBytesCompleted) == "number" then
      current.totalBytesCompleted = math.max(0, math.floor(progress.totalBytesCompleted))
    end
    if type(progress.currentFile) == "string" and progress.currentFile ~= "" then
      current.currentFile = progress.currentFile
    end
    if type(progress.currentFileSize) == "number" then
      current.currentFileSize = math.max(0, math.floor(progress.currentFileSize))
    end
    if type(progress.note) == "string" and progress.note ~= "" then
      current.note = firstLine(progress.note)
    end
  end

  current.phase = current.phase or UPDATE_STATUS.IDLE
  current.totalFiles = math.max(0, math.floor(current.totalFiles or 0))
  current.completedFiles = math.max(0, math.floor(current.completedFiles or 0))
  current.totalBytesExpected = math.max(0, math.floor(current.totalBytesExpected or 0))
  current.totalBytesCompleted = math.max(0, math.floor(current.totalBytesCompleted or 0))
  current.currentFile = current.currentFile or "-"
  current.currentFileSize = math.max(0, math.floor(current.currentFileSize or 0))
  current.note = current.note or "idle"

  local percent = 0
  if current.totalBytesExpected > 0 then
    percent = (current.totalBytesCompleted * 100) / current.totalBytesExpected
  elseif current.totalFiles > 0 then
    percent = (current.completedFiles * 100) / current.totalFiles
  end

  current.percent = round(clamp(percent, 0, 100), 1)
end

local function resetDownloadProgress(phase, note)
  setDownloadProgress({
    phase = phase or UPDATE_STATUS.IDLE,
    totalFiles = 0,
    completedFiles = 0,
    totalBytesExpected = 0,
    totalBytesCompleted = 0,
    currentFile = "-",
    currentFileSize = 0,
    note = note or "idle",
  })
end

local function setValidationProgress(progress)
  if type(state.update.validationProgress) ~= "table" then
    state.update.validationProgress = {}
  end

  local current = state.update.validationProgress
  if type(progress) == "table" then
    if type(progress.phase) == "string" and progress.phase ~= "" then
      current.phase = progress.phase
    end
    if type(progress.totalFiles) == "number" then
      current.totalFiles = math.max(0, math.floor(progress.totalFiles))
    end
    if type(progress.completedFiles) == "number" then
      current.completedFiles = math.max(0, math.floor(progress.completedFiles))
    end
    if type(progress.totalBytesExpected) == "number" then
      current.totalBytesExpected = math.max(0, math.floor(progress.totalBytesExpected))
    end
    if type(progress.totalBytesCompleted) == "number" then
      current.totalBytesCompleted = math.max(0, math.floor(progress.totalBytesCompleted))
    end
    if type(progress.currentFile) == "string" and progress.currentFile ~= "" then
      current.currentFile = progress.currentFile
    end
    if type(progress.currentFileSize) == "number" then
      current.currentFileSize = math.max(0, math.floor(progress.currentFileSize))
    end
    if type(progress.note) == "string" and progress.note ~= "" then
      current.note = firstLine(progress.note)
    end
  end

  current.phase = current.phase or UPDATE_STATUS.IDLE
  current.totalFiles = math.max(0, math.floor(current.totalFiles or 0))
  current.completedFiles = math.max(0, math.floor(current.completedFiles or 0))
  current.totalBytesExpected = math.max(0, math.floor(current.totalBytesExpected or 0))
  current.totalBytesCompleted = math.max(0, math.floor(current.totalBytesCompleted or 0))
  current.currentFile = current.currentFile or "-"
  current.currentFileSize = math.max(0, math.floor(current.currentFileSize or 0))
  current.note = current.note or "idle"

  local percent = 0
  if current.totalBytesExpected > 0 then
    percent = (current.totalBytesCompleted * 100) / current.totalBytesExpected
  elseif current.totalFiles > 0 then
    percent = (current.completedFiles * 100) / current.totalFiles
  end

  current.percent = round(clamp(percent, 0, 100), 1)
end

local function resetValidationProgress(phase, note)
  setValidationProgress({
    phase = phase or UPDATE_STATUS.IDLE,
    totalFiles = 0,
    completedFiles = 0,
    totalBytesExpected = 0,
    totalBytesCompleted = 0,
    currentFile = "-",
    currentFileSize = 0,
    note = note or "idle",
  })
end

local function sumManifestEntrySizes(fileEntries)
  local total = 0
  for _, entry in ipairs(fileEntries or {}) do
    if type(entry) == "table" and type(entry.size) == "number" and entry.size >= 0 then
      total = total + math.max(0, math.floor(entry.size))
    end
  end
  return total
end

local function integrityStatusColor(status)
  if status == INTEGRITY_STATUS.OK then
    return C.green
  end
  if status == INTEGRITY_STATUS.HASH_FAILED or status == INTEGRITY_STATUS.STAGING_INVALID then
    return C.red
  end
  return C.orange
end

local function shortIntegrityStatus(status)
  if status == INTEGRITY_STATUS.OK then
    return "INT OK"
  end
  if status == INTEGRITY_STATUS.HASH_FAILED then
    return "INT FAIL"
  end
  if status == INTEGRITY_STATUS.STAGING_INVALID then
    return "STG BAD"
  end
  return "INT WAIT"
end

local function setIntegrityStatus(status, detail, logIt)
  state.update.integrityStatus = status or INTEGRITY_STATUS.PENDING
  if type(detail) == "string" and detail ~= "" then
    state.update.integrityDetail = firstLine(detail)
  end
  if logIt then
    appendUpdateLogLine("INTEGRITY " .. tostring(state.update.integrityStatus) .. " | " .. tostring(state.update.integrityDetail))
  end
end

local function setIntegrityFromError(rawErr)
  local raw = firstLine(rawErr or "")
  local lower = string.lower(raw)

  if string.find(lower, "hash mismatch", 1, true)
    or string.find(lower, "hash compute failed", 1, true)
  then
    setIntegrityStatus(INTEGRITY_STATUS.HASH_FAILED, raw, true)
    return
  end

  if string.find(lower, "staging", 1, true)
    or string.find(lower, "manifest hash", 1, true)
    or string.find(lower, "manifest size", 1, true)
    or string.find(lower, "manifest commit", 1, true)
    or string.find(lower, "manifest integrity", 1, true)
    or string.find(lower, "size mismatch in staging", 1, true)
    or string.find(lower, "unsupported hash algorithm", 1, true)
  then
    setIntegrityStatus(INTEGRITY_STATUS.STAGING_INVALID, raw, true)
  end
end

local shortCommit = UpdateFormat.shortCommit

local function writeTextFile(path, text)
  local fh = fs.open(path, "w")
  if not fh then
    return false, "cannot write file: " .. tostring(path)
  end
  fh.write(text or "")
  fh.close()
  return true
end

local function parseSizeMismatchDetail(raw)
  local path = string.match(raw, "size mismatch for ([^:]+)")
  local expected = string.match(raw, "expected=([0-9]+)")
  local received = string.match(raw, "received=([0-9]+)")
  local url = string.match(raw, "url=(%S+)")
  return path, expected, received, url
end

local function parseHashMismatchDetail(raw)
  local path = string.match(raw, "hash mismatch[^%w]+for ([^:]+)")
  local expected = string.match(raw, "expected=([0-9a-fA-F]+)")
  local received = string.match(raw, "received=([0-9a-fA-F]+)")
  local algo = string.match(raw, "algo=([%w_%-]+)")
  return path, expected, received, algo
end

local function formatUpdateUserError(step, err)
  local raw = firstLine(err or "unknown error")
  local lower = string.lower(raw)

  if string.find(lower, "http disabled", 1, true) then
    return step .. ": HTTP disabled. Enable HTTP in ComputerCraft config."
  end
  if string.find(lower, "http 404", 1, true) then
    return step .. ": remote file not found (404). Check owner/repo/branch/manifestPath."
  end
  if string.find(lower, "url malformed", 1, true) then
    return step .. ": invalid download URL (path/source issue)."
  end
  if string.find(lower, "source incomplete", 1, true) then
    return step .. ": update source is incomplete (owner/repo/branch/commit)."
  end
  if string.find(lower, "manifest commit missing or invalid", 1, true) then
    return step .. ": manifest commit missing/invalid (expected 40-hex sha)."
  end
  if string.find(lower, "requires pinned commit", 1, true) then
    return step .. ": download source must support commit pinning ({commit} or {ref})."
  end
  if string.find(lower, "staging", 1, true) then
    return step .. ": staging is invalid or incomplete. Run DOWNLOAD again."
  end
  if string.find(lower, "hash validation required before apply", 1, true) then
    return step .. ": hash validation not complete. Run DOWNLOAD and wait for VALIDATING."
  end
  if string.find(lower, "hash mismatch", 1, true) then
    local path, expected, received, algo = parseHashMismatchDetail(raw)
    if path and expected and received then
      return step .. ": hash check failed on " .. tostring(path)
        .. " (" .. tostring(algo or "sha256") .. ", expected " .. tostring(expected) .. ", got " .. tostring(received) .. ")."
    end
    return step .. ": hash check failed."
  end
  if string.find(lower, "unsupported hash algorithm", 1, true) then
    return step .. ": unsupported hash algorithm in manifest/source."
  end
  if string.find(lower, "hash compute failed", 1, true) then
    return step .. ": unable to compute local file hash."
  end
  if string.find(lower, "size mismatch", 1, true) then
    local path, expected, received = parseSizeMismatchDetail(raw)
    if path and expected and received then
      return step .. ": integrity mismatch on " .. tostring(path)
        .. " (expected " .. tostring(expected) .. " bytes, got " .. tostring(received) .. ")."
    end
    return step .. ": file integrity check failed (size mismatch)."
  end
  if string.find(lower, "manifest", 1, true) then
    return step .. ": manifest issue: " .. raw
  end

  return step .. ": " .. raw
end

local function failUpdateStep(step, status, err)
  local userMessage = formatUpdateUserError(step, err)
  state.update.lastError = userMessage
  state.update.lastCheckSummary = string.lower(step) .. " failed"
  state.update.hashValidated = false
  setIntegrityFromError(err)
  if step == "DOWNLOAD" then
    setDownloadProgress({
      phase = UPDATE_STATUS.DOWNLOAD_FAILED,
      note = userMessage,
    })
    resetValidationProgress(UPDATE_STATUS.IDLE, "download failed")
  elseif step == "VALIDATION" then
    setValidationProgress({
      phase = UPDATE_STATUS.VALIDATION_FAILED,
      note = userMessage,
    })
  end
  setUpdateStatus(status, userMessage, false)
  appendUpdateLogLine(step .. " failed (raw): " .. tostring(firstLine(err)))
  appendUpdateLogLine(step .. " failed (ui): " .. tostring(userMessage))
  return false, userMessage
end

local function clearStagingWithLog(reason)
  local ok, err = UpdateApply.clearPath(UPDATE_TEMP_DIR)
  if ok then
    appendUpdateLogLine("STAGING cleared (" .. tostring(reason or "cleanup") .. ")")
    return true
  end

  appendUpdateLogLine("STAGING cleanup failed (" .. tostring(reason or "cleanup") .. "): " .. tostring(err))
  return false, err
end

local function buildUpdateSource(remoteManifest)
  local source = {
    owner = tostring(UPDATE_CFG.owner or ""),
    repo = tostring(UPDATE_CFG.repo or ""),
    branch = tostring(UPDATE_CFG.branch or "main"),
    commit = "",
    rawBaseUrl = tostring(UPDATE_CFG.rawBaseUrl or ""),
    defaultHashAlgo = "sha256",
  }

  if type(remoteManifest) == "table" then
    local resolvedCommit = UpdateManifest.resolveCommit(remoteManifest)
    if type(resolvedCommit) == "string" and resolvedCommit ~= "" then
      source.commit = resolvedCommit
    end
  end

  if type(remoteManifest) == "table" and type(remoteManifest.source) == "table" then
    if source.rawBaseUrl == "" and type(remoteManifest.source.rawBaseUrl) == "string" and remoteManifest.source.rawBaseUrl ~= "" then
      source.rawBaseUrl = remoteManifest.source.rawBaseUrl
    end
    if source.owner == "" and type(remoteManifest.source.owner) == "string" then
      source.owner = remoteManifest.source.owner
    end
    if source.repo == "" and type(remoteManifest.source.repo) == "string" then
      source.repo = remoteManifest.source.repo
    end
    if source.branch == "" and type(remoteManifest.source.branch) == "string" then
      source.branch = remoteManifest.source.branch
    end
    if source.commit == "" and type(remoteManifest.source.commit) == "string" and remoteManifest.source.commit ~= "" then
      source.commit = remoteManifest.source.commit
    end
  end

  if type(remoteManifest) == "table" and type(remoteManifest.integrity) == "table" and type(remoteManifest.integrity.defaultHashAlgo) == "string" and remoteManifest.integrity.defaultHashAlgo ~= "" then
    source.defaultHashAlgo = string.lower(remoteManifest.integrity.defaultHashAlgo)
  end

  return source
end

local function resolveManifestPath(remoteManifest)
  if type(UPDATE_CFG.manifestPath) == "string" and UPDATE_CFG.manifestPath ~= "" then
    return UPDATE_CFG.manifestPath
  end

  if type(remoteManifest) == "table" and type(remoteManifest.source) == "table" and type(remoteManifest.source.manifestPath) == "string" and remoteManifest.source.manifestPath ~= "" then
    return remoteManifest.source.manifestPath
  end

  return UPDATE_MANIFEST_FILE
end

local function rawBaseSupportsPinnedRef(rawBaseUrl)
  if type(rawBaseUrl) ~= "string" or rawBaseUrl == "" then
    return false
  end
  return string.find(rawBaseUrl, "{commit}", 1, true) ~= nil or string.find(rawBaseUrl, "{ref}", 1, true) ~= nil
end

local function validateUpdateSource(source, requireCommit)
  requireCommit = requireCommit == true

  if type(source.rawBaseUrl) == "string" and source.rawBaseUrl ~= "" then
    if requireCommit and not rawBaseSupportsPinnedRef(source.rawBaseUrl) then
      return false, "download source requires pinned commit in rawBaseUrl ({commit} or {ref})"
    end
    if requireCommit and not UpdateManifest.isValidCommit(source.commit) then
      return false, "manifest commit missing or invalid (expected 40-hex sha)"
    end
    return true
  end

  if source.owner == "" or source.repo == "" then
    return false, "update source incomplete (owner/repo)"
  end

  if requireCommit then
    if not UpdateManifest.isValidCommit(source.commit) then
      return false, "manifest commit missing or invalid (expected 40-hex sha)"
    end
    return true
  end

  if source.branch == "" then
    return false, "update source incomplete (branch)"
  end

  return true
end

local function refreshLocalUpdateSnapshot()
  local localVersion, versionErr = UpdateVersion.readLocalVersion(UPDATE_VERSION_FILE)
  if localVersion then
    state.update.localVersion = localVersion
  else
    state.update.localVersion = "n/a"
    state.update.lastError = firstLine(versionErr or "version read failed")
  end

  local localManifest, manifestErr = UpdateManifest.readLocal(UPDATE_MANIFEST_FILE)
  if localManifest then
    state.update.localManifest = localManifest
    state.update.channel = tostring(localManifest.channel or UPDATE_CFG.channel)
  else
    state.update.localManifest = nil
    state.update.lastError = firstLine(manifestErr or "manifest read failed")
  end

  local backupMeta = UpdateApply.loadBackupMeta(UPDATE_BACKUP_DIR)
  state.update.canRollback = backupMeta ~= nil
end

local function performUpdateCheck(reason)
  local integrityMode = normalizeIntegrityMode(UPDATE_CFG.integrityMode)
  local hashValidationRequired = integrityMode ~= "size-only"

  state.update.applyConfirmArmed = false
  state.update.lastCheck = nowText()
  state.update.integrityMode = integrityMode
  state.update.hashValidationRequired = hashValidationRequired
  setDownloadedState(false, 0)
  state.update.hashValidated = not hashValidationRequired
  resetDownloadProgress(UPDATE_STATUS.IDLE, "check reset")
  resetValidationProgress(UPDATE_STATUS.IDLE, hashValidationRequired and "hash validation pending" or "size-only mode")
  setIntegrityStatus(INTEGRITY_STATUS.PENDING, "manifest validation pending", false)
  state.update.remoteCommit = "n/a"
  state.update.remoteBranch = tostring(UPDATE_CFG.branch or "main")
  state.update.manifestUrl = "n/a"
  state.update.remoteManifestText = nil
  setUpdateStatus(UPDATE_STATUS.CHECKING, "fetching remote manifest", true)
  appendUpdateLogLine("CHECK start: reason=" .. tostring(reason or "manual"))
  appendUpdateLogLine("CHECK configured branch: " .. tostring(UPDATE_CFG.branch or "main"))
  refreshLocalUpdateSnapshot()

  if not UpdateClient.isHttpEnabled() then
    return failUpdateStep("CHECK", UPDATE_STATUS.CHECK_FAILED, "http disabled in ComputerCraft")
  end

  local source = buildUpdateSource(nil)
  state.update.remoteBranch = tostring(source.branch ~= "" and source.branch or UPDATE_CFG.branch or "main")
  local sourceOk, sourceErr = validateUpdateSource(source, false)
  if not sourceOk then
    return failUpdateStep("CHECK", UPDATE_STATUS.CHECK_FAILED, sourceErr)
  end

  local manifestPath = resolveManifestPath(nil)
  local manifestUrl = UpdateClient.buildRawUrl(source, manifestPath)
  state.update.manifestUrl = manifestUrl
  appendUpdateLogLine("CHECK manifest url: " .. tostring(manifestUrl))
  local remoteManifest, remoteManifestTextOrErr = UpdateManifest.readRemote(UpdateClient, manifestUrl)
  if not remoteManifest then
    return failUpdateStep("CHECK", UPDATE_STATUS.CHECK_FAILED, remoteManifestTextOrErr)
  end
  local remoteManifestText = remoteManifestTextOrErr

  local remoteSource = buildUpdateSource(remoteManifest)
  local remoteSourceOk, remoteSourceErr = validateUpdateSource(remoteSource, false)
  if not remoteSourceOk then
    return failUpdateStep("CHECK", UPDATE_STATUS.CHECK_FAILED, remoteSourceErr)
  end

  local manifestReady, manifestCommitOrErr = UpdateManifest.validateDownloadManifest(remoteManifest, {
    integrityMode = integrityMode,
  })
  if manifestReady then
    remoteSource.commit = manifestCommitOrErr
    state.update.remoteCommit = manifestCommitOrErr
  else
    state.update.remoteCommit = "n/a"
    appendUpdateLogLine("CHECK warning: " .. tostring(manifestCommitOrErr))
  end

  state.update.remoteManifest = remoteManifest
  state.update.remoteManifestText = type(remoteManifestText) == "string" and remoteManifestText or nil
  state.update.remoteSource = remoteSource
  state.update.remoteVersion = tostring(remoteManifest.version or "n/a")
  state.update.channel = tostring(remoteManifest.channel or UPDATE_CFG.channel)
  state.update.remoteBranch = tostring(remoteSource.branch ~= "" and remoteSource.branch or state.update.remoteBranch)
  appendUpdateLogLine("CHECK mode: manifest via branch, files pinned by commit")
  appendUpdateLogLine("CHECK session branch=" .. tostring(state.update.remoteBranch) .. ", commit=" .. tostring(state.update.remoteCommit))
  appendUpdateLogLine("CHECK integrity mode: config=" .. tostring(integrityMode)
    .. ", manifest=" .. tostring(remoteManifest.integrity and remoteManifest.integrity.mode or "hash+size"))
  state.update.pendingFiles = UpdateManifest.computePendingFiles(state.update.localManifest, remoteManifest)
  state.update.filesToUpdate = #state.update.pendingFiles
  setDownloadProgress({
    phase = state.update.filesToUpdate > 0 and UPDATE_STATUS.UPDATE_AVAILABLE or UPDATE_STATUS.UP_TO_DATE,
    totalFiles = state.update.filesToUpdate,
    completedFiles = 0,
    totalBytesExpected = sumManifestEntrySizes(state.update.pendingFiles),
    totalBytesCompleted = 0,
    currentFile = "-",
    currentFileSize = 0,
    note = state.update.filesToUpdate > 0 and "update files pending download" or "no pending files",
  })
  setValidationProgress({
    phase = state.update.filesToUpdate > 0 and UPDATE_STATUS.IDLE or UPDATE_STATUS.UP_TO_DATE,
    totalFiles = state.update.filesToUpdate,
    completedFiles = 0,
    totalBytesExpected = sumManifestEntrySizes(state.update.pendingFiles),
    totalBytesCompleted = 0,
    currentFile = "-",
    currentFileSize = 0,
    note = hashValidationRequired and (state.update.filesToUpdate > 0 and "waiting for hash validation" or "nothing to validate")
      or "size-only mode (hash skipped)",
  })
  state.update.lastError = manifestReady and "none" or formatUpdateUserError("CHECK", manifestCommitOrErr)
  setDownloadedState(false, 0)
  state.update.hashValidated = (not hashValidationRequired) or state.update.filesToUpdate == 0
  if manifestReady then
    if state.update.filesToUpdate > 0 then
      setIntegrityStatus(INTEGRITY_STATUS.PENDING, hashValidationRequired and "manifest valid; download + hash validation pending" or "manifest valid; size-only validation pending", true)
    else
      setIntegrityStatus(INTEGRITY_STATUS.OK, hashValidationRequired and "manifest hash/size valid (up to date)" or "manifest size valid (size-only mode, up to date)", true)
    end
  else
    setIntegrityStatus(INTEGRITY_STATUS.STAGING_INVALID, firstLine(manifestCommitOrErr), true)
  end

  local newer, cmpErr = UpdateVersion.isRemoteNewer(state.update.localVersion, state.update.remoteVersion)
  local status = UPDATE_STATUS.UP_TO_DATE
  if newer == nil then
    if state.update.filesToUpdate > 0 then
      status = UPDATE_STATUS.UPDATE_AVAILABLE
    else
      status = UPDATE_STATUS.UP_TO_DATE
    end
    if cmpErr then
      appendUpdateLogLine("CHECK warning: " .. tostring(cmpErr))
    end
  elseif newer or state.update.filesToUpdate > 0 then
    status = UPDATE_STATUS.UPDATE_AVAILABLE
  else
    status = UPDATE_STATUS.UP_TO_DATE
  end

  if status == UPDATE_STATUS.UPDATE_AVAILABLE and not manifestReady then
    state.update.lastCheckSummary = "update available (download blocked)"
  else
    state.update.lastCheckSummary = status == UPDATE_STATUS.UPDATE_AVAILABLE and "update available" or "up to date"
  end

  local detail = "local=" .. tostring(state.update.localVersion)
    .. " remote=" .. tostring(state.update.remoteVersion)
    .. " pending=" .. tostring(state.update.filesToUpdate)
    .. " commit=" .. tostring(shortCommit(state.update.remoteCommit, 8))
  if not manifestReady then
    detail = detail .. " (download blocked)"
  end

  setUpdateStatus(status, detail, true)
  appendUpdateLogLine("CHECK done: local=" .. tostring(state.update.localVersion) .. ", remote=" .. tostring(state.update.remoteVersion) .. ", files=" .. tostring(state.update.filesToUpdate) .. ", commit=" .. tostring(state.update.remoteCommit))
  return true, state.update.lastCheckSummary
end

local function handleValidationProgressEvent(event)
  if type(event) ~= "table" then
    return
  end

  local totalFilesEvent = type(event.totalFiles) == "number" and event.totalFiles or state.update.validationProgress.totalFiles
  local completedFilesEvent = type(event.completedFiles) == "number" and event.completedFiles or state.update.validationProgress.completedFiles
  local totalBytesExpectedEvent = type(event.totalBytesExpected) == "number" and event.totalBytesExpected or state.update.validationProgress.totalBytesExpected
  local totalBytesCompletedEvent = type(event.totalBytesCompleted) == "number" and event.totalBytesCompleted or state.update.validationProgress.totalBytesCompleted
  local currentPath = type(event.path) == "string" and event.path ~= "" and event.path or state.update.validationProgress.currentFile
  local currentFileSize = 0
  if type(event.expectedSize) == "number" then
    currentFileSize = math.max(0, math.floor(event.expectedSize))
  elseif type(event.receivedSize) == "number" then
    currentFileSize = math.max(0, math.floor(event.receivedSize))
  else
    currentFileSize = state.update.validationProgress.currentFileSize or 0
  end

  setValidationProgress({
    phase = UPDATE_STATUS.VALIDATING,
    totalFiles = totalFilesEvent,
    completedFiles = completedFilesEvent,
    totalBytesExpected = totalBytesExpectedEvent,
    totalBytesCompleted = totalBytesCompletedEvent,
    currentFile = currentPath,
    currentFileSize = currentFileSize,
    note = type(event.event) == "string" and event.event or state.update.validationProgress.note,
  })

  local percent = math.floor((state.update.validationProgress.percent or 0) + 0.5)
  local progressSummary = tostring(state.update.validationProgress.completedFiles or 0) .. "/" .. tostring(state.update.validationProgress.totalFiles or 0)
    .. " files, " .. tostring(state.update.validationProgress.totalBytesCompleted or 0) .. "/" .. tostring(state.update.validationProgress.totalBytesExpected or 0)
    .. " bytes (" .. tostring(percent) .. "%)"

  if event.event == "file_start" then
    setUpdateStatus(UPDATE_STATUS.VALIDATING, "validating hash " .. tostring(currentPath), false)
    appendUpdateLogLine("VALIDATION file start: " .. tostring(currentPath) .. " expected=" .. tostring(currentFileSize) .. "B")
  elseif event.event == "file_done" then
    setUpdateStatus(UPDATE_STATUS.VALIDATING, "validated " .. tostring(progressSummary), false)
    appendUpdateLogLine("VALIDATION progress: " .. tostring(progressSummary))
  elseif event.event == "complete" then
    appendUpdateLogLine("VALIDATION transfer complete: " .. tostring(progressSummary))
  end
end

local function handleDownloadProgressEvent(event)
  if type(event) ~= "table" then
    return
  end

  local phase = type(event.phase) == "string" and event.phase ~= "" and event.phase or UPDATE_STATUS.DOWNLOADING
  local totalFilesEvent = type(event.totalFiles) == "number" and event.totalFiles or state.update.downloadProgress.totalFiles
  local completedFilesEvent = type(event.completedFiles) == "number" and event.completedFiles or state.update.downloadProgress.completedFiles
  local totalBytesExpectedEvent = type(event.totalBytesExpected) == "number" and event.totalBytesExpected or state.update.downloadProgress.totalBytesExpected
  local totalBytesCompletedEvent = type(event.totalBytesCompleted) == "number" and event.totalBytesCompleted or state.update.downloadProgress.totalBytesCompleted
  local currentPath = type(event.path) == "string" and event.path ~= "" and event.path or state.update.downloadProgress.currentFile
  local currentFileSize = 0
  if type(event.expectedSize) == "number" then
    currentFileSize = math.max(0, math.floor(event.expectedSize))
  elseif type(event.receivedSize) == "number" then
    currentFileSize = math.max(0, math.floor(event.receivedSize))
  else
    currentFileSize = state.update.downloadProgress.currentFileSize or 0
  end

  setDownloadProgress({
    phase = phase,
    totalFiles = totalFilesEvent,
    completedFiles = completedFilesEvent,
    totalBytesExpected = totalBytesExpectedEvent,
    totalBytesCompleted = totalBytesCompletedEvent,
    currentFile = currentPath,
    currentFileSize = currentFileSize,
    note = type(event.event) == "string" and event.event or state.update.downloadProgress.note,
  })

  local percent = math.floor((state.update.downloadProgress.percent or 0) + 0.5)
  local progressSummary = tostring(state.update.downloadProgress.completedFiles or 0) .. "/" .. tostring(state.update.downloadProgress.totalFiles or 0)
    .. " files, " .. tostring(state.update.downloadProgress.totalBytesCompleted or 0) .. "/" .. tostring(state.update.downloadProgress.totalBytesExpected or 0)
    .. " bytes (" .. tostring(percent) .. "%)"

  if event.event == "file_start" then
    setUpdateStatus(UPDATE_STATUS.DOWNLOADING, "downloading " .. tostring(currentPath) .. " (" .. progressSummary .. ")", false)
    appendUpdateLogLine("DOWNLOAD file start: " .. tostring(currentPath) .. " expected=" .. tostring(currentFileSize) .. "B url=" .. tostring(event.url or "n/a"))
  elseif event.event == "file_done" then
    setUpdateStatus(UPDATE_STATUS.DOWNLOADING, "downloaded " .. tostring(progressSummary), false)
    appendUpdateLogLine("DOWNLOAD progress: " .. tostring(progressSummary))
  elseif event.event == "complete" then
    setUpdateStatus(UPDATE_STATUS.DOWNLOADING, "download transfer complete", false)
    setDownloadProgress({
      phase = UPDATE_STATUS.DOWNLOADING,
      note = "download transfer complete",
    })
    appendUpdateLogLine("DOWNLOAD transfer complete: " .. tostring(progressSummary))
  end
end

local function performUpdateDownload()
  local integrityMode = normalizeIntegrityMode(state.update.integrityMode or UPDATE_CFG.integrityMode)
  local hashValidationRequired = integrityMode ~= "size-only"

  state.update.integrityMode = integrityMode
  state.update.hashValidationRequired = hashValidationRequired
  state.update.applyConfirmArmed = false
  setDownloadedState(false, 0)
  setIntegrityStatus(INTEGRITY_STATUS.PENDING, hashValidationRequired and "download + hash validation in progress" or "download in progress (size-only mode)", true)
  setUpdateStatus(UPDATE_STATUS.DOWNLOADING, "preparing staging directory", true)
  resetDownloadProgress(UPDATE_STATUS.DOWNLOADING, "preparing staging directory")
  resetValidationProgress(UPDATE_STATUS.IDLE, hashValidationRequired and "waiting for download completion" or "size-only mode")
  appendUpdateLogLine("DOWNLOAD start")

  if not state.update.remoteManifest then
    local ok, err = performUpdateCheck("download precheck")
    if not ok then
      return false, err
    end
  end

  local remoteManifest = state.update.remoteManifest
  local manifestReady, manifestCommitOrErr = UpdateManifest.validateDownloadManifest(remoteManifest, {
    integrityMode = integrityMode,
  })
  if not manifestReady then
    clearStagingWithLog("manifest invalid for download")
    setDownloadedState(false, 0)
    return failUpdateStep("DOWNLOAD", UPDATE_STATUS.DOWNLOAD_FAILED, manifestCommitOrErr)
  end

  local manifestCommit = manifestCommitOrErr
  state.update.remoteCommit = manifestCommit
  local remoteSource = state.update.remoteSource or buildUpdateSource(remoteManifest)
  remoteSource.commit = manifestCommit
  state.update.remoteSource = remoteSource
  state.update.remoteBranch = tostring(remoteSource.branch ~= "" and remoteSource.branch or UPDATE_CFG.branch or "main")
  appendUpdateLogLine("DOWNLOAD mode: manifest branch=" .. tostring(state.update.remoteBranch) .. ", files commit=" .. tostring(manifestCommit))
  appendUpdateLogLine("DOWNLOAD integrity mode: " .. tostring(integrityMode))

  local sourceOk, sourceErr = validateUpdateSource(remoteSource, true)
  if not sourceOk then
    clearStagingWithLog("source invalid")
    setDownloadedState(false, 0)
    return failUpdateStep("DOWNLOAD", UPDATE_STATUS.DOWNLOAD_FAILED, sourceErr)
  end

  local clearOk, clearErr = clearStagingWithLog("before download")
  if not clearOk then
    setDownloadedState(false, 0)
    return failUpdateStep("DOWNLOAD", UPDATE_STATUS.DOWNLOAD_FAILED, clearErr)
  end

  fs.makeDir(UPDATE_TEMP_DIR)
  local plannedFiles = remoteManifest.files or {}
  local totalFiles = #plannedFiles
  local totalExpectedBytes = sumManifestEntrySizes(plannedFiles)
  setDownloadProgress({
    phase = UPDATE_STATUS.DOWNLOADING,
    totalFiles = totalFiles,
    completedFiles = 0,
    totalBytesExpected = totalExpectedBytes,
    totalBytesCompleted = 0,
    currentFile = "-",
    currentFileSize = 0,
    note = "download started",
  })
  appendUpdateLogLine("DOWNLOAD files planned: " .. tostring(totalFiles))
  appendUpdateLogLine("DOWNLOAD expected bytes: " .. tostring(totalExpectedBytes))

  local downloaded, downloadErr = UpdateClient.downloadFiles(remoteSource, plannedFiles, UPDATE_TEMP_DIR, appendUpdateLogLine, handleDownloadProgressEvent)
  if not downloaded then
    clearStagingWithLog("download failure")
    setDownloadedState(false, 0)
    return failUpdateStep("DOWNLOAD", UPDATE_STATUS.DOWNLOAD_FAILED, downloadErr)
  end

  if hashValidationRequired then
    setUpdateStatus(UPDATE_STATUS.VALIDATING, "hash validation in progress", true)
    resetValidationProgress(UPDATE_STATUS.VALIDATING, "hash validation started")
    setValidationProgress({
      phase = UPDATE_STATUS.VALIDATING,
      totalFiles = totalFiles,
      completedFiles = 0,
      totalBytesExpected = totalExpectedBytes,
      totalBytesCompleted = 0,
      currentFile = "-",
      currentFileSize = 0,
      note = "hash validation started",
    })
    appendUpdateLogLine("VALIDATION start: files=" .. tostring(totalFiles) .. ", expectedBytes=" .. tostring(totalExpectedBytes))

    local validated, validationErr = UpdateClient.validateDownloadedHashes(remoteSource, plannedFiles, UPDATE_TEMP_DIR, appendUpdateLogLine, handleValidationProgressEvent)
    if not validated then
      clearStagingWithLog("hash validation failure")
      setDownloadedState(false, 0)
      return failUpdateStep("VALIDATION", UPDATE_STATUS.VALIDATION_FAILED, validationErr)
    end

    state.update.hashValidated = true
    setValidationProgress({
      phase = UPDATE_STATUS.READY_TO_APPLY,
      completedFiles = totalFiles,
      totalFiles = totalFiles,
      totalBytesCompleted = totalExpectedBytes,
      totalBytesExpected = totalExpectedBytes,
      currentFile = "-",
      currentFileSize = 0,
      note = "hash validation complete",
    })
    appendUpdateLogLine("VALIDATION done: files=" .. tostring(totalFiles))
  else
    state.update.hashValidated = true
    setValidationProgress({
      phase = UPDATE_STATUS.READY_TO_APPLY,
      totalFiles = totalFiles,
      completedFiles = totalFiles,
      totalBytesExpected = totalExpectedBytes,
      totalBytesCompleted = totalExpectedBytes,
      currentFile = "-",
      currentFileSize = 0,
      note = "size-only mode: hash validation skipped",
    })
    appendUpdateLogLine("VALIDATION skipped: size-only mode enabled")
  end

  setUpdateStatus(UPDATE_STATUS.VALIDATING, "finalizing staging metadata", true)
  setDownloadProgress({
    phase = UPDATE_STATUS.DOWNLOADING,
    note = "download complete, staging finalize",
  })

  local stagingContext = {
    remoteVersion = tostring(state.update.remoteVersion or "n/a"),
    manifestVersion = tostring(remoteManifest.version or "n/a"),
    remoteCommit = tostring(manifestCommit or ""),
    channel = tostring(state.update.channel or "stable"),
    checkedAt = tostring(state.update.lastCheck or "never"),
    integrityMode = integrityMode,
  }

  local marked, markedErr = UpdateApply.markStagingReady(remoteManifest.files, UPDATE_TEMP_DIR, stagingContext)
  if not marked then
    clearStagingWithLog("staging meta failure")
    setDownloadedState(false, 0)
    return failUpdateStep("DOWNLOAD", UPDATE_STATUS.DOWNLOAD_FAILED, markedErr)
  end

  local valid, validErr = UpdateApply.validateStaging(remoteManifest.files, UPDATE_TEMP_DIR, stagingContext, appendUpdateLogLine, "download staging validation", {
    skipHash = true,
  })
  if not valid then
    clearStagingWithLog("staging validation failure")
    setDownloadedState(false, 0)
    return failUpdateStep("DOWNLOAD", UPDATE_STATUS.DOWNLOAD_FAILED, validErr)
  end

  if hashValidationRequired then
    setIntegrityStatus(INTEGRITY_STATUS.OK, "download + hash validation complete for commit " .. tostring(shortCommit(manifestCommit, 8)), true)
  else
    setIntegrityStatus(INTEGRITY_STATUS.OK, "download size validation complete (size-only mode) for commit " .. tostring(shortCommit(manifestCommit, 8)), true)
  end
  setDownloadedState(true, #downloaded)
  setDownloadProgress({
    phase = UPDATE_STATUS.READY_TO_APPLY,
    completedFiles = #downloaded,
    totalFiles = totalFiles,
    totalBytesCompleted = state.update.downloadProgress.totalBytesExpected,
    currentFile = "-",
    currentFileSize = 0,
    note = "ready to apply",
  })
  setValidationProgress({
    phase = UPDATE_STATUS.READY_TO_APPLY,
    currentFile = "-",
    currentFileSize = 0,
    note = hashValidationRequired and "ready to apply (hash validated)" or "ready to apply (size-only mode)",
  })
  state.update.lastDownload = nowText()
  state.update.lastError = "none"
  state.update.lastCheckSummary = "ready to apply"
  setUpdateStatus(UPDATE_STATUS.READY_TO_APPLY, "downloaded files=" .. tostring(#downloaded) .. " commit=" .. tostring(shortCommit(manifestCommit, 8)) .. " mode=" .. tostring(integrityMode), true)
  appendUpdateLogLine("DOWNLOAD done: files=" .. tostring(#downloaded) .. ", commit=" .. tostring(manifestCommit) .. ", mode=" .. tostring(integrityMode))

  return true, "ready to apply (" .. tostring(#downloaded) .. " files)"
end

local function performUpdateApply()
  if UPDATE_CFG.requireConfirmApply and not state.update.applyConfirmArmed then
    state.update.applyConfirmArmed = true
    setUpdateStatus(UPDATE_STATUS.READY_TO_APPLY, "confirmation required before apply", true)
    appendUpdateLogLine("APPLY waiting confirmation")
    return false, "confirmation required: press APPLY again"
  end

  state.update.applyConfirmArmed = false
  setIntegrityStatus(INTEGRITY_STATUS.PENDING, "pre-apply integrity validation in progress", true)
  setUpdateStatus(UPDATE_STATUS.APPLYING, "validating staging and applying update", true)
  appendUpdateLogLine("APPLY start")

  local remoteManifest = state.update.remoteManifest
  if not remoteManifest then
    return failUpdateStep("APPLY", UPDATE_STATUS.APPLY_FAILED, "check required before apply")
  end

  if not state.update.downloaded then
    return failUpdateStep("APPLY", UPDATE_STATUS.APPLY_FAILED, "download required before apply")
  end

  local integrityMode = normalizeIntegrityMode(state.update.integrityMode or UPDATE_CFG.integrityMode)
  local hashValidationRequired = state.update.hashValidationRequired ~= false and integrityMode ~= "size-only"
  if hashValidationRequired and state.update.hashValidated ~= true then
    return failUpdateStep("APPLY", UPDATE_STATUS.APPLY_FAILED, "hash validation required before apply")
  end

  local expectedContext = {
    remoteVersion = tostring(state.update.remoteVersion or "n/a"),
    manifestVersion = tostring(remoteManifest.version or "n/a"),
    remoteCommit = tostring(state.update.remoteCommit or ""),
    integrityMode = integrityMode,
  }

  local stageOk, stageErr = UpdateApply.validateStaging(remoteManifest.files, UPDATE_TEMP_DIR, expectedContext, appendUpdateLogLine, "pre-apply validation", {
    skipHash = not hashValidationRequired,
  })
  if not stageOk then
    clearStagingWithLog("apply refused invalid staging")
    setDownloadedState(false, 0)
    return failUpdateStep("APPLY", UPDATE_STATUS.APPLY_FAILED, stageErr)
  end
  if hashValidationRequired then
    setIntegrityStatus(INTEGRITY_STATUS.OK, "pre-apply staging hash+size validation OK", true)
  else
    setIntegrityStatus(INTEGRITY_STATUS.OK, "pre-apply staging size validation OK (size-only mode)", true)
  end

  local context = {
    previousVersion = state.update.localVersion,
    previousManifestVersion = state.update.localManifest and state.update.localManifest.version or "n/a",
  }

  local backupOk, backupErr = UpdateApply.createBackup(remoteManifest.files, UPDATE_BACKUP_DIR, context, appendUpdateLogLine)
  if not backupOk then
    setDownloadedState(false, 0)
    return failUpdateStep("APPLY", UPDATE_STATUS.APPLY_FAILED, backupErr)
  end

  local applied, applyErr = UpdateApply.applyFromStaging(remoteManifest.files, UPDATE_TEMP_DIR, appendUpdateLogLine, {
    skipHash = not hashValidationRequired,
  })
  if not applied then
    setIntegrityFromError(applyErr)
    setUpdateStatus(UPDATE_STATUS.APPLY_FAILED, "apply failed, rollback attempt started", true)
    local rolledBack, rollbackErr = UpdateApply.rollback(UPDATE_BACKUP_DIR, appendUpdateLogLine)
    if rolledBack then
      clearStagingWithLog("after automatic rollback")
      setDownloadedState(false, 0)
      state.update.lastApply = nowText() .. " (auto rollback)"
      state.update.lastError = formatUpdateUserError("APPLY", applyErr)
      state.update.lastCheckSummary = "rollback done after apply failure"
      setUpdateStatus(UPDATE_STATUS.ROLLBACK_DONE, "automatic rollback completed", true)
      appendUpdateLogLine("APPLY failed -> automatic rollback done: " .. tostring(firstLine(applyErr)))
      refreshLocalUpdateSnapshot()
      return false, state.update.lastError .. " (automatic rollback done)"
    end

    clearStagingWithLog("after failed apply/rollback")
    setDownloadedState(false, 0)
    return failUpdateStep("APPLY", UPDATE_STATUS.APPLY_FAILED, "apply failed: " .. tostring(applyErr) .. " ; rollback failed: " .. tostring(rollbackErr))
  end

  clearStagingWithLog("after apply success")
  if type(state.update.remoteManifestText) == "string" and state.update.remoteManifestText ~= "" then
    local manifestWriteOk, manifestWriteErr = writeTextFile(UPDATE_MANIFEST_FILE, state.update.remoteManifestText)
    if manifestWriteOk then
      appendUpdateLogLine("APPLY refreshed local manifest from checked branch source")
    else
      appendUpdateLogLine("APPLY warning: manifest refresh failed: " .. tostring(manifestWriteErr))
    end
  end

  state.update.lastApply = nowText()
  setDownloadedState(false, 0)
  state.update.hashValidated = false
  resetDownloadProgress(UPDATE_STATUS.UP_TO_DATE, "no pending download")
  resetValidationProgress(UPDATE_STATUS.UP_TO_DATE, "no pending validation")
  state.update.pendingFiles = {}
  state.update.filesToUpdate = 0
  state.update.lastError = "none"
  state.update.lastCheckSummary = "up to date"
  refreshLocalUpdateSnapshot()
  setIntegrityStatus(INTEGRITY_STATUS.OK, "applied with validated staging integrity", true)
  setUpdateStatus(UPDATE_STATUS.UP_TO_DATE, "apply completed successfully", true)
  appendUpdateLogLine("APPLY success: local version=" .. tostring(state.update.localVersion) .. ", commit=" .. tostring(state.update.remoteCommit))

  return true, "apply done"
end

local function performUpdateRollback()
  state.update.applyConfirmArmed = false
  appendUpdateLogLine("ROLLBACK start")

  local rolledBack, rollbackErr = UpdateApply.rollback(UPDATE_BACKUP_DIR, appendUpdateLogLine)
  if not rolledBack then
    setDownloadedState(false, 0)
    return failUpdateStep("ROLLBACK", UPDATE_STATUS.ROLLBACK_FAILED, rollbackErr)
  end

  clearStagingWithLog("after manual rollback")
  state.update.lastApply = nowText() .. " (rollback)"
  setDownloadedState(false, 0)
  state.update.hashValidated = false
  resetDownloadProgress(UPDATE_STATUS.IDLE, "rollback done")
  resetValidationProgress(UPDATE_STATUS.IDLE, "rollback done")
  state.update.lastError = "none"
  state.update.lastCheckSummary = "rollback done"
  refreshLocalUpdateSnapshot()
  setIntegrityStatus(INTEGRITY_STATUS.PENDING, "rollback restored backup; run CHECK", true)
  setUpdateStatus(UPDATE_STATUS.ROLLBACK_DONE, "backup restored", true)
  appendUpdateLogLine("ROLLBACK success: local version=" .. tostring(state.update.localVersion))

  return true, "rollback done"
end

local function requestProgramRestart()
  local entrypoint = "start.lua"
  if state.update.localManifest and type(state.update.localManifest.entrypoint) == "string" and state.update.localManifest.entrypoint ~= "" then
    entrypoint = state.update.localManifest.entrypoint
  elseif state.update.remoteManifest and type(state.update.remoteManifest.entrypoint) == "string" and state.update.remoteManifest.entrypoint ~= "" then
    entrypoint = state.update.remoteManifest.entrypoint
  end

  state.restartTarget = entrypoint
  state.restartRequested = true
  appendUpdateLogLine("RESTART requested: " .. tostring(entrypoint))
  os.queueEvent("fusion_restart")
  return true, "restart queued: " .. tostring(entrypoint)
end

if type(logWithLevel) == "function" then
  logWithLevel("INFO", "UPDATE", "update runtime state loaded", {
    integrityMode = tostring(state and state.update and state.update.integrityMode or UPDATE_CFG.integrityMode or "size+hash"),
    hashRequired = tostring(state and state.update and state.update.hashValidationRequired ~= false),
  }, "runtime")
  logWithLevel("DEBUG", "UPDATE", "update runtime muted state", {
    muted = string.format("0x%08X", tonumber(C.muted) or 0),
  }, "runtime")
end

  return {
    loadUpdateLogTail = loadUpdateLogTail,
    updateStatusColor = updateStatusColor,
    integrityStatusColor = integrityStatusColor,
    shortIntegrityStatus = shortIntegrityStatus,
    shortCommit = shortCommit,
    refreshLocalUpdateSnapshot = refreshLocalUpdateSnapshot,
    performUpdateCheck = performUpdateCheck,
    performUpdateDownload = performUpdateDownload,
    performUpdateApply = performUpdateApply,
    performUpdateRollback = performUpdateRollback,
    requestProgramRestart = requestProgramRestart,
  }
end

return M
