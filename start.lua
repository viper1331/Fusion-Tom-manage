-- Stable project entrypoint.
local ENTRYPOINT_IMPL = "start_menu_pages_live_v7_impl.lua"

if shell and type(shell.run) == "function" then
  shell.run(ENTRYPOINT_IMPL)
else
  dofile(ENTRYPOINT_IMPL)
end
