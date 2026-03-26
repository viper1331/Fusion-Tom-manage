local M = {}

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
