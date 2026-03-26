-- Legacy compatibility shim.
local STABLE_ENTRYPOINT = "start.lua"

if shell and type(shell.run) == "function" then
  shell.run(STABLE_ENTRYPOINT)
else
  dofile(STABLE_ENTRYPOINT)
end
