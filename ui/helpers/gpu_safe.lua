local M = {}
local throttleFallback = {}

local function nowMs()
  if os.epoch then
    return os.epoch("utc")
  end
  return math.floor((os.clock() or 0) * 1000)
end

local function logWithLevel(logger, level, category, message, context, sink)
  if not logger then
    return false
  end

  local method = string.lower(tostring(level or "INFO"))
  local fn = logger[method]
  if type(fn) == "function" then
    return fn(category, message, context, sink or "runtime")
  end

  if type(logger.info) == "function" then
    return logger.info(category, message, context, sink or "runtime")
  end

  return false
end

local function throttleFallbackAllow(key, intervalMs)
  local now = nowMs()
  local previous = throttleFallback[key]
  if previous and (now - previous) < intervalMs then
    return false
  end
  throttleFallback[key] = now
  return true
end

local function logGpu(args, level, message, context, key, intervalMs)
  local category = tostring((args and args.logCategory) or "GPU")
  local sink = tostring((args and args.logSink) or "runtime")
  local logger = args and args.logger

  if logger and key and type(logger.throttle) == "function" then
    logger.throttle(key, intervalMs or 4000, level, category, message, context, sink)
    return
  end

  if logger then
    if key and not throttleFallbackAllow(key, intervalMs or 4000) then
      return
    end
    logWithLevel(logger, level, category, message, context, sink)
    return
  end

  local appendFallback = args and args.appendUiRuntimeLog
  if type(appendFallback) == "function" then
    if key and not throttleFallbackAllow(key, intervalMs or 4000) then
      return
    end
    appendFallback({
      category = category,
      level = level,
      message = message,
      context = context,
    })
  end
end

local function resolveBounds(args, gpu)
  local g = gpu or (args and args.gpu)
  if not g then
    return nil, nil
  end

  local ui = args and args.ui
  if ui and type(ui.sw) == "number" and type(ui.sh) == "number" then
    return math.max(1, math.floor(ui.sw)), math.max(1, math.floor(ui.sh))
  end

  local ok, sw, sh = pcall(g.getSize)
  if not ok or type(sw) ~= "number" or type(sh) ~= "number" then
    return nil, nil
  end

  return math.max(1, math.floor(sw)), math.max(1, math.floor(sh))
end

local function clipRect(x, y, w, h, sw, sh)
  x = math.floor(tonumber(x) or 0)
  y = math.floor(tonumber(y) or 0)
  w = math.floor(tonumber(w) or 0)
  h = math.floor(tonumber(h) or 0)

  if w <= 0 or h <= 0 then
    return nil
  end

  local x2 = x + w - 1
  local y2 = y + h - 1

  if x2 < 0 or y2 < 0 or x >= sw or y >= sh then
    return nil
  end

  local cx = math.max(0, x)
  local cy = math.max(0, y)
  local cx2 = math.min(sw - 1, x2)
  local cy2 = math.min(sh - 1, y2)

  local cw = cx2 - cx + 1
  local ch = cy2 - cy + 1
  if cw <= 0 or ch <= 0 then
    return nil
  end

  return cx, cy, cw, ch
end

local function getImageSize(img)
  if not img then
    return nil, nil
  end

  local okW, width = pcall(function()
    return img.getWidth and img.getWidth() or nil
  end)
  local okH, height = pcall(function()
    return img.getHeight and img.getHeight() or nil
  end)
  if not okW or not okH or type(width) ~= "number" or type(height) ~= "number" then
    return nil, nil
  end

  return math.max(0, math.floor(width)), math.max(0, math.floor(height))
end

local function resolveTextWidth(gpu, text, size, angle)
  local value = tostring(text or "")
  if value == "" then
    return 0
  end

  local ok, width = pcall(gpu.getTextLength, value, size, angle)
  if not ok or type(width) ~= "number" then
    return 0
  end

  return math.max(0, math.floor(width))
end

