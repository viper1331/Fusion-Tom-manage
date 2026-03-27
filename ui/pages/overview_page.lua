local M = {}
local lastViewportLogKey = nil

local function resolveOverviewZones(args)
  local r = args.rect
  local ui = args.ui
  local sv = args.sv
  local chooseOverviewStackLayout = args.chooseOverviewStackLayout
  local control = args.control

  local alertsH = ui.compact and math.max(28, sv(34)) or math.max(34, sv(42))
  local main = { x = r.x, y = r.y, w = r.w, h = math.max(1, r.h - alertsH - ui.gap) }
  local alerts = { x = r.x, y = main.y + main.h + ui.gap, w = r.w, h = alertsH }

  local innerW = math.max(8, main.w - ui.pad * 2)
  local innerH = math.max(8, main.h - sv(40))
  local overviewLayout = chooseOverviewStackLayout(math.max(8, innerW - 2), math.max(8, innerH - 2), control.laserModuleCount)

  return {
    main = main,
    alerts = alerts,
    overviewLayout = overviewLayout,
  }
end

local function logOverviewViewport(args, zones, imgW, imgH)
  local logger = args.appendUiRuntimeLog
  if type(logger) ~= "function" then
    return
  end

  local ui = args.ui
  local mode = ui.micro and "micro" or (ui.compact and "compact" or "large")
  local layout = zones.overviewLayout
  local reactorName = layout and layout.reactor and layout.reactor.name or "none"
  local moduleName = layout and layout.module and layout.module.name or "none"
  local renderedMode = "none"
  if layout and layout.reactor then
    renderedMode = layout.module and "pair" or "reactor-only"
  end
  local drawnCount = layout and layout.drawnModuleCount or 0

  local key = table.concat({
    mode,
    tostring(zones.main.w),
    tostring(zones.main.h),
    tostring(imgW),
    tostring(imgH),
    tostring(renderedMode),
    tostring(reactorName),
    tostring(moduleName),
    tostring(drawnCount),
  }, "|")

  if key ~= lastViewportLogKey then
    logger(
      "overview reactor viewport:"
        .. " mode=" .. mode
        .. " panel=" .. tostring(zones.main.w) .. "x" .. tostring(zones.main.h)
        .. " scene=" .. tostring(imgW) .. "x" .. tostring(imgH)
        .. " layout=" .. tostring(renderedMode)
        .. " reactor=" .. tostring(reactorName)
        .. " module=" .. tostring(moduleName)
        .. " modulesDrawn=" .. tostring(drawnCount)
    )
    lastViewportLogKey = key
  end
end

local function drawOverviewImageZone(args, zones)
  local ui = args.ui
  local C = args.colors
  local data = args.data
  local sv = args.sv
  local gpu = args.gpu

  local left = zones.main

  args.drawPanel(left.x, left.y, left.w, left.h, "REACTOR")
  local innerX = left.x + ui.pad
  local innerY = left.y + sv(32)
  local innerW = math.max(8, left.w - ui.pad * 2)
  local innerH = math.max(8, left.h - sv(40))
  gpu.filledRectangle(innerX, innerY, innerW, innerH, C.white)
  gpu.rectangle(innerX, innerY, innerW, innerH, C.border)

  local imgInset = 1
  local imgX = innerX + imgInset
  local imgY = innerY + imgInset
  local imgW = math.max(8, innerW - imgInset * 2)
  local imgH = math.max(8, innerH - imgInset * 2)

  logOverviewViewport(args, zones, imgW, imgH)

  args.drawReactorLaserScene(imgX, imgY, imgW, imgH, data, zones.overviewLayout)

  local badgeW = ui.compact and math.max(70, sv(88)) or math.max(82, sv(102))
  local badgeH = math.max(14, sv(16))
  local badgeX = innerX + innerW - badgeW - ui.smallPad
  local badgeY = innerY + ui.smallPad
  local statusColor = args.chooseStateColor(data)

  gpu.filledRectangle(badgeX, badgeY, badgeW, badgeH, C.panel)
  gpu.rectangle(badgeX, badgeY, badgeW, badgeH, C.border)
  args.drawTextCenter(badgeX, badgeY + math.max(0, math.floor((badgeH - args.textPixelHeight(1)) / 2)), badgeW, data.status, statusColor, 1)

  local laserCountText = ui.micro and ("Lx" .. tostring(args.control.laserModuleCount)) or ("LASER x" .. tostring(args.control.laserModuleCount))
  local countBadgeW = ui.micro and math.max(40, sv(50)) or (ui.compact and math.max(54, sv(66)) or math.max(64, sv(78)))
  local countBadgeH = ui.micro and math.max(10, sv(11)) or math.max(11, sv(12))
  local countBadgeX = innerX + innerW - countBadgeW - ui.smallPad
  local countBadgeY = badgeY + badgeH + math.max(1, math.floor(ui.smallPad * 0.35))
  gpu.filledRectangle(countBadgeX, countBadgeY, countBadgeW, countBadgeH, C.panel2)
  gpu.rectangle(countBadgeX, countBadgeY, countBadgeW, countBadgeH, C.border)
  args.drawTextCenter(
    countBadgeX,
    countBadgeY + math.max(0, math.floor((countBadgeH - args.textPixelHeight(1)) / 2)),
    countBadgeW,
    laserCountText,
    C.muted,
    1
  )
end

local function drawOverviewAlertsZone(args, zones)
  local C = args.colors
  local data = args.data
  local ui = args.ui

  local alerts = zones.alerts
  args.drawPanel(alerts.x, alerts.y, alerts.w, alerts.h, "ALERTS")
  local textTop = alerts.y + (ui.compact and math.max(14, args.sv(16)) or math.max(16, args.sv(18)))
  local maxTop = alerts.y + alerts.h - args.textPixelHeight(1) - 1
  local ty = math.max(alerts.y + 1, math.min(textTop, maxTop))
  args.drawTextCenter(alerts.x, ty, alerts.w, data.alerts or "none", data.alerts == "none" and C.green or C.orange, 1)
end

function M.draw(args)
  local zones = resolveOverviewZones(args)
  drawOverviewImageZone(args, zones)
  drawOverviewAlertsZone(args, zones)
end

return M
