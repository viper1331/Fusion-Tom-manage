local RenderCommon = assert(dofile("ui/helpers/render_common.lua"))

local M = {}

local function toInt(value)
  local n = tonumber(value)
  if not n then
    return 0
  end
  return math.max(0, math.floor(n))
end

local function toPercent(value)
  local n = tonumber(value)
  if not n then
    return 0
  end
  if n < 0 then
    return 0
  end
  if n > 100 then
    return 100
  end
  return n
end

local function basename(path)
  local normalized = tostring(path or "")
  normalized = string.gsub(normalized, "\\", "/")
  local name = string.match(normalized, "[^/]+$")
  if type(name) == "string" and name ~= "" then
    return name
  end
  return normalized
end

local function shorten(text, maxLen)
  local value = tostring(text or "")
  local limit = math.max(4, math.floor(maxLen or 16))
  if #value <= limit then
    return value
  end
  return string.sub(value, 1, limit - 3) .. "..."
end

local function buildDownloadProgress(updateState)
  local raw = type(updateState.downloadProgress) == "table" and updateState.downloadProgress or {}
  local totalFiles = toInt(raw.totalFiles)
  local completedFiles = toInt(raw.completedFiles)
  local totalBytesExpected = toInt(raw.totalBytesExpected)
  local totalBytesCompleted = toInt(raw.totalBytesCompleted)
  local phase = type(raw.phase) == "string" and raw.phase ~= "" and raw.phase or (updateState.remoteStatus or "IDLE")
  local currentFile = type(raw.currentFile) == "string" and raw.currentFile ~= "" and raw.currentFile or "-"
  local percent = toPercent(raw.percent)

  if percent <= 0 then
    if totalBytesExpected > 0 then
      percent = toPercent((totalBytesCompleted * 100) / totalBytesExpected)
    elseif totalFiles > 0 then
      percent = toPercent((completedFiles * 100) / totalFiles)
    end
  end

  return {
    phase = phase,
    currentFile = currentFile,
    currentFileBase = basename(currentFile),
    totalFiles = totalFiles,
    completedFiles = completedFiles,
    totalBytesExpected = totalBytesExpected,
    totalBytesCompleted = totalBytesCompleted,
    percent = percent,
    percentText = tostring(math.floor(percent + 0.5)) .. "%",
    filesText = tostring(completedFiles) .. " / " .. tostring(totalFiles) .. " fichiers",
    bytesText = tostring(totalBytesCompleted) .. " / " .. tostring(totalBytesExpected) .. " B",
  }
end

local function shortDownloadStatus(status)
  if status == "DOWNLOADING" then
    return "DL"
  end
  if status == "VALIDATING" then
    return "VAL"
  end
  if status == "READY TO APPLY" then
    return "READY"
  end
  if status == "DOWNLOAD FAILED" then
    return "FAIL"
  end
  if status == "UP TO DATE" then
    return "OK"
  end
  return shorten(status, 6)
end

local function buildStatusRows(ctx)
  local updateState = ctx.updateState
  local C = ctx.colors
  local progress = buildDownloadProgress(updateState)

  return {
    { label = "STATUS", value = updateState.remoteStatus, color = ctx.updateStatusColor(updateState.remoteStatus) },
    { label = "DL STATUS", value = progress.phase, color = ctx.updateStatusColor(progress.phase) },
    { label = "DL PROGRESS", value = progress.filesText .. " (" .. progress.percentText .. ")", color = C.cyan },
    { label = "DETAIL", value = updateState.statusDetail ~= "" and updateState.statusDetail or "-", color = C.muted },
    { label = "INTEGRITY", value = updateState.integrityStatus, color = ctx.integrityStatusColor(updateState.integrityStatus) },
    {
      label = "INTEGRITY DETAIL",
      value = updateState.integrityDetail ~= "" and updateState.integrityDetail or "-",
      color = updateState.integrityStatus == ctx.integrityStatusOk and C.muted or ctx.integrityStatusColor(updateState.integrityStatus),
    },
    { label = "LOCAL VERSION", value = updateState.localVersion, color = C.cyan },
    { label = "REMOTE VERSION", value = updateState.remoteVersion, color = C.yellow },
    { label = "CHANNEL", value = updateState.channel, color = C.text },
    { label = "BRANCH", value = updateState.remoteBranch or "-", color = C.text },
    { label = "REMOTE COMMIT", value = ctx.shortCommit(updateState.remoteCommit, 12), color = C.cyan },
    { label = "FILES TO UPDATE", value = tostring(updateState.filesToUpdate), color = updateState.filesToUpdate > 0 and C.orange or C.green },
    { label = "LAST CHECK", value = updateState.lastCheck, color = C.text },
    { label = "LAST APPLY", value = updateState.lastApply, color = C.text },
    { label = "LAST DOWNLOAD", value = updateState.lastDownload, color = C.text },
    { label = "CHECK SUMMARY", value = updateState.lastCheckSummary, color = C.muted },
    {
      label = "LAST ERROR",
      value = updateState.lastError == "none" and "-" or ctx.firstLine(updateState.lastError),
      color = updateState.lastError == "none" and C.muted or C.red,
    },
  }