local function resolveClip(sw, sh, options)
  local opts = type(options) == "table" and options or {}
  local clipX = math.floor(tonumber(opts.clipX) or 0)
  local clipY = math.floor(tonumber(opts.clipY) or 0)
  local clipW = math.floor(tonumber(opts.clipW) or sw)
  local clipH = math.floor(tonumber(opts.clipH) or sh)

  if clipW <= 0 or clipH <= 0 then
    return nil
  end

  local clipX2 = clipX + clipW - 1
  local clipY2 = clipY + clipH - 1
  if clipX2 < 0 or clipY2 < 0 or clipX >= sw or clipY >= sh then
    return nil
  end

  local cx = math.max(0, clipX)
  local cy = math.max(0, clipY)
  local cx2 = math.min(sw - 1, clipX2)
  local cy2 = math.min(sh - 1, clipY2)

  local cw = cx2 - cx + 1
  local ch = cy2 - cy + 1
  if cw <= 0 or ch <= 0 then
    return nil
  end

  return {
    x = cx,
    y = cy,
    w = cw,
    h = ch,
    right = cx2,
    bottom = cy2,
  }
end

local function fitTextToWidth(gpu, text, size, angle, maxWidth)
  if maxWidth <= 0 then
    return ""
  end

  local raw = tostring(text or "")
  if raw == "" then
    return ""
  end

  local fullWidth = resolveTextWidth(gpu, raw, size, angle)
  if fullWidth <= maxWidth then
    return raw
  end

  local suffix = "..."
  local suffixWidth = resolveTextWidth(gpu, suffix, size, angle)
  if suffixWidth > maxWidth then
    suffix = ""
    suffixWidth = 0
  end

  local low = 0
  local high = #raw
  local best = 0

  while low <= high do
    local mid = math.floor((low + high) / 2)
    local probe = string.sub(raw, 1, mid) .. suffix
    local probeWidth = resolveTextWidth(gpu, probe, size, angle)
    if probeWidth <= maxWidth then
      best = mid
      low = mid + 1
    else
      high = mid - 1
    end
  end

  if best <= 0 and suffix == "" then
    return ""
  end

  local out = string.sub(raw, 1, best) .. suffix
  if out == suffix and suffix == "" then
    return ""
  end
  return out
end

function M.filledRect(args, x, y, w, h, color)
  local gpu = args and args.gpu
  if not gpu then
    return false, "gpu unavailable"
  end

  local sw, sh = resolveBounds(args, gpu)
  if not sw or not sh then
    local ok, err = pcall(gpu.filledRectangle, x, y, w, h, color)
    return ok, err
  end

  local cx, cy, cw, ch = clipRect(x, y, w, h, sw, sh)
  if not cx then
    logGpu(args, "DEBUG", "filledRect skipped (clipped)", {
      x = math.floor(tonumber(x) or 0),
      y = math.floor(tonumber(y) or 0),
      w = math.floor(tonumber(w) or 0),
      h = math.floor(tonumber(h) or 0),
      sw = sw,
      sh = sh,
    }, "gpu.filledRect.clipped", 3000)
    return false, "clipped"
  end

  if cx ~= x or cy ~= y or cw ~= w or ch ~= h then
    logGpu(args, "DEBUG", "filledRect clamped", {
      x = math.floor(tonumber(x) or 0),
      y = math.floor(tonumber(y) or 0),
      w = math.floor(tonumber(w) or 0),
      h = math.floor(tonumber(h) or 0),
      clamped = tostring(cx) .. "," .. tostring(cy) .. ":" .. tostring(cw) .. "x" .. tostring(ch),
      sw = sw,
      sh = sh,
    }, "gpu.filledRect.clamped", 5000)
  end

  local ok, err = pcall(gpu.filledRectangle, cx, cy, cw, ch, color)
  if not ok then
    logGpu(args, "WARN", "filledRect draw failed", {
      error = tostring(err),
      x = cx,
      y = cy,
      w = cw,
      h = ch,
    }, "gpu.filledRect.error", 2000)
  end
  return ok, err
end

