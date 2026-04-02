local M = {}

local function isCompact5x5(ui)
  local mode = tostring((ui and ui.overviewScreenClass) or (ui and ui.overviewResponsiveMode) or "")
  return mode == "compact_5x5"
end

local function drawCompact5x5(args)
  local r = args.rect
  local data = args.data
  local ui = args.ui
  local colors = args.colors
  local state = args.state
  local splitVertical = args.splitVertical
  local drawPanel = args.drawPanel
  local drawToggleRow = args.drawToggleRow
  local drawButton = args.drawButton
  local drawText = args.drawText
  local drawTextRight = args.drawTextRight
  local drawImageStack = args.drawImageStack
  local sv = args.sv
  local gpu = args.gpu
  local safeFilledRect = args.safeFilledRect or function(x, y, w, h, color)
    gpu.filledRectangle(x, y, w, h, color)
  end
  local safeRectangle = args.safeRectangle or function(x, y, w, h, color)
    gpu.rectangle(x, y, w, h, color)
  end
  local activeGpuName = args.activeGpuName
  local gpuMode = args.gpuMode

  local top, bottom = splitVertical(r, 0.56)
  drawPanel(top.x, top.y, top.w, top.h, "SYSTEM")
  local rowY = top.y + sv(28)
  local step = math.max(8, sv(10))
  local rows = {
    { label = "GPU", value = activeGpuName, color = colors.cyan },
    { label = "SCREEN", value = tostring(ui.sw) .. "x" .. tostring(ui.sh), color = colors.text },
    { label = "MODE", value = tostring(gpuMode), color = colors.text },
    { label = "LOGIC", value = data.logicPresent and "ONLINE" or "OFFLINE", color = data.logicPresent and colors.green or colors.red },
    { label = "IND", value = data.inductionPresent and "ONLINE" or "OFFLINE", color = data.inductionPresent and colors.green or colors.red },
    { label = "MSG", value = state.message, color = colors.green },
  }
  local maxRows = math.max(1, math.floor((top.h - (rowY - top.y) - sv(24)) / step))
  for i = 1, math.min(maxRows, #rows) do
    local row = rows[i]
    drawToggleRow(top, rowY + (i - 1) * step, row.label, row.value, row.color)
  end

  local refreshY = top.y + top.h - math.max(14, sv(18)) - ui.smallPad
  drawButton("RELOAD_ASSETS", top.x + ui.pad, refreshY, top.w - ui.pad * 2, math.max(14, sv(18)), "[RELOAD]", "cyan", true)

  drawPanel(bottom.x, bottom.y, bottom.w, bottom.h, "VISUAL")
  local innerX = bottom.x + ui.pad
  local innerY = bottom.y + sv(22)
  local innerW = bottom.w - ui.pad * 2
  local innerH = bottom.h - sv(30)
  safeFilledRect(innerX, innerY, innerW, innerH, colors.white)
  safeRectangle(innerX, innerY, innerW, innerH, colors.border)
  drawImageStack(innerX + ui.smallPad, innerY + ui.smallPad, innerW - ui.smallPad * 2, innerH - ui.smallPad * 2, data)

  local infoY = innerY + innerH - sv(20)
  drawText(innerX + ui.smallPad, infoY, "LOGIC", colors.text, 1)
  drawTextRight(innerX + innerW - ui.smallPad, infoY, data.logicMode, colors.cyan, 1)
end

function M.draw(args)
  local r = args.rect
  local data = args.data
  local ui = args.ui
  local colors = args.colors
  local state = args.state
  local splitVertical = args.splitVertical
  local splitHorizontal = args.splitHorizontal
  local drawPanel = args.drawPanel
  local drawToggleRow = args.drawToggleRow
  local drawButton = args.drawButton
  local drawText = args.drawText
  local drawTextRight = args.drawTextRight
  local drawImageStack = args.drawImageStack
  local sv = args.sv
  local gpu = args.gpu
  local safeFilledRect = args.safeFilledRect or function(x, y, w, h, color)
    gpu.filledRectangle(x, y, w, h, color)
  end
  local safeRectangle = args.safeRectangle or function(x, y, w, h, color)
    gpu.rectangle(x, y, w, h, color)
  end
  local activeGpuName = args.activeGpuName
  local gpuMode = args.gpuMode

  if isCompact5x5(ui) then
    drawCompact5x5(args)
    return
  end

  local left, right
  if ui.compact then
    left, right = splitVertical(r, 0.50)
  else
    left, right = splitHorizontal(r, 0.50)
  end

  drawPanel(left.x, left.y, left.w, left.h, "SYSTEM INFO")
  local rowY = left.y + sv(54)
  drawToggleRow(left, rowY, "GPU", activeGpuName, colors.cyan)
  drawToggleRow(left, rowY + sv(18), "SCREEN", tostring(ui.sw) .. "x" .. tostring(ui.sh), colors.text)
  drawToggleRow(left, rowY + sv(36), "MODE", tostring(gpuMode), colors.text)
  drawToggleRow(left, rowY + sv(54), "LOGIC", data.logicPresent and "ONLINE" or "OFFLINE", data.logicPresent and colors.green or colors.red)
  drawToggleRow(left, rowY + sv(72), "INDUCTION", data.inductionPresent and "ONLINE" or "OFFLINE", data.inductionPresent and colors.green or colors.red)
  drawToggleRow(left, rowY + sv(90), "AMPLIFIER", data.amplifierPresent and "ONLINE" or "OFFLINE", data.amplifierPresent and colors.green or colors.red)
  drawToggleRow(left, rowY + sv(108), "LASER", data.laserPresent and "ONLINE" or "OFFLINE", data.laserPresent and colors.green or colors.red)
  drawToggleRow(left, rowY + sv(126), "FLOW IN/OUT", data.energyFlowIn .. " / " .. data.energyFlowOut, colors.text)
  drawToggleRow(left, rowY + sv(144), "TRANSFER CAP", data.transferCapText, colors.text)
  drawToggleRow(left, rowY + sv(162), "MESSAGE", state.message, colors.green)

  local refreshY = left.y + left.h - sv(56)
  local bw = left.w - ui.pad * 2
  drawButton("RELOAD_ASSETS", left.x + ui.pad, refreshY, bw, math.max(ui.buttonH, sv(36)), "[RELOAD ASSETS]", "cyan", true)

  drawPanel(right.x, right.y, right.w, right.h, "VISUAL CHECK")
  local innerX = right.x + ui.pad
  local innerY = right.y + sv(38)
  local innerW = right.w - ui.pad * 2
  local innerH = right.h - sv(46)
  safeFilledRect(innerX, innerY, innerW, innerH, colors.white)
  safeRectangle(innerX, innerY, innerW, innerH, colors.border)
  drawImageStack(innerX + ui.smallPad, innerY + ui.smallPad, innerW - ui.smallPad * 2, innerH - ui.smallPad * 2, data)

  local infoBaseY = innerY + innerH - sv(74)
  drawText(innerX + ui.smallPad, infoBaseY, "LOGIC MODE", colors.text, 1)
  drawTextRight(innerX + innerW - ui.smallPad, infoBaseY, data.logicMode, colors.cyan, 1)
  drawText(innerX + ui.smallPad, infoBaseY + sv(18), "ACTIVE COOL", colors.text, 1)
  drawTextRight(innerX + innerW - ui.smallPad, infoBaseY + sv(18), data.activeCooled and "ON" or "OFF", data.activeCooled and colors.cyan or colors.muted, 1)
  drawText(innerX + ui.smallPad, infoBaseY + sv(36), "ENV LOSS", colors.text, 1)
  drawTextRight(innerX + innerW - ui.smallPad, infoBaseY + sv(36), data.environmentalLossText, colors.orange, 1)
  drawText(innerX + ui.smallPad, infoBaseY + sv(54), "XFER LOSS", colors.text, 1)
  drawTextRight(innerX + innerW - ui.smallPad, infoBaseY + sv(54), data.transferLossText, colors.orange, 1)
end

return M
