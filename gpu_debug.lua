local function inspectGpu(name)
  print("================================")
  print("GPU:", name)

  local gpu = peripheral.wrap(name)
  if not gpu then
    print("wrap impossible")
    return
  end

  gpu.refreshSize()

  local pxW, pxH, blockW, blockH, scale = gpu.getSize()
  print("Pixels :", pxW, pxH)
  print("Blocks :", blockW, blockH)
  print("Scale  :", scale)

  gpu.fill(0xFF000022)
  gpu.drawText(4, 4, "GPU: " .. name, 0xFFFFFFFF)
  gpu.drawText(4, 20, "Pixels: " .. tostring(pxW) .. "x" .. tostring(pxH), 0xFFFFFFFF)
  gpu.drawText(4, 36, "Blocks: " .. tostring(blockW) .. "x" .. tostring(blockH), 0xFFFFFFFF)
  gpu.drawText(4, 52, "Scale: " .. tostring(scale), 0xFFFFFFFF)
  gpu.sync()
end

inspectGpu("tm_gpu_1")
sleep(2)
inspectGpu("tm_gpu_2")
sleep(2)
inspectGpu("tm_gpu_3")