function M.rectangle(args, x, y, w, h, color)
  x = math.floor(tonumber(x) or 0)
  y = math.floor(tonumber(y) or 0)
  w = math.floor(tonumber(w) or 0)
  h = math.floor(tonumber(h) or 0)
  if w <= 0 or h <= 0 then
    return false
  end

  local okTop = M.filledRect(args, x, y, w, 1, color)
  local okBottom = M.filledRect(args, x, y + h - 1, w, 1, color)
  local okLeft = M.filledRect(args, x, y, 1, h, color)
  local okRight = M.filledRect(args, x + w - 1, y, 1, h, color)
  return okTop or okBottom or okLeft or okRight
end

function M.drawImage(args, img, x, y)
  local gpu = args and args.gpu
  if not gpu then
    return false, "gpu unavailable"
  end
  if not img then
    return false, "image missing"
  end

  local iw, ih = getImageSize(img)
  if not iw or not ih then
    return false, "image size unavailable"
  end
  if iw <= 0 or ih <= 0 then
    return false, "image empty"
  end

  local sw, sh = resolveBounds(args, gpu)
  if sw and sh then
    x = math.floor(tonumber(x) or 0)
    y = math.floor(tonumber(y) or 0)
    if x < 0 or y < 0 or (x + iw) > sw or (y + ih) > sh then
      logGpu(args, "WARN", "drawImage skipped (out of bounds)", {
        x = x,
        y = y,
        w = iw,
        h = ih,
        sw = sw,
        sh = sh,
      }, "gpu.drawImage.out_of_bounds", 3000)
      return false, "image out of bounds"
    end
  end

  local ok, err = pcall(function()
    gpu.drawImage(x, y, img.ref())
  end)
  if not ok then
    logGpu(args, "WARN", "drawImage failed", {
      x = x,
      y = y,
      error = tostring(err),
    }, "gpu.drawImage.error", 2000)
  end
  return ok, err
end

