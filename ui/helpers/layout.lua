local M = {}

function M.classifyScreen(sw, sh)
  local width = math.floor(tonumber(sw) or 0)
  local height = math.floor(tonumber(sh) or 0)
  if width <= 0 or height <= 0 then
    return "invalid"
  end

  local minSide = math.min(width, height)
  local maxSide = math.max(width, height)

  -- Field-oriented survival tiers for very small monitor layouts.
  if minSide <= 170 and maxSide <= 280 then
    return "ultra_compact_4x4"
  end
  if minSide <= 240 and maxSide <= 360 then
    return "ultra_compact_5x4_ou_6x4"
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
  return screenClass == "ultra_compact_5x4_ou_6x4" or screenClass == "ultra_compact_4x4"
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
