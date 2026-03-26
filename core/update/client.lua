local M = {}

local function normalizePath(path)
  path = tostring(path or "")
  path = string.gsub(path, "\\", "/")
  path = string.gsub(path, "^%./", "")
  path = string.gsub(path, "^/", "")
  return path
end

local function ensureParent(path)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function normalizeUrl(url)
  url = tostring(url or "")
  while string.sub(url, -1) == "/" do
    url = string.sub(url, 1, #url - 1)
  end
  return url
end

local function nonEmpty(value)
  if type(value) == "string" and value ~= "" then
    return value
  end
  return nil
end

local function resolveSourceRef(source)
  local commit = nonEmpty(source and source.commit)
  if commit then
    return commit
  end

  local branch = nonEmpty(source and source.branch)
  if branch then
    return branch
  end

  return "main"
end

local function buildTemplateBaseUrl(source)
  local base = normalizeUrl(source and source.rawBaseUrl or "")
  local owner = tostring(source and source.owner or "")
  local repo = tostring(source and source.repo or "")
  local branch = tostring(nonEmpty(source and source.branch) or "main")
  local commit = tostring(nonEmpty(source and source.commit) or "")
  local ref = tostring(resolveSourceRef(source))

  base = string.gsub(base, "{owner}", owner)
  base = string.gsub(base, "{repo}", repo)
  base = string.gsub(base, "{branch}", branch)
  base = string.gsub(base, "{commit}", commit)
  base = string.gsub(base, "{ref}", ref)
  return base
end

local function isUnreservedByte(byte)
  return (byte >= 48 and byte <= 57) -- 0-9
    or (byte >= 65 and byte <= 90)   -- A-Z
    or (byte >= 97 and byte <= 122)  -- a-z
    or byte == 45                    -- -
    or byte == 46                    -- .
    or byte == 95                    -- _
    or byte == 126                   -- ~
end

local function encodePathSegment(segment)
  local out = {}
  for i = 1, #segment do
    local byte = string.byte(segment, i)
    if isUnreservedByte(byte) then
      out[#out + 1] = string.char(byte)
    else
      out[#out + 1] = string.format("%%%02X", byte)
    end
  end
  return table.concat(out)
end

local function encodeRelativePathForUrl(path)
  local normalized = normalizePath(path)
  if normalized == "" then
    return ""
  end

  local encodedParts = {}
  for part in string.gmatch(normalized, "[^/]+") do
    encodedParts[#encodedParts + 1] = encodePathSegment(part)
  end
  return table.concat(encodedParts, "/")
end

function M.isHttpEnabled()
  return type(http) == "table" and type(http.get) == "function"
end

function M.buildRawUrl(source, relativePath)
  local rel = encodeRelativePathForUrl(relativePath)
  local rawBaseUrl = source and source.rawBaseUrl

  if type(rawBaseUrl) == "string" and rawBaseUrl ~= "" then
    return buildTemplateBaseUrl(source) .. "/" .. rel
  end

  local owner = source and source.owner or ""
  local repo = source and source.repo or ""
  local ref = resolveSourceRef(source)
  return "https://raw.githubusercontent.com/" .. owner .. "/" .. repo .. "/" .. ref .. "/" .. rel
end

function M.fetch(url, binary)
  if not M.isHttpEnabled() then
    return nil, "http disabled (enable HTTP in ComputerCraft)"
  end

  local ok, responseOrNil, err = pcall(http.get, url, nil, binary == true)
  if not ok then
    return nil, "http failure: " .. tostring(responseOrNil)
  end
  if not responseOrNil then
    return nil, "http request failed: " .. tostring(err or "unknown")
  end

  local response = responseOrNil
  local code = response.getResponseCode and response.getResponseCode() or 200
  local body = response.readAll() or ""
  response.close()

  if code >= 400 then
    return nil, "http " .. tostring(code)
  end

  return body, nil, code
end

function M.fetchText(url)
  return M.fetch(url, false)
end

function M.fetchBinary(url)
  return M.fetch(url, true)
end

function M.downloadFile(source, relativePath, destinationPath, entry, resolvedUrl)
  local url = resolvedUrl or M.buildRawUrl(source, relativePath)
  local payload, err = M.fetchBinary(url)
  if not payload then
    return nil, "download failed for " .. tostring(relativePath) .. ": " .. tostring(err) .. " (url=" .. tostring(url) .. ")"
  end

  ensureParent(destinationPath)
  local fh = fs.open(destinationPath, "wb")
  if not fh then
    return nil, "cannot open destination: " .. tostring(destinationPath)
  end
  fh.write(payload)
  fh.close()

  return {
    path = normalizePath(relativePath),
    size = #payload,
    url = url,
    hash = type(entry) == "table" and entry.hash or nil,
    hashAlgo = type(entry) == "table" and entry.hashAlgo or nil,
  }
end

function M.downloadFiles(source, fileEntries, targetDir, logger)
  if type(fileEntries) ~= "table" then
    return nil, "invalid file list for download"
  end

  if type(targetDir) ~= "string" or targetDir == "" then
    return nil, "invalid download target directory"
  end

  if not fs.exists(targetDir) then
    fs.makeDir(targetDir)
  end

  local out = {}
  for i, entry in ipairs(fileEntries) do
    local relativePath = type(entry) == "table" and entry.path or nil
    if type(relativePath) ~= "string" or relativePath == "" then
      return nil, "invalid entry path at index " .. tostring(i)
    end

    local normalizedPath = normalizePath(relativePath)
    local requestedUrl = M.buildRawUrl(source, normalizedPath)
    if logger then
      logger("downloading " .. tostring(normalizedPath) .. " <- " .. tostring(requestedUrl))
    end
    local destination = fs.combine(targetDir, normalizedPath)
    local downloaded, err = M.downloadFile(source, normalizedPath, destination, entry, requestedUrl)
    if not downloaded then
      return nil, err
    end

    if type(entry.size) == "number" and entry.size >= 0 and downloaded.size ~= entry.size then
      local mismatch = "size mismatch for " .. tostring(normalizedPath)
        .. ": expected=" .. tostring(entry.size)
        .. ", received=" .. tostring(downloaded.size)
        .. ", url=" .. tostring(downloaded.url)
      if logger then
        logger(mismatch)
      end
      return nil, mismatch
    end

    out[#out + 1] = downloaded
    if logger then
      logger("downloaded " .. tostring(downloaded.path) .. " (" .. tostring(downloaded.size) .. " bytes) from " .. tostring(downloaded.url))
      if downloaded.hash then
        logger("integrity hint present for " .. tostring(downloaded.path) .. " (" .. tostring(downloaded.hashAlgo or "hash") .. ", verification pending implementation)")
      end
    end
  end

  return out
end

return M
