local M = {}

local function isCompact5x5(ui)
  local mode = tostring((ui and ui.overviewScreenClass) or (ui and ui.overviewResponsiveMode) or "")
  return mode == "compact_5x5"
end

local function drawRowsWithinPanel(args, rect, startY, step, rows)
  local maxRows = math.max(0, math.floor((rect.y + rect.h - startY - args.ui.smallPad) / step))
  local count = math.min(#rows, maxRows)
  for i = 1, count do
    local row = rows[i]
    args.drawToggleRow(rect, startY + (i - 1) * step, row.label, row.value, row.color)
  end
end

local function drawCompact5x5(args)
  local r = args.rect
  local data = args.data
  local ui = args.ui
  local C = args.colors
  local state = args.state

  local commandRect, manageRect = args.splitVertical(r, 0.62)
  args.drawPanel(commandRect.x, commandRect.y, commandRect.w, commandRect.h, "COMMAND")

  local pad = ui.pad
  local gap = ui.gap
  local bw = math.max(10, math.floor((commandRect.w - pad * 2 - gap) / 2))
  local bh = math.max(14, math.min(math.max(ui.buttonH - 4, args.sv(20)), math.floor(commandRect.h * 0.20)))
  local x1 = commandRect.x + pad
  local x2 = x1 + bw + gap
  local y1 = commandRect.y + args.sv(28)
  local rowGap = math.max(2, args.sv(6))
  local y2 = y1 + bh + rowGap
  local y3 = y2 + bh + rowGap

  args.drawButton("START", x1, y1, bw, bh, "[START]", "green", true)
  args.drawButton("STOP", x2, y1, bw, bh, "[STOP]", "red", true)
  args.drawButton("AUTO", x1, y2, bw, bh, state.auto and "[AUTO ON]" or "[AUTO OFF]", "orange", true)
  args.drawButton("SCRAM", x2, y2, bw, bh, "[SCRAM]", "red", true)
  args.drawButton("FIRE_LASER", x1, y3, bw, bh, "[FIRE]", "cyan", true)
  args.drawButton("FILL_HOHLRAUM", x2, y3, bw, bh, "[HOHL]", "purple", true)

  local infoY = y3 + bh + rowGap
  local infoStep = math.max(8, args.sv(10))
  drawRowsWithinPanel(args, commandRect, infoY, infoStep, {
    { label = "MODE", value = data.logicMode, color = C.cyan },
    { label = "STATUS", value = data.status, color = args.chooseStateColor(data) },
    { label = "AMP", value = data.laserAmplifierText, color = data.laserReady and C.green or C.orange },
  })

  args.drawPanel(manageRect.x, manageRect.y, manageRect.w, manageRect.h, "MANAGEMENT")
  local mRowY = manageRect.y + args.sv(28)
  local mStep = math.max(8, args.sv(10))
  drawRowsWithinPanel(args, manageRect, mRowY, mStep, {
    { label = "PROFILE", value = "P" .. tostring(state.ignitionProfile), color = C.yellow },
    { label = "FUEL", value = state.manualFuel and "OPEN" or "CLOSED", color = state.manualFuel and C.orange or C.muted },
    { label = "MAINT", value = state.maintenance and "ON" or "OFF", color = state.maintenance and C.orange or C.muted },
    { label = "LASER", value = args.relaySideConfigured("laserCharge") or "UNSET", color = args.relaySideConfigured("laserCharge") and C.green or C.orange },
  })

  local by = manageRect.y + manageRect.h - (bh * 2 + rowGap + ui.smallPad)
  if by >= manageRect.y + args.sv(24) then
    local mx1 = manageRect.x + pad
    local mw = math.max(10, math.floor((manageRect.w - pad * 2 - gap) / 2))
    local mx2 = mx1 + mw + gap
    args.drawButton("PROFILE_PREV", mx1, by, mw, bh, "[P-]", "purple", true)
    args.drawButton("PROFILE_NEXT", mx2, by, mw, bh, "[P+]", "purple", true)
    args.drawButton("MANUAL_FUEL", mx1, by + bh + rowGap, mw, bh, state.manualFuel and "[F CLOSE]" or "[F OPEN]", "orange", true)
    args.drawButton("MAINTENANCE", mx2, by + bh + rowGap, mw, bh, state.maintenance and "[M OFF]" or "[M ON]", "orange", true)
  end
end

function M.draw(args)
  local r = args.rect
  local data = args.data
  local ui = args.ui
  local C = args.colors
  local state = args.state

  if isCompact5x5(ui) then
    drawCompact5x5(args)
    return
  end

  local left, right
  if ui.compact then
    left, right = args.splitVertical(r, 0.54)
  else
    left, right = args.splitHorizontal(r, 0.52)
  end

  args.drawPanel(left.x, left.y, left.w, left.h, "COMMAND CENTER")

  local pad = ui.pad
  local gap = ui.gap
  local bw = math.floor((left.w - pad * 2 - gap) / 2)
  local bh = math.max(ui.buttonH, args.sv(36))
  local x1 = left.x + pad
  local x2 = x1 + bw + gap
  local y1 = left.y + args.sv(54)
  local y2 = y1 + bh + args.sv(12)
  local y3 = y2 + bh + args.sv(12)

  args.drawButton("START", x1, y1, bw, bh, "[START]", "green", true)
  args.drawButton("STOP", x2, y1, bw, bh, "[STOP]", "red", true)
  args.drawButton("AUTO", x1, y2, bw, bh, state.auto and "[AUTO UI ON]" or "[AUTO UI OFF]", "orange", true)
  args.drawButton("SCRAM", x2, y2, bw, bh, "[SCRAM]", "red", true)
  args.drawButton("FIRE_LASER", x1, y3, bw, bh, "[FIRE LASER]", "cyan", true)
  args.drawButton("FILL_HOHLRAUM", x2, y3, bw, bh, "[HOHLRAUM]", "purple", true)

  local infoY = y3 + bh + args.sv(18)
  args.drawToggleRow(left, infoY, "MODE", data.logicMode, C.cyan)
  args.drawToggleRow(left, infoY + args.sv(18), "STATUS", data.status, args.chooseStateColor(data))
  args.drawToggleRow(left, infoY + args.sv(36), "AMPLIFIER", data.laserAmplifierText, data.laserReady and C.green or C.orange)
  args.drawToggleRow(left, infoY + args.sv(54), "LAST ACTION", state.lastAction, C.cyan)

  args.drawPanel(right.x, right.y, right.w, right.h, "MANAGEMENT")
  local rx = right.x + ui.pad
  local rw = right.w - ui.pad * 2
  local rowY = right.y + args.sv(54)

  args.drawToggleRow(right, rowY, "IGNITION PROFILE (UI)", "P" .. tostring(state.ignitionProfile), C.yellow)
  args.drawToggleRow(right, rowY + args.sv(18), "MANUAL FUEL", state.manualFuel and "OPEN" or "CLOSED", state.manualFuel and C.orange or C.muted)
  args.drawToggleRow(right, rowY + args.sv(36), "MAINTENANCE", state.maintenance and "ON" or "OFF", state.maintenance and C.orange or C.muted)
  args.drawToggleRow(right, rowY + args.sv(54), "LASER RELAY", args.relaySideConfigured("laserCharge") or "UNSET", args.relaySideConfigured("laserCharge") and C.green or C.orange)
  args.drawToggleRow(right, rowY + args.sv(72), "DEUT RELAY", args.relaySideConfigured("deuteriumTank") or "UNSET", args.relaySideConfigured("deuteriumTank") and C.green or C.orange)
  args.drawToggleRow(right, rowY + args.sv(90), "TRIT RELAY", args.relaySideConfigured("tritiumTank") or "UNSET", args.relaySideConfigured("tritiumTank") and C.green or C.orange)
  args.drawToggleRow(right, rowY + args.sv(108), "HOHLRAUM", data.hohlraumLoaded and "LOADED" or "MISSING", data.hohlraumLoaded and C.green or C.red)

  local by1 = right.y + right.h - args.sv(122)
  local bw2 = math.floor((rw - gap) / 2)
  local bx1 = rx
  local bx2 = rx + bw2 + gap

  args.drawButton("PROFILE_PREV", bx1, by1, bw2, bh, "[PROFILE UI -]", "purple", true)
  args.drawButton("PROFILE_NEXT", bx2, by1, bw2, bh, "[PROFILE UI +]", "purple", true)
  args.drawButton("MANUAL_FUEL", bx1, by1 + bh + args.sv(12), bw2, bh, state.manualFuel and "[FUEL CLOSE]" or "[FUEL OPEN]", "orange", true)
  args.drawButton("MAINTENANCE", bx2, by1 + bh + args.sv(12), bw2, bh, state.maintenance and "[MAINT OFF]" or "[MAINT ON]", "orange", true)
end

return M
