local M = {}

local function startsWith(value, prefix)
  return string.sub(value, 1, #prefix) == prefix
end

local function collectByPrefix(prefix)
  local out = {}
  local names = peripheral.getNames()
  table.sort(names)
  for _, name in ipairs(names) do
    if startsWith(name, prefix) then
      out[#out + 1] = name
    end
  end
  return out
end

function M.run(harness, context)
  local groups = {
    fusionReactorLogicAdapter = collectByPrefix("fusionReactorLogicAdapter"),
    inductionPort = collectByPrefix("inductionPort"),
    laserAmplifier = collectByPrefix("laserAmplifier"),
    blockReader = collectByPrefix("block_reader"),
    redstoneRelay = collectByPrefix("redstone_relay"),
    tmGpu = context.tmGpuNames,
    monitor = context.monitorNames,
  }

  for group, names in pairs(groups) do
    harness:note("peripheral group snapshot", {
      group = group,
      count = #names,
      names = names,
    })
  end

  harness:assertTrue("logic_adapter_present", #groups.fusionReactorLogicAdapter > 0, #groups.fusionReactorLogicAdapter > 0 and "logic adapter detected" or "logic adapter missing", groups.fusionReactorLogicAdapter)
  harness:assertTrue("induction_present", #groups.inductionPort > 0, #groups.inductionPort > 0 and "induction detected" or "induction missing", groups.inductionPort)
  harness:assertTrue("laser_amp_present", #groups.laserAmplifier > 0, #groups.laserAmplifier > 0 and "laser amplifier detected" or "laser amplifier missing", groups.laserAmplifier)
end

return M
