local M = {}

function M.draw(args)
  local r = args.rect
  local data = args.data
  local ui = args.ui
  local C = args.colors
  local state = args.state

  local top, bottom = args.splitVertical(r, 0.56)

  args.drawPanel(top.x, top.y, top.w, top.h, "FUEL MANAGEMENT")
  local x = top.x + ui.pad
  local w = top.w - ui.pad * 2
  local topY = top.y + args.sv(54)
  local step = ui.gaugeH + args.sv(20)

  args.drawGauge(x, topY, w, ui.gaugeH, data.dPct, C.green, "DEUTERIUM CORE", tostring(math.floor(data.dPct + 0.5)) .. " %")
  args.drawGauge(x, topY + step, w, ui.gaugeH, data.tPct, C.cyan, "TRITIUM CORE", tostring(math.floor(data.tPct + 0.5)) .. " %")
  args.drawGauge(x, topY + step * 2, w, ui.gaugeH, data.dtPct, C.yellow, "D-T CORE", tostring(math.floor(data.dtPct + 0.5)) .. " %")
  args.drawGauge(x, topY + step * 3, w, ui.gaugeH, data.energyPct, C.green, "ENERGY BUFFER", data.energyText)

  local infoY = top.y + top.h - args.sv(92)
  args.drawToggleRow(top, infoY, "SUPPLY D", data.readers.deuterium.amountText, data.readers.deuterium.ok and C.green or C.orange)
  args.drawToggleRow(top, infoY + args.sv(18), "SUPPLY T", data.readers.tritium.amountText, data.readers.tritium.ok and C.cyan or C.orange)
  args.drawToggleRow(top, infoY + args.sv(36), "SUPPLY DT", data.readers.dtFuel.amountText, data.readers.dtFuel.ok and C.yellow or C.orange)
  args.drawToggleRow(top, infoY + args.sv(54), "ACTIVE READER", data.activeReader, data.activeReaderColor)

  args.drawPanel(bottom.x, bottom.y, bottom.w, bottom.h, "FUEL ACTIONS")
  local pad = ui.pad
  local gap = ui.gap
  local bw = math.floor((bottom.w - pad * 2 - gap) / 2)
  local bh = math.max(ui.buttonH, args.sv(36))
  local x1 = bottom.x + pad
  local x2 = x1 + bw + gap
  local y1 = bottom.y + args.sv(54)
  local y2 = y1 + bh + args.sv(12)

  args.drawButton("MANUAL_FUEL", x1, y1, bw, bh, state.manualFuel and "[FUEL CLOSE]" or "[FUEL OPEN]", "orange", true)
  args.drawButton("FILL_HOHLRAUM", x2, y1, bw, bh, "[LOAD HOHLRAUM]", "purple", true)
  args.drawButton("PROFILE_PREV", x1, y2, bw, bh, "[PROFILE UI -]", "purple", true)
  args.drawButton("PROFILE_NEXT", x2, y2, bw, bh, "[PROFILE UI +]", "purple", true)
end

return M