end

function M.drawMicro(args)
  local r = args.rect
  local ui = args.ui
  local C = args.colors
  local updateState = args.updateState

  args.drawPanel(r.x, r.y, r.w, r.h, "MAJ")

  local infoH = math.max(64, math.floor(r.h * 0.46))
  local infoRect = { x = r.x + ui.smallPad, y = r.y + args.sv(18), w = r.w - ui.smallPad * 2, h = infoH }
  local actionsRect = {
    x = r.x + ui.smallPad,
    y = infoRect.y + infoRect.h + ui.smallPad,
    w = r.w - ui.smallPad * 2,
    h = r.h - infoH - args.sv(18) - ui.smallPad * 2,
  }
  local progress = buildDownloadProgress(updateState)

  local rowY = infoRect.y + 2
  args.drawText(infoRect.x + 1, rowY, "LV", C.text, 1)
  args.drawTextRight(infoRect.x + infoRect.w - 1, rowY, updateState.localVersion, C.cyan, 1)

  rowY = rowY + 9
  args.drawText(infoRect.x + 1, rowY, "RV", C.text, 1)
  args.drawTextRight(infoRect.x + infoRect.w - 1, rowY, updateState.remoteVersion, C.yellow, 1)

  rowY = rowY + 9
  args.drawText(infoRect.x + 1, rowY, "BR", C.text, 1)
  args.drawTextRight(infoRect.x + infoRect.w - 1, rowY, updateState.remoteBranch or "-", C.text, 1)

  rowY = rowY + 9
  args.drawText(infoRect.x + 1, rowY, "CM", C.text, 1)
  args.drawTextRight(infoRect.x + infoRect.w - 1, rowY, args.shortCommit(updateState.remoteCommit, 8), C.cyan, 1)

  rowY = rowY + 9
  args.drawText(infoRect.x + 1, rowY, "ST", C.text, 1)
  args.drawTextRight(infoRect.x + infoRect.w - 1, rowY, shortDownloadStatus(progress.phase), args.updateStatusColor(progress.phase), 1)

  rowY = rowY + 9
  args.drawText(infoRect.x + 1, rowY, "DL", C.text, 1)
  args.drawTextRight(infoRect.x + infoRect.w - 1, rowY, tostring(progress.completedFiles) .. "/" .. tostring(progress.totalFiles), C.cyan, 1)

  rowY = rowY + 9
  args.drawText(infoRect.x + 1, rowY, "%", C.text, 1)
  args.drawTextRight(infoRect.x + infoRect.w - 1, rowY, progress.percentText, C.yellow, 1)

  local pad = 1
  local gap = math.max(1, math.floor(ui.smallPad * 0.6))
  local bw = math.floor((actionsRect.w - gap) / 2)
  local bh = math.max(11, math.floor((actionsRect.h - gap * 2) / 3))
  local x1 = actionsRect.x + pad
  local x2 = x1 + bw + gap
  local y1 = actionsRect.y + pad
  local y2 = y1 + bh + gap
  local y3 = y2 + bh + gap

  args.drawButton("UPDATE_CHECK", x1, y1, bw, bh, "CHECK", "cyan", true)
  args.drawButton("UPDATE_DOWNLOAD", x2, y1, bw, bh, "DL", "purple", true)
  args.drawButton("UPDATE_APPLY", x1, y2, bw, bh, "APPLY", "green", updateState.downloaded)
  args.drawButton("UPDATE_ROLLBACK", x2, y2, bw, bh, "ROLL", "orange", updateState.canRollback)
  args.drawButton("UPDATE_RESTART", x1, y3, bw * 2 + gap, bh, "RESTART", "red", true)
end

