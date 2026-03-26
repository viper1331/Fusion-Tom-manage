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

function M.isHttpEnabled()
  return type(http) == "table" and type(http.get) == "function"
end

function M.buildRawUrl(source, relativePath)
  local rel = normalizePath(relativePath)
  local rawBaseUrl = source and source.rawBaseUrl

  if type(rawBaseUrl) == "string" and rawBaseUrl ~= "" then
    return normalizeUrl(rawBaseUrl) .. "/" .. rel
  end

  local owner = source and source.owner or ""
  local repo = source and source.repo or ""
  local branch = source and source.branch or "main"
  return "https://raw.githubusercontent.com/" .. owner .. "/" .. repo .. "/" .. branch .. "/" .. rel
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

function M.downloadFile(source, relativePath, destinationPath, entry)
  local url = M.buildRawUrl(source, relativePath)
  local payload, err = M.fetchBinary(url)
  if not payload then
    return nil, "download failed for " .. tostring(relativePath) .. ": " .. tostring(err)
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
    local destination = fs.combine(targetDir, normalizedPath)
    local downloaded, err = M.downloadFile(source, normalizedPath, destination, entry)
    if not downloaded then
      return nil, err
    end

    if type(entry.size) == "number" and entry.size >= 0 and downloaded.size ~= entry.size then
      return nil, "size mismatch for " .. tostring(normalizedPath)
    end

    out[#out + 1] = downloaded
    if logger then
      logger("downloaded " .. tostring(downloaded.path) .. " (" .. tostring(downloaded.size) .. " bytes)")
      if downloaded.hash then
        logger("integrity hint present for " .. tostring(downloaded.path) .. " (" .. tostring(downloaded.hashAlgo or "hash") .. ", verification pending implementation)")
      end
    end
  end

  return out
end

return M
