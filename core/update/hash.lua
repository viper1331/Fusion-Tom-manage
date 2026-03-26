local M = {}

local bit = bit32
if not bit then
  error("bit32 library is required for sha256")
end

local band = bit.band
local bor = bit.bor
local bxor = bit.bxor
local bnot = bit.bnot
local rshift = bit.rshift
local lshift = bit.lshift
local rrotate = bit.rrotate

local MOD32 = 4294967296

local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local H0 = {
  0x6a09e667,
  0xbb67ae85,
  0x3c6ef372,
  0xa54ff53a,
  0x510e527f,
  0x9b05688c,
  0x1f83d9ab,
  0x5be0cd19,
}

local function add32(...)
  local sum = 0
  for i = 1, select("#", ...) do
    sum = (sum + (select(i, ...) % MOD32)) % MOD32
  end
  return sum
end

local function readU32BE(str, index)
  local b1, b2, b3, b4 = string.byte(str, index, index + 3)
  return bor(lshift(b1, 24), lshift(b2, 16), lshift(b3, 8), b4)
end

local function normalizeAlgo(algo)
  if type(algo) ~= "string" then
    return nil
  end
  algo = string.lower(algo)
  if algo == "" then
    return nil
  end
  return algo
end

local function sha256Binary(message)
  message = type(message) == "string" and message or tostring(message or "")

  local msgLen = #message
  local bitLen = msgLen * 8
  local hi = math.floor(bitLen / MOD32)
  local lo = bitLen % MOD32
  local padLen = (56 - ((msgLen + 1) % 64)) % 64

  local padded = message
    .. string.char(0x80)
    .. string.rep("\0", padLen)
    .. string.char(
      band(rshift(hi, 24), 0xFF),
      band(rshift(hi, 16), 0xFF),
      band(rshift(hi, 8), 0xFF),
      band(hi, 0xFF),
      band(rshift(lo, 24), 0xFF),
      band(rshift(lo, 16), 0xFF),
      band(rshift(lo, 8), 0xFF),
      band(lo, 0xFF)
    )

  local h = {
    H0[1], H0[2], H0[3], H0[4],
    H0[5], H0[6], H0[7], H0[8],
  }

  local w = {}
  for chunkStart = 1, #padded, 64 do
    for i = 0, 15 do
      w[i] = readU32BE(padded, chunkStart + i * 4)
    end

    for i = 16, 63 do
      local s0 = bxor(rrotate(w[i - 15], 7), rrotate(w[i - 15], 18), rshift(w[i - 15], 3))
      local s1 = bxor(rrotate(w[i - 2], 17), rrotate(w[i - 2], 19), rshift(w[i - 2], 10))
      w[i] = add32(w[i - 16], s0, w[i - 7], s1)
    end

    local a = h[1]
    local b = h[2]
    local c = h[3]
    local d = h[4]
    local e = h[5]
    local f = h[6]
    local g = h[7]
    local j = h[8]

    for i = 0, 63 do
      local s1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
      local ch = bxor(band(e, f), band(bnot(e), g))
      local temp1 = add32(j, s1, ch, K[i + 1], w[i])
      local s0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
      local maj = bxor(band(a, b), band(a, c), band(b, c))
      local temp2 = add32(s0, maj)

      j = g
      g = f
      f = e
      e = add32(d, temp1)
      d = c
      c = b
      b = a
      a = add32(temp1, temp2)
    end

    h[1] = add32(h[1], a)
    h[2] = add32(h[2], b)
    h[3] = add32(h[3], c)
    h[4] = add32(h[4], d)
    h[5] = add32(h[5], e)
    h[6] = add32(h[6], f)
    h[7] = add32(h[7], g)
    h[8] = add32(h[8], j)
  end

  return string.format(
    "%08x%08x%08x%08x%08x%08x%08x%08x",
    h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
  )
end

function M.isSupportedAlgo(algo)
  return normalizeAlgo(algo or "sha256") == "sha256"
end

function M.hashBytes(data, algo)
  local normalizedAlgo = normalizeAlgo(algo or "sha256")
  if normalizedAlgo ~= "sha256" then
    return nil, "unsupported hash algorithm: " .. tostring(algo)
  end

  return sha256Binary(data), normalizedAlgo
end

function M.hashFile(path, algo)
  path = tostring(path or "")
  if path == "" then
    return nil, "invalid file path"
  end

  if not fs.exists(path) then
    return nil, "file missing: " .. tostring(path)
  end

  local fh = fs.open(path, "rb")
  if not fh then
    return nil, "cannot open file: " .. tostring(path)
  end

  local payload = fh.readAll() or ""
  fh.close()

  return M.hashBytes(payload, algo)
end

return M
