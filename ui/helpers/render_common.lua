local M = {}

function M.drawToggleRows(args)
  local rect = args.rect
  local rows = args.rows or {}
  local baseY = args.baseY or 0
  local step = args.step or 0
  local drawToggleRow = args.drawToggleRow
  local maxRows = args.maxRows

  if type(maxRows) ~= "number" then
    maxRows = #rows
  end

  local rowCount = math.min(math.max(0, math.floor(maxRows)), #rows)
  for i = 1, rowCount do
    local row = rows[i]
    drawToggleRow(rect, baseY + step * (i - 1), row.label, row.value, row.color)
  end

  return rowCount
end

function M.drawLogTail(args)
  local rect = args.rect
  local lines = args.lines or {}
  local step = args.step or 0
  local logY = args.logY or rect.y
  local pad = args.pad or 0
  local maxLogLines = math.max(1, math.floor(args.maxLogLines or 1))
  local drawText = args.drawText
  local firstLine = args.firstLine
  local colorResolver = args.colorResolver
  local emptyText = args.emptyText or "no update log yet"
  local mutedColor = args.mutedColor

  local totalLines = #lines
  local startIndex = math.max(1, totalLines - maxLogLines + 1)
  local lineIndex = 0

  if totalLines == 0 then
    drawText(rect.x + pad, logY, emptyText, mutedColor, 1)
    return 0
  end

  for i = startIndex, totalLines do
    local line = lines[i]
    local low = string.lower(tostring(line or ""))
    local color = colorResolver and colorResolver(line, low) or mutedColor
    drawText(rect.x + pad, logY + step * lineIndex, firstLine(line), color, 1)
    lineIndex = lineIndex + 1
  end

  return lineIndex
end

return M
