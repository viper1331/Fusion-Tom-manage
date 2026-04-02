-- Stable project entrypoint.
local ENTRYPOINT_IMPL = "start_menu_pages_live_v7_impl.lua"
local RuntimeEntrypoint = assert(dofile("core/app/runtime_entrypoint.lua"))

RuntimeEntrypoint.run({
  entrypoint = ENTRYPOINT_IMPL,
  terrainBoot = "terrain/boot.lua",
  configPath = "fusion_config.lua",
  defaultsPath = "terrain/agent_config.lua",
})
