local M = {}

function M.draw(args)
  local r = args.rect
  local data = args.data
  local ui = args.ui
  local C = args.colors
  local state = args.state

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
