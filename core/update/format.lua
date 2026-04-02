local M = {}

function M.shortCommit(commit, length)
  local value = type(commit) == "string" and commit or ""
  if value == "" or value == "n/a" then
    return "n/a"
  end

  local size = math.max(4, math.floor(tonumber(length) or 8))
  if #value <= size then
    return value
  end
  return string.sub(value, 1, size)
end

return M

