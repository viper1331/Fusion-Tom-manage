local M = {}

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
    return false, "clipped"
  end

  local ok, err = pcall(gpu.filledRectangle, cx, cy, cw, ch, color)
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
      return false, "image out of bounds"
    end
  end

  local ok, err = pcall(function()
    gpu.drawImage(x, y, img.ref())
  end)
  return ok, err
end

return M
