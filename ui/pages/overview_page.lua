local M = {}

local function resolveOverviewZones(args)
  local r = args.rect
  local ui = args.ui
  local sv = args.sv
  local chooseOverviewStackLayout = args.chooseOverviewStackLayout
  local control = args.control
  local splitVertical = args.splitVertical
  local splitHorizontal = args.splitHorizontal

  local alertsH = math.max(62, sv(72))
  local main = { x = r.x, y = r.y, w = r.w, h = r.h - alertsH - ui.gap }
  local alerts = { x = r.x, y = main.y + main.h + ui.gap, w = r.w, h = alertsH }

  local candidateRatios = ui.compact and {1.00, 0.72, 0.66, 0.60, 0.56, 0.52} or {0.64, 0.60, 0.56, 0.52, 0.50, 0.48}
  local left, right, overviewLayout
  local infoMinW = ui.compact and math.max(110, math.floor(main.w * 0.45)) or math.max(140, math.floor(main.w * 0.28))

  for _, ratio in ipairs(candidateRatios) do
    local testLeft, testRight
    if ui.compact then
      local splitH = math.floor((main.h - ui.gap) * ratio)
      testLeft = { x = main.x, y = main.y, w = main.w, h = splitH }
      testRight = { x = main.x, y = main.y + splitH + ui.gap, w = main.w, h = main.h - splitH - ui.gap }
    else
      local splitW = math.floor((main.w - ui.gap) * ratio)
      testLeft = { x = main.x, y = main.y, w = splitW, h = main.h }
      testRight = { x = main.x + splitW + ui.gap, y = main.y, w = main.w - splitW - ui.gap, h = main.h }
    end

    local innerX = testLeft.x + ui.pad
    local innerY = testLeft.y + sv(38)
    local innerW = testLeft.w - ui.pad * 2
    local innerH = testLeft.h - sv(46)

    if innerW > 20 and innerH > 20 then
      local imgInset = 1
      local imgX = innerX + imgInset
      local imgY = innerY + imgInset
      local imgW = innerW - imgInset * 2
      local imgH = innerH - imgInset * 2
      local fit = chooseOverviewStackLayout(imgW, imgH, control.laserModuleCount)

      if fit and fit.reactor and (ui.compact or testRight.w >= infoMinW) and testRight.h >= math.max(120, sv(160)) then
        left, right, overviewLayout = testLeft, testRight, fit
        break
      end
    end
  end

  if not left then
    if ui.compact then
      left, right = splitVertical(main, 0.66)
    else
      left, right = splitHorizontal(main, 0.60)
    end

    local innerX = left.x + ui.pad
    local innerY = left.y + sv(38)
    local innerW = left.w - ui.pad * 2
    local innerH = left.h - sv(46)
    overviewLayout = chooseOverviewStackLayout(math.max(8, innerW - 2), math.max(8, innerH - 2), control.laserModuleCount)
  end

  return {
    main = main,
    alerts = alerts,
    left = left,
    right = right,
    overviewLayout = overviewLayout,
  }
end

