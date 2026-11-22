-- Port of OpenTTD 14.1 src/townname.cpp (English Original and the world-generation
-- TownNames set path) and src/table/townname.h (part tables).
-- OpenTTD is free software under the GNU General Public License version 2,
-- without any warranty; see COPYING.OpenTTD.md. SPDX-License-Identifier: GPL-2.0-only
local N = {MAX_CHARS = 32, MAX_ATTEMPTS = 1000}
local floor = math.floor
local parts = {
  {"Great ", "Little ", "New ", "Fort "},
  {"Wr", "B", "C", "Ch", "Br", "D", "Dr", "F", "Fr", "Fl", "G", "Gr", "H",
   "L", "M", "N", "P", "Pr", "Pl", "R", "S", "S", "Sl", "T", "Tr", "W"},
  {"ar", "a", "e", "in", "on", "u", "un", "en"},
  {"n", "ning", "ding", "d", "", "t", "fing"},
  {"ville", "ham", "field", "ton", "town", "bridge", "bury", "wood", "ford",
   "hall", "ston", "way", "stone", "borough", "ley", "head", "bourne", "pool",
   "worth", "hill", "well", "hattan", "burg"},
  {"-on-sea", " Bay", " Market", " Cross", " Bridge", " Falls", " City",
   " Ridge", " Springs"},
}
local corrections = {
  Cunt="East", Slag="Pits", Slut="Edin", Drar="Quar", Dreh="Bash",
  Frar="Shor", Grar="Aber", Brar="Over", Wrar="Inve",
}

-- SeedChance: use the 16 bits at the requested shift, then take the
-- high 16 bits of the product, not a modulo by the number of spellings.
local function chance(seed, shift, max)
  return floor((floor(seed / 2^shift) % 65536) * max / 65536)
end

function N.display(seed)
  assert(type(seed)=="number" and seed>=0 and seed<4294967296 and seed==floor(seed),
    "OpenTTD town nameparts require an unsigned 32-bit integer")
  local i = chance(seed, 0, #parts[1]+50)-50
  local j = chance(seed, 15, #parts[6]+60)-60
  local name = (parts[1][i+1] or "") ..
    parts[2][chance(seed, 4, #parts[2])+1] ..
    parts[3][chance(seed, 7, #parts[3])+1] ..
    parts[4][chance(seed, 10, #parts[4])+1] ..
    parts[5][chance(seed, 13, #parts[5])+1] ..
    (parts[6][j+1] or "")
  if name:sub(1,2)=="Ce" or name:sub(1,2)=="Ci" then name="K"..name:sub(2) end
  -- Replacement is at the very beginning of the full name (including an
  -- optional prefix). The stock English Original replacements cannot cascade.
  local replacement = corrections[name:sub(1,4)]
  return replacement and replacement..name:sub(5) or name
end

-- The world-generation set is both input and output; accepted names count
-- before the caller even tries to place the town. For the stock last resort,
-- pass a fresh set seeded only with actual towns, not failed reservations.
function N.generate(used, random)
  assert(type(used)=="table" and type(random)=="function", "expected town name set and Next() callback")
  for _ = 1, N.MAX_ATTEMPTS do
    local seed = random()
    local name = N.display(seed)
    -- Every character of this original-English table is ASCII.
    if #name < N.MAX_CHARS and used[name] == nil then
      used[name] = true
      return seed, name
    end
  end
  return nil, nil
end

return N
