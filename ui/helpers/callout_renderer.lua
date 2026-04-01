local M = {}

local GpuSafe = assert(dofile("ui/helpers/gpu_safe.lua"))

local calloutPlacementCache = {}
local calloutLogKeys = {}

local function clampValue(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function appendRuntimeLog(args, message)
  local logger = args and args.appendUiRuntimeLog
  if type(logger) == "function" then
    logger(message)
  end
end

local function appendRuntimeLogOnce(args, stage, key, message)
  if calloutLogKeys[stage] ~= key then
    appendRuntimeLog(args, message)
    calloutLogKeys[stage] = key
  end
end

local function drawLineSafe(args, x1, y1, x2, y2, color, thickness)
  local t = math.max(1, math.floor(tonumber(thickness) or 1))
  local half = math.floor(t / 2)
  local ix1 = math.floor(tonumber(x1) or 0)
  local iy1 = math.floor(tonumber(y1) or 0)
  local ix2 = math.floor(tonumber(x2) or 0)
  local iy2 = math.floor(tonumber(y2) or 0)

  local dx = math.abs(ix2 - ix1)
  local sx = ix1 < ix2 and 1 or -1
  local dy = -math.abs(iy2 - iy1)
  local sy = iy1 < iy2 and 1 or -1
  local err = dx + dy

  while true do
    GpuSafe.filledRect(args, ix1 - half, iy1 - half, t, t, color)
    if ix1 == ix2 and iy1 == iy2 then
      break
    end
    local e2 = err * 2
    if e2 >= dy then
      err = err + dy
      ix1 = ix1 + sx
    end
    if e2 <= dx then
      err = err + dx
      iy1 = iy1 + sy
    end
  end
end

local function safeTextWidth(gpu, text, size)
  local ok, value = pcall(gpu.getTextLength, text, size, 0)
  if ok and type(value) == "number" and value > 0 then
    return math.floor(value)
  end
  return math.max(1, (#text) * (6 * math.max(1, size)))
end

local function fitTextToWidth(gpu, text, size, maxWidth)
  local raw = tostring(text or "")
  if raw == "" then
    return ""
  end

  if maxWidth <= 0 then
    return ""
  end

  if safeTextWidth(gpu, raw, size) <= maxWidth then
    return raw
  end

  local suffix = "..."
  local suffixW = safeTextWidth(gpu, suffix, size)
  if suffixW >= maxWidth then
    return ""
  end

  local trimmed = raw
  while #trimmed > 0 do
    trimmed = string.sub(trimmed, 1, #trimmed - 1)
    local candidate = trimmed .. suffix
    if safeTextWidth(gpu, candidate, size) <= maxWidth then
      return candidate
    end
  end

  return ""
end

function M.normalizeReservedRects(reservedRects)
  local normalized = {}
  if type(reservedRects) ~= "table" then
    return normalized
  end

  for _, rect in ipairs(reservedRects) do
    if type(rect) == "table" then
      local rx = math.floor(tonumber(rect.x) or 0)
      local ry = math.floor(tonumber(rect.y) or 0)
      local rw = math.floor(tonumber(rect.w) or 0)
      local rh = math.floor(tonumber(rect.h) or 0)
      if rw > 0 and rh > 0 then
        normalized[#normalized + 1] = {
          name = rect.name,
          x = rx,
          y = ry,
          w = rw,
          h = rh,
        }
      end
    end
  end

  return normalized
end

local function rectsIntersect(a, b)
  local aRight = a.x + a.w - 1
  local aBottom = a.y + a.h - 1
  local bRight = b.x + b.w - 1
  local bBottom = b.y + b.h - 1
  return a.x <= bRight and aRight >= b.x and a.y <= bBottom and aBottom >= b.y
end

function M.resetPlacementCache()
  calloutPlacementCache = {}
end

function M.drawCalloutLabel(args, spec)
  local gpu = args and args.gpu
  if not gpu then
    return
  end

  -- Contract: a valid callout always keeps anchor + segmented line + non-empty text.
  local rawText = tostring(spec.text or "")
  if rawText == "" then
    return
  end

  local size = math.max(1, math.floor(spec.size or 1))
  local viewportMinX = spec.slotX + 1
  local viewportMinY = spec.slotY + 1
  local viewportMaxX = spec.slotX + spec.slotW - 2
  local viewportMaxY = spec.slotY + spec.slotH - 2
  if viewportMaxX <= viewportMinX or viewportMaxY <= viewportMinY then
    return
  end

  local textH = math.max(1, spec.textPixelHeight and spec.textPixelHeight(size) or (8 * size))
  local annotationName = tostring(spec.name or "annotation")
  local reservedRects = M.normalizeReservedRects(spec.reservedRects)

  local anchorX = clampValue(math.floor(spec.anchorX), viewportMinX, viewportMaxX)
  local anchorY = clampValue(math.floor(spec.anchorY), viewportMinY, viewportMaxY)
  local elbowX = clampValue(math.floor(spec.elbowX), viewportMinX, viewportMaxX)
  local elbowY = clampValue(math.floor(spec.elbowY), viewportMinY, viewportMaxY)
  local side = spec.side == "left" and "left" or "right"
  local textGap = math.max(2, math.floor(spec.textGap or 3))
  local minHorizontal = math.max(5, math.floor(spec.minHorizontal or 8))
  local requestedEndLen = math.max(minHorizontal, math.floor(math.abs(spec.endLen or 20)))
  local requestedTextY = elbowY + (spec.textDy or 0)
  local textY = clampValue(math.floor(requestedTextY), viewportMinY, viewportMaxY - textH + 1)
  local endY = clampValue(elbowY, viewportMinY, viewportMaxY)

  local function computeAvailableWidth(candidateSide)
    if candidateSide == "right" then
      return viewportMaxX - (elbowX + minHorizontal + textGap) + 1
    end
    return (elbowX - minHorizontal - textGap) - viewportMinX + 1
  end

  local function placementForSide(candidateSide)
    local availableWidth = computeAvailableWidth(candidateSide)
    if availableWidth < 4 then
      return nil
    end

    local fittedText = fitTextToWidth(gpu, rawText, size, availableWidth)
    if fittedText == "" then
      return nil
    end

    local fittedTextWidth = safeTextWidth(gpu, fittedText, size)
    local textX
    local endX
    local requestedTextX

    if candidateSide == "right" then
      local minTextX = elbowX + minHorizontal + textGap
      local maxTextX = viewportMaxX - fittedTextWidth + 1
      if maxTextX < minTextX then
        return nil
      end
      requestedTextX = elbowX + requestedEndLen + textGap
      textX = clampValue(requestedTextX, minTextX, maxTextX)
      endX = textX - textGap
    else
      local minTextX = viewportMinX
      local maxTextX = math.min(viewportMaxX - fittedTextWidth + 1, elbowX - minHorizontal - textGap - fittedTextWidth + 1)
      if maxTextX < minTextX then
        return nil
      end
      requestedTextX = elbowX - requestedEndLen - textGap - fittedTextWidth + 1
      textX = clampValue(requestedTextX, minTextX, maxTextX)
      endX = textX + fittedTextWidth + textGap - 1
    end

    endX = clampValue(endX, viewportMinX, viewportMaxX)
    return {
      side = candidateSide,
      text = fittedText,
      textW = fittedTextWidth,
      textX = textX,
      endX = endX,
      requestedTextX = requestedTextX,
      availableWidth = availableWidth,
    }
  end

  local function firstReservedCollision(candidatePlacement, candidateTextY)
    if #reservedRects == 0 then
      return nil
    end
    local textRect = {
      x = candidatePlacement.textX,
      y = candidateTextY,
      w = candidatePlacement.textW,
      h = textH,
    }
    for _, rect in ipairs(reservedRects) do
      if rectsIntersect(textRect, rect) then
        return rect
      end
    end
    return nil
  end

  local function resolveTextYForPlacement(candidatePlacement)
    local baseY = textY
    if #reservedRects == 0 then
      return baseY, false, false
    end

    local collision = firstReservedCollision(candidatePlacement, baseY)
    if not collision then
      return baseY, false, false
    end

    local minY = viewportMinY
    local maxY = viewportMaxY - textH + 1
    local seen = {}
    local candidates = {}

    local function pushCandidate(value)
      local clamped = clampValue(math.floor(value), minY, maxY)
      if not seen[clamped] then
        seen[clamped] = true
        candidates[#candidates + 1] = clamped
      end
    end

    for _, rect in ipairs(reservedRects) do
      pushCandidate(rect.y - textH - 1)
      pushCandidate(rect.y + rect.h + 1)
    end
    pushCandidate(endY - textH - 2)
    pushCandidate(endY + 2)
    pushCandidate(baseY - textH - 1)
    pushCandidate(baseY + textH + 1)
    pushCandidate(minY)
    pushCandidate(maxY)

    for _, candidateY in ipairs(candidates) do
      if not firstReservedCollision(candidatePlacement, candidateY) then
        return candidateY, true, false
      end
    end

    return baseY, true, true
  end

  local function resolvePlacementForSide(candidateSide)
    local candidate = placementForSide(candidateSide)
    if not candidate then
      return nil
    end
    local resolvedY, hadCollision, unresolved = resolveTextYForPlacement(candidate)
    candidate.textY = resolvedY
    candidate.hadReservedCollision = hadCollision
    candidate.unresolvedReservedCollision = unresolved
    return candidate
  end

  local placement = resolvePlacementForSide(side)
  if not placement then
    local alternate = side == "right" and "left" or "right"
    placement = resolvePlacementForSide(alternate)
    if placement then
      appendRuntimeLogOnce(
        args,
        "annotation_side_flip_" .. annotationName,
        annotationName .. "|" .. tostring(alternate) .. "|" .. tostring(viewportMinX) .. "|" .. tostring(viewportMaxX),
        "overview annotation side fallback: name=" .. annotationName .. " side=" .. side .. "->" .. alternate
      )
    end
  elseif placement.unresolvedReservedCollision then
    local alternate = placement.side == "right" and "left" or "right"
    local alternatePlacement = resolvePlacementForSide(alternate)
    if alternatePlacement and not alternatePlacement.unresolvedReservedCollision then
      placement = alternatePlacement
      appendRuntimeLogOnce(
        args,
        "annotation_reserved_flip_" .. annotationName,
        annotationName .. "|" .. tostring(alternate) .. "|" .. tostring(viewportMinX) .. "|" .. tostring(viewportMaxX),
        "overview annotation side fallback: name=" .. annotationName .. " reason=reserved_collision side=" .. side .. "->" .. alternate
      )
    end
  end

  if not placement then
    local bestSide = side
    local rightWidth = computeAvailableWidth("right")
    local leftWidth = computeAvailableWidth("left")
    if leftWidth > rightWidth then
      bestSide = "left"
    end

    local bestWidth = math.max(1, math.max(rightWidth, leftWidth))
    local emergencyText = fitTextToWidth(gpu, rawText, size, bestWidth)
    if emergencyText == "" then
      emergencyText = "."
    end
    local emergencyW = safeTextWidth(gpu, emergencyText, size)
    local emergencyX = clampValue(elbowX + textGap + 1, viewportMinX, viewportMaxX - emergencyW + 1)
    if bestSide == "left" then
      emergencyX = clampValue(elbowX - textGap - emergencyW - 1, viewportMinX, viewportMaxX - emergencyW + 1)
    end
    local emergencyEndX = bestSide == "right"
      and clampValue(emergencyX - textGap, viewportMinX, viewportMaxX)
      or clampValue(emergencyX + emergencyW + textGap - 1, viewportMinX, viewportMaxX)

    placement = {
      side = bestSide,
      text = emergencyText,
      textW = emergencyW,
      textX = emergencyX,
      endX = emergencyEndX,
      requestedTextX = emergencyX,
      availableWidth = bestWidth,
      textY = textY,
      hadReservedCollision = false,
      unresolvedReservedCollision = false,
    }

    appendRuntimeLogOnce(
      args,
      "annotation_emergency_" .. annotationName,
      annotationName .. "|" .. tostring(bestSide) .. "|" .. tostring(bestWidth),
      "overview annotation emergency placement: name=" .. annotationName .. " side=" .. bestSide
    )
  end

  if placement.hadReservedCollision then
    local reservedKey = table.concat({
      annotationName,
      tostring(placement.side),
      tostring(placement.textX),
      tostring(placement.textY),
      tostring(placement.unresolvedReservedCollision and "blocked" or "shifted"),
    }, "|")
    appendRuntimeLogOnce(
      args,
      "annotation_reserved_" .. annotationName,
      reservedKey,
      "overview annotation reserved recalibration:"
        .. " name=" .. annotationName
        .. " side=" .. tostring(placement.side)
        .. " final=" .. tostring(placement.textX) .. "," .. tostring(placement.textY)
        .. " status=" .. (placement.unresolvedReservedCollision and "blocked" or "shifted")
    )
  end

  if placement.text ~= rawText then
    local trimKey = annotationName .. "|" .. placement.side .. "|" .. placement.text
    appendRuntimeLogOnce(
      args,
      "annotation_trim_" .. annotationName,
      trimKey,
      "overview annotation text trimmed: name=" .. annotationName
        .. " side=" .. placement.side
        .. " text=\"" .. placement.text .. "\""
    )
  end

  local finalTextY = placement.textY or textY
  if placement.textX ~= placement.requestedTextX or finalTextY ~= requestedTextY then
    local clampKey = table.concat({
      annotationName,
      tostring(placement.requestedTextX),
      tostring(requestedTextY),
      tostring(placement.textX),
      tostring(finalTextY),
      tostring(spec.slotX),
      tostring(spec.slotY),
      tostring(spec.slotW),
      tostring(spec.slotH),
    }, "|")

    appendRuntimeLogOnce(
      args,
      "annotation_clamp_" .. annotationName,
      clampKey,
      "overview annotation clamped:"
        .. " name=" .. annotationName
        .. " requested=" .. tostring(placement.requestedTextX) .. "," .. tostring(requestedTextY)
        .. " final=" .. tostring(placement.textX) .. "," .. tostring(finalTextY)
        .. " viewport=" .. tostring(spec.slotX) .. "," .. tostring(spec.slotY)
        .. ":" .. tostring(spec.slotW) .. "x" .. tostring(spec.slotH)
    )
  end

  local lineColor = spec.lineColor
  local lineThickness = math.max(1, math.floor(spec.lineThickness or 1))
  drawLineSafe(args, anchorX, anchorY, elbowX, elbowY, lineColor, lineThickness)
  drawLineSafe(args, elbowX, elbowY, placement.endX, endY, lineColor, lineThickness)

  local cap = math.max(1, math.floor(spec.capSize or 2))
  drawLineSafe(args, placement.endX, endY - cap, placement.endX, endY + cap, lineColor, 1)
  local anchorDot = math.max(1, math.floor(spec.anchorSize or (lineThickness + 1)))
  local anchorHalf = math.floor(anchorDot / 2)
  GpuSafe.filledRect(args, anchorX - anchorHalf, anchorY - anchorHalf, anchorDot, anchorDot, lineColor)

  if spec.textShadowColor then
    GpuSafe.drawText(args, placement.textX + 1, finalTextY + 1, placement.text, spec.textShadowColor, nil, size, 0, {
      clipX = spec.slotX + 1,
      clipY = spec.slotY + 1,
      clipW = spec.slotW - 2,
      clipH = spec.slotH - 2,
    })
  end

  GpuSafe.drawText(args, placement.textX, finalTextY, placement.text, spec.textColor, nil, size, 0, {
    clipX = spec.slotX + 1,
    clipY = spec.slotY + 1,
    clipW = spec.slotW - 2,
    clipH = spec.slotH - 2,
  })

  calloutPlacementCache[annotationName] = {
    side = placement.side,
    text = placement.text,
    x = placement.textX,
    y = finalTextY,
  }
  local placementLogKey = table.concat({
    annotationName,
    tostring(placement.side),
    tostring(placement.text),
    tostring(placement.textX),
    tostring(finalTextY),
  }, "|")
  appendRuntimeLogOnce(
    args,
    "overview_callout_placement_" .. annotationName,
    placementLogKey,
    "overview callout placement: name=" .. annotationName
      .. " side=" .. tostring(placement.side)
      .. " text=\"" .. tostring(placement.text) .. "\""
      .. " final=" .. tostring(placement.textX) .. "," .. tostring(finalTextY)
  )
end

return M