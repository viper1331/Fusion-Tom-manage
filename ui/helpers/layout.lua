local M = {}

function M.classifyScreen(sw, sh)
  local width = math.floor(tonumber(sw) or 0)
  local height = math.floor(tonumber(sh) or 0)
  if width <= 0 or height <= 0 then
    return "invalid"
  end

  local minSide = math.min(width, height)
  local maxSide = math.max(width, height)

  -- Runtime labels are intentionally explicit to ease field diagnostics.
  -- 4x4 block displays are 256x256 in tm_gpu field measurements.
  if width <= 256 and height <= 256 then
    return "ultra_compact_4x4"
  end
  -- Field correction: 320x256 (and close low-compact variants) use 4x4 class.
  if (minSide <= 260 and maxSide <= 340) then
    return "ultra_compact_4x4"
  end
  if minSide <= 170 and maxSide <= 280 then
    return "ultra_compact_4x4"
  end
  if minSide <= 260 and maxSide <= 420 then
    return "ultra_compact_5x4"
  end
  if minSide <= 480 and maxSide <= 560 then
    return "compact_5x5"
  end
  if minSide <= 620 and maxSide <= 760 then
    return "compact_6x5"
  end

  if width <= 160 or height <= 340 then
    return "micro"
  end
  if width < 760 or (width / math.max(1, height)) < 0.72 then
    return "compact"
  end
  return "large"
end

function M.isUltraCompactClass(screenClass)
  return screenClass == "ultra_compact_5x4" or screenClass == "ultra_compact_4x4"
end

function M.splitVertical(r, topRatio, gap)
  local topH = math.floor((r.h - gap) * topRatio)
  return {
    x = r.x, y = r.y, w = r.w, h = topH
  }, {
    x = r.x, y = r.y + topH + gap, w = r.w, h = r.h - topH - gap
  }
end

function M.splitHorizontal(r, leftRatio, gap)
  local leftW = math.floor((r.w - gap) * leftRatio)
  return {
    x = r.x, y = r.y, w = leftW, h = r.h
  }, {
    x = r.x + leftW + gap, y = r.y, w = r.w - leftW - gap, h = r.h
  }
end

return M