local function drawOverviewImageZone(args, zones)
  local ui = args.ui
  local C = args.colors
  local data = args.data
  local sv = args.sv
  local gpu = args.gpu

  local left = zones.left

  args.drawPanel(left.x, left.y, left.w, left.h, "REACTOR")
  local innerX = left.x + ui.pad
  local innerY = left.y + sv(38)
  local innerW = left.w - ui.pad * 2
  local innerH = left.h - sv(46)
  gpu.filledRectangle(innerX, innerY, innerW, innerH, C.white)
  gpu.rectangle(innerX, innerY, innerW, innerH, C.border)

  local imgInset = 1
  local imgX = innerX + imgInset
  local imgY = innerY + imgInset
  local imgW = innerW - imgInset * 2
  local imgH = innerH - imgInset * 2

  args.drawReactorLaserScene(imgX, imgY, imgW, imgH, data, zones.overviewLayout)

  local badgeW = math.max(90, sv(116))
  local badgeH = math.max(16, sv(18))
  local badgeX = innerX + innerW - badgeW - ui.smallPad
  local badgeY = innerY + ui.smallPad
  local statusColor = args.chooseStateColor(data)

  gpu.filledRectangle(badgeX, badgeY, badgeW, badgeH, C.panel)
  gpu.rectangle(badgeX, badgeY, badgeW, badgeH, C.border)
  args.drawTextCenter(badgeX, badgeY + math.max(0, math.floor((badgeH - args.textPixelHeight(1)) / 2)), badgeW, data.status, statusColor, 1)

  local countBadgeW = math.max(90, sv(116))
  local countBadgeH = badgeH
  local countBadgeX = badgeX
  local countBadgeY = badgeY + badgeH + math.max(2, math.floor(ui.smallPad * 0.5))
  gpu.filledRectangle(countBadgeX, countBadgeY, countBadgeW, countBadgeH, C.panel)
  gpu.rectangle(countBadgeX, countBadgeY, countBadgeW, countBadgeH, C.border)
  args.drawTextCenter(
    countBadgeX,
    countBadgeY + math.max(0, math.floor((countBadgeH - args.textPixelHeight(1)) / 2)),
    countBadgeW,
    "LASER x" .. tostring(args.control.laserModuleCount),
    C.yellow,
    1
  )
end

local function drawOverviewInfoZone(args, zones)
  local ui = args.ui
  local C = args.colors
  local data = args.data
  local sv = args.sv

  local right = zones.right

  args.drawPanel(right.x, right.y, right.w, right.h, "POWER & FUEL")
  local px = right.x + ui.pad
  local pw = right.w - ui.pad * 2
  local topY = right.y + sv(50)
  local rowGap = sv(16)
  local step = ui.gaugeH + rowGap

  local availableH = right.h - sv(120)
  local gaugeCount = availableH < (step * 5) and 4 or 5

  args.drawGauge(px, topY, pw, ui.gaugeH, data.energyPct, C.green, "ENERGY", data.energyText)
  args.drawGauge(px, topY + step, pw, ui.gaugeH, args.clamp(data.caseMK, 0, 100), C.orange, "CASE", tostring(args.round(data.caseMK, 1)) .. " MK")
  args.drawGauge(px, topY + step * 2, pw, ui.gaugeH, data.dPct, C.green, "D", tostring(data.dPct) .. " %")
  args.drawGauge(px, topY + step * 3, pw, ui.gaugeH, data.tPct, C.cyan, "T", tostring(data.tPct) .. " %")
  if gaugeCount >= 5 then
    args.drawGauge(px, topY + step * 4, pw, ui.gaugeH, data.dtPct, C.yellow, "DT", tostring(data.dtPct) .. " %")
  end

  local fy = right.y + right.h - (gaugeCount >= 5 and sv(72) or sv(54))
  args.drawToggleRow(right, fy, "INJECTION", data.injection, C.text)
  args.drawToggleRow(right, fy + sv(18), "PRODUCTION", data.productionText, C.green)
  args.drawToggleRow(right, fy + sv(36), "LOGIC", data.logicMode, C.cyan)
  if gaugeCount >= 5 then
    args.drawToggleRow(right, fy + sv(54), "LASER", data.laserReady and "READY" or "NOT READY", data.laserReady and C.green or C.red)
  end
end

local function drawOverviewAlertsZone(args, zones)
  local C = args.colors
  local data = args.data

  local alerts = zones.alerts
  args.drawPanel(alerts.x, alerts.y, alerts.w, alerts.h, "ALERTS")
  local ty = alerts.y + math.max(0, math.floor((alerts.h - args.textPixelHeight(1)) / 2))
  args.drawTextCenter(alerts.x, ty, alerts.w, data.alerts or "none", data.alerts == "none" and C.green or C.orange, 1)
end

function M.draw(args)
  local zones = resolveOverviewZones(args)
  drawOverviewImageZone(args, zones)
  drawOverviewInfoZone(args, zones)
  drawOverviewAlertsZone(args, zones)
end

return M
