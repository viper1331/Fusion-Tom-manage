return {
  ui = {
    startPage = "OVERVIEW",
  },
  devices = {
    gpu = "tm_gpu_3",
    fusionController = "mekanismgenerators:fusion_reactor_controller_3",
    modem = "back",
    readers = {
      tritium = "block_reader_2",
      deuterium = "block_reader_1",
      dtFuel = "block_reader_9",
      active = "block_reader_7",
    },
    laser = "laser_0",
    laserAmplifier = "laserAmplifier_1",
    induction = "inductionPort_1",
    logic = "fusionReactorLogicAdapter_0",
    relays = {
      laserCharge = "redstone_relay_0",
      deuteriumTank = "redstone_relay_1",
      tritiumTank = "redstone_relay_2",
      aux = "redstone_relay_3",
    },
  },
  control = {
    laserModuleCount = 8,
    relaySides = {
      laserCharge = "",
      deuteriumTank = "",
      tritiumTank = "",
      aux = "",
    },
    laserPulseSeconds = 0.15,
    telemetryPollMs = 500,
    relayAnalogStrength = 15,
  },
  update = {
    channel = "stable",
    owner = "viper1331",
    repo = "Fusion-Tom-manage",
    branch = "main",
    manifestPath = "fusion.manifest.json",
    rawBaseUrl = "",
    integrityMode = "size-only",
    requireConfirmApply = true,
    autoCheckOnStartup = false,
  },
}