function M.drawText(args, x, y, text, color, bgColor, size, angle, options)
  local gpu = args and args.gpu
  if not gpu then
    return false, "gpu unavailable"
  end

  local sw, sh = resolveBounds(args, gpu)
  if not sw or not sh then
    local drawX = math.floor(tonumber(x) or 0)
    local drawY = math.floor(tonumber(y) or 0)
    local drawText = tostring(text or "")
    local drawSize = math.max(1, math.floor(tonumber(size) or 1))
    local drawAngle = tonumber(angle) or 0
    if drawText == "" then
      return false, "empty text"
    end
    local ok, err = pcall(gpu.drawText, drawX, drawY, drawText, color, bgColor, drawSize, drawAngle)
    return ok, err
  end

  local drawSize = math.max(1, math.floor(tonumber(size) or 1))
  local drawAngle = tonumber(angle) or 0
  local drawText = tostring(text or "")
  if drawText == "" then
    return false, "empty text"
  end

  local clip = resolveClip(sw, sh, options)
  if not clip then
    logGpu(args, "DEBUG", "drawText skipped (clip out of bounds)", {
      x = math.floor(tonumber(x) or 0),
      y = math.floor(tonumber(y) or 0),
      sw = sw,
      sh = sh,
    }, "gpu.drawText.clip_oob", 3000)
    return false, "clip out of bounds"
  end

  local drawY = math.floor(tonumber(y) or 0)
  local textH = math.max(1, 8 * drawSize)
  if textH > clip.h then
    logGpu(args, "DEBUG", "drawText skipped (text too tall)", {
      textH = textH,
      clipH = clip.h,
      clip = tostring(clip.x) .. "," .. tostring(clip.y) .. ":" .. tostring(clip.w) .. "x" .. tostring(clip.h),
    }, "gpu.drawText.too_tall", 4000)
    return false, "text too tall for clip"
  end

  if drawY < clip.y then
    drawY = clip.y
  end
  if (drawY + textH - 1) > clip.bottom then
    drawY = clip.bottom - textH + 1
  end
  if drawY < clip.y then
    logGpu(args, "DEBUG", "drawText skipped (y outside clip)", {
      requestedY = math.floor(tonumber(y) or 0),
      finalY = drawY,
      clipY = clip.y,
      clipBottom = clip.bottom,
    }, "gpu.drawText.y_oob", 4000)
    return false, "y outside clip"
  end

  drawText = fitTextToWidth(gpu, drawText, drawSize, drawAngle, clip.w)
  if drawText == "" then
    logGpu(args, "DEBUG", "drawText skipped (outside clip width)", {
      requestedText = tostring(text or ""),
      clipW = clip.w,
      size = drawSize,
    }, "gpu.drawText.width_oob", 3000)
    return false, "text outside clip"
  end

  local textW = resolveTextWidth(gpu, drawText, drawSize, drawAngle)
  if textW <= 0 then
    return false, "text width invalid"
  end

  local drawX = math.floor(tonumber(x) or 0)
  if drawX < clip.x then
    drawX = clip.x
  end
  if (drawX + textW - 1) > clip.right then
    drawX = clip.right - textW + 1
  end

  if drawX < clip.x then
    logGpu(args, "DEBUG", "drawText skipped (x outside clip)", {
      requestedX = math.floor(tonumber(x) or 0),
      finalX = drawX,
      clipX = clip.x,
      clipRight = clip.right,
      text = drawText,
    }, "gpu.drawText.x_oob", 4000)
    return false, "x outside clip"
  end

  local ok, err = pcall(gpu.drawText, drawX, drawY, drawText, color, bgColor, drawSize, drawAngle)
  if not ok then
    logGpu(args, "WARN", "drawText failed", {
      x = drawX,
      y = drawY,
      text = drawText,
      error = tostring(err),
    }, "gpu.drawText.error", 2000)
  elseif drawX ~= math.floor(tonumber(x) or 0) or drawY ~= math.floor(tonumber(y) or 0) then
    logGpu(args, "DEBUG", "drawText clamped", {
      requested = tostring(math.floor(tonumber(x) or 0)) .. "," .. tostring(math.floor(tonumber(y) or 0)),
      final = tostring(drawX) .. "," .. tostring(drawY),
      text = drawText,
    }, "gpu.drawText.clamped", 5000)
  end
  return ok, err
end

function M.drawTextRight(args, xRight, y, text, color, bgColor, size, angle, options)
  local gpu = args and args.gpu
  if not gpu then
    return false, "gpu unavailable"
  end

  local drawSize = math.max(1, math.floor(tonumber(size) or 1))
  local drawAngle = tonumber(angle) or 0
  local rawText = tostring(text or "")
  local textW = resolveTextWidth(gpu, rawText, drawSize, drawAngle)
  local startX = math.floor(tonumber(xRight) or 0) - textW

  return M.drawText(args, startX, y, rawText, color, bgColor, drawSize, drawAngle, options)
end

function M.drawTextCenter(args, x, y, w, text, color, bgColor, size, angle, options)
  local gpu = args and args.gpu
  if not gpu then
    return false, "gpu unavailable"
  end

  local boxW = math.floor(tonumber(w) or 0)
  if boxW <= 0 then
    return false, "invalid width"
  end

  local drawSize = math.max(1, math.floor(tonumber(size) or 1))
  local drawAngle = tonumber(angle) or 0
  local rawText = tostring(text or "")
  local textW = resolveTextWidth(gpu, rawText, drawSize, drawAngle)
  local startX = math.floor(tonumber(x) or 0) + math.floor((boxW - textW) / 2)

  local opts = {}
  if type(options) == "table" then
    for key, value in pairs(options) do
      opts[key] = value
    end
  end
  if opts.clipX == nil then
    opts.clipX = math.floor(tonumber(x) or 0)
  end
  if opts.clipW == nil then
    opts.clipW = boxW
  end

  return M.drawText(args, startX, y, rawText, color, bgColor, drawSize, drawAngle, opts)
end

return M
