local M = {}

local function isCompact5x5(ui)
  local mode = tostring((ui and ui.overviewScreenClass) or (ui and ui.overviewResponsiveMode) or "")
  return mode == "compact_5x5"
end

local function drawCompact5x5(args)
  local r = args.rect
  local data = args.data
  local ui = args.ui
  local C = args.colors
  local state = args.state

  local top, bottom = args.splitVertical(r, 0.64)
  args.drawPanel(top.x, top.y, top.w, top.h, "FUEL")

  local x = top.x + ui.pad
  local w = top.w - ui.pad * 2
  local startY = top.y + args.sv(28)
  local gaugeStep = math.max(ui.gaugeH + args.sv(8), args.sv(14))
  local gaugeDefs = {
    { pct = data.dPct, color = C.green, label = "DEUT", value = tostring(math.floor(data.dPct + 0.5)) .. "%" },
    { pct = data.tPct, color = C.cyan, label = "TRIT", value = tostring(math.floor(data.tPct + 0.5)) .. "%" },
    { pct = data.dtPct, color = C.yellow, label = "DT", value = tostring(math.floor(data.dtPct + 0.5)) .. "%" },
    { pct = data.energyPct, color = C.green, label = "ENERGY", value = data.energyText },
  }
  local reserveRows = 2
  local reserveHeight = reserveRows * math.max(8, args.sv(10)) + ui.smallPad
  local maxGaugeRows = math.max(1, math.min(#gaugeDefs, math.floor((top.h - (startY - top.y) - reserveHeight - ui.smallPad) / gaugeStep)))
  for i = 1, maxGaugeRows do
    local g = gaugeDefs[i]
    args.drawGauge(x, startY + (i - 1) * gaugeStep, w, ui.gaugeH, g.pct, g.color, g.label, g.value)
  end

  local rowStep = math.max(8, args.sv(10))
  local infoY = top.y + top.h - reserveHeight
  args.drawToggleRow(top, infoY, "SUPPLY D", data.readers.deuterium.amountText, data.readers.deuterium.ok and C.green or C.orange)
  args.drawToggleRow(top, infoY + rowStep, "SUPPLY T", data.readers.tritium.amountText, data.readers.tritium.ok and C.cyan or C.orange)

  args.drawPanel(bottom.x, bottom.y, bottom.w, bottom.h, "ACTIONS")
  local pad = ui.pad
  local gap = ui.gap
  local bw = math.max(10, math.floor((bottom.w - pad * 2 - gap) / 2))
  local bh = math.max(14, math.min(math.max(ui.buttonH - 4, args.sv(18)), math.floor(bottom.h * 0.30)))
  local x1 = bottom.x + pad
  local x2 = x1 + bw + gap
  local y1 = bottom.y + args.sv(24)
  local y2 = y1 + bh + math.max(2, args.sv(6))

  args.drawButton("MANUAL_FUEL", x1, y1, bw, bh, state.manualFuel and "[F CLOSE]" or "[F OPEN]", "orange", true)
  args.drawButton("FILL_HOHLRAUM", x2, y1, bw, bh, "[HOHL]", "purple", true)
  args.drawButton("PROFILE_PREV", x1, y2, bw, bh, "[P-]", "purple", true)
  args.drawButton("PROFILE_NEXT", x2, y2, bw, bh, "[P+]", "purple", true)
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
