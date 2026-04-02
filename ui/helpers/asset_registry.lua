local M = {}

local function cloneVariants(list)
  local out = {}
  for i = 1, #list do
    local item = list[i]
    out[#out + 1] = {
      name = item.name,
      path = item.path,
    }
  end
  return out
end

-- Runtime reactor tiers are trim variants from micro to large.
-- reactor_top.png is kept as a legacy/base fallback only.
local REACTOR_VARIANTS = {
  { name = "trim_micro",  path = "assets/reactor_top_trim_micro.png"  },
  { name = "trim_tiny",   path = "assets/reactor_top_trim_tiny.png"   },
  { name = "trim_xsmall", path = "assets/reactor_top_trim_xsmall.png" },
  { name = "trim_small2", path = "assets/reactor_top_trim_small2.png" },
  { name = "trim_small",  path = "assets/reactor_top_trim_small.png"  },
  { name = "trim_medium", path = "assets/reactor_top_trim_medium.png" },
  { name = "trim_large",  path = "assets/reactor_top_trim_large.png"  },
  { name = "base",        path = "assets/reactor_top.png"             },
}

local LASER_MODULE_VARIANTS = {
  { name = "micro",   path = "assets/laser_module_micro.png"   },
  { name = "tiny",    path = "assets/laser_module_tiny.png"    },
  { name = "xsmall",  path = "assets/laser_module_xsmall.png"  },
  { name = "small2",  path = "assets/laser_module_small2.png"  },
  { name = "small",   path = "assets/laser_module_small.png"   },
  { name = "medium",  path = "assets/laser_module_medium.png"  },
  { name = "large",   path = "assets/laser_module_large.png"   },
}

-- Kept in repository for historical/manual usage; not used by runtime loader.
M.RUNTIME_EXCLUDED = {
  "assets/module laser.png",
}

function M.getReactorVariants()
  return cloneVariants(REACTOR_VARIANTS)
end

function M.getLaserModuleVariants()
  return cloneVariants(LASER_MODULE_VARIANTS)
end

return M
