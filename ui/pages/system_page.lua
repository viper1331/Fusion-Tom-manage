local M = {}

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
  local activeGpuName = args.activeGpuName
  local gpuMode = args.gpuMode

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
  gpu.filledRectangle(innerX, innerY, innerW, innerH, colors.white)
  gpu.rectangle(innerX, innerY, innerW, innerH, colors.border)
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
