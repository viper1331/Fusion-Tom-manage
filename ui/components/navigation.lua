local M = {}

function M.draw(args)
  local rect = args.rect
  local ui = args.ui
  local pages = args.pages or {}
  local activePage = args.activePage
  local drawPanel = args.drawPanel
  local drawButton = args.drawButton

  drawPanel(rect.x, rect.y, rect.w, rect.h, nil)

  local innerX = rect.x + ui.smallPad
  local innerY = rect.y + ui.smallPad
  local innerW = rect.w - ui.smallPad * 2
  local innerH = rect.h - ui.smallPad * 2
  local tabGap = ui.smallPad
  local count = #pages

  if count < 1 then
    return
  end

  local tabW = math.floor((innerW - tabGap * (count - 1)) / count)
  for i, page in ipairs(pages) do
    local bx = innerX + (i - 1) * (tabW + tabGap)
    local tone = activePage == page.id and "cyan" or "purple"
    drawButton("PAGE_" .. page.id, bx, innerY, tabW, innerH, page.label, tone, true)
  end
end

return M