function M.draw(args)
  local r = args.rect
  local ui = args.ui
  local C = args.colors
  local updateState = args.updateState

  local topRatio = ui.compact and 0.68 or 0.72
  local top, actions = args.splitVertical(r, topRatio)
  local statusRect, logRect

  if ui.compact then
    statusRect, logRect = args.splitVertical(top, 0.54)
  else
    statusRect, logRect = args.splitHorizontal(top, 0.52)
  end

  args.drawPanel(statusRect.x, statusRect.y, statusRect.w, statusRect.h, "MAJ STATUS")
  local step = math.max(12, args.sv(16))
  local progress = buildDownloadProgress(updateState)
  local gaugeX = statusRect.x + ui.pad
  local gaugeW = statusRect.w - ui.pad * 2
  local gaugeY = statusRect.y + args.sv(54)
  local gaugeH = math.max(ui.gaugeH, args.sv(14))
  local progressColor = progress.phase == "DOWNLOAD FAILED" and C.red or (progress.phase == "READY TO APPLY" and C.green or C.cyan)

  if type(args.drawGauge) == "function" then
    args.drawGauge(gaugeX, gaugeY, gaugeW, gaugeH, progress.percent, progressColor, "DOWNLOAD", progress.percentText)
  else
    args.drawToggleRow(statusRect, gaugeY, "DOWNLOAD", progress.filesText .. " " .. progress.percentText, progressColor)
  end

  local rowY = gaugeY + gaugeH + args.sv(8)
  local currentFileValue = ui.compact and shorten(progress.currentFileBase, 20) or shorten(progress.currentFile, 42)
  args.drawToggleRow(statusRect, rowY, "FILES", progress.filesText, C.cyan)
  rowY = rowY + step
  args.drawToggleRow(statusRect, rowY, "CURRENT FILE", currentFileValue, C.text)
  rowY = rowY + step
  args.drawToggleRow(statusRect, rowY, "DOWNLOAD STATUS", progress.phase, args.updateStatusColor(progress.phase))
  rowY = rowY + step
  if not ui.compact then
    args.drawToggleRow(statusRect, rowY, "BYTES", progress.bytesText, C.muted)
    rowY = rowY + step
  end

  local baseY = rowY + args.sv(6)
  local statusRows = buildStatusRows({
    updateState = updateState,
    colors = C,
    updateStatusColor = args.updateStatusColor,
    integrityStatusColor = args.integrityStatusColor,
    integrityStatusOk = args.integrityStatusOk,
    shortCommit = args.shortCommit,
    firstLine = args.firstLine,
  })

  local maxRows = math.max(2, math.floor((statusRect.y + statusRect.h - baseY - ui.pad) / step))
  RenderCommon.drawToggleRows({
    rect = statusRect,
    rows = statusRows,
    baseY = baseY,
    step = step,
    maxRows = maxRows,
    drawToggleRow = args.drawToggleRow,
  })

  args.drawPanel(logRect.x, logRect.y, logRect.w, logRect.h, "MAJ LOG")
  local logY = logRect.y + args.sv(54)
  local maxLogLines = math.max(3, math.floor((logRect.h - args.sv(62)) / step))

  RenderCommon.drawLogTail({
    rect = logRect,
    lines = updateState.logs,
    step = step,
    logY = logY,
    pad = ui.pad,
    maxLogLines = maxLogLines,
    drawText = args.drawText,
    firstLine = args.firstLine,
    emptyText = "no update log yet",
    mutedColor = C.muted,
    colorResolver = function(_, low)
      local hasError = string.find(low, "failed", 1, true)
        or string.find(low, "error", 1, true)
        or string.find(low, "mismatch", 1, true)
        or string.find(low, "invalid", 1, true)
      local hasWarn = string.find(low, "warning", 1, true)
      local hasHash = string.find(low, "hash ", 1, true)
      return hasError and C.red or (hasWarn and C.orange or (hasHash and C.cyan or C.text))
    end,
  })

  args.drawPanel(actions.x, actions.y, actions.w, actions.h, "MAJ ACTIONS")
  local pad = ui.pad
  local gap = ui.gap
  local usableW = actions.w - pad * 2
  local bh = math.max(ui.buttonH, args.sv(34))
  local y1 = actions.y + args.sv(54)
  local y2 = y1 + bh + args.sv(10)

  local bw3 = math.floor((usableW - gap * 2) / 3)
  local x1 = actions.x + pad
  local x2 = x1 + bw3 + gap
  local x3 = x2 + bw3 + gap

  args.drawButton("UPDATE_CHECK", x1, y1, bw3, bh, "[CHECK]", "cyan", true)
  args.drawButton("UPDATE_DOWNLOAD", x2, y1, bw3, bh, "[DOWNLOAD]", "purple", true)
  args.drawButton(
    "UPDATE_APPLY",
    x3,
    y1,
    bw3,
    bh,
    args.requireConfirmApply and (updateState.applyConfirmArmed and "[APPLY CONFIRM]" or "[APPLY]") or "[APPLY]",
    "green",
    updateState.downloaded
  )

  local bw2 = math.floor((usableW - gap) / 2)
  args.drawButton("UPDATE_ROLLBACK", x1, y2, bw2, bh, "[ROLLBACK]", "orange", updateState.canRollback)
  args.drawButton("UPDATE_RESTART", x1 + bw2 + gap, y2, bw2, bh, "[RESTART]", "red", true)
end

return M
