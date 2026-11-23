-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 industry_cmd.cpp DoCreateNewIndustry: RC1 stores
-- only the output slots through the last valid cargo. The older 14.1
-- world generator used sixteen slots; don't consume those extra draws.
local function initialize(ind,seed_bits,random,original)
  local floor=math.floor
  local function vary(q)
    local draw=floor(random()/16777216)
    q.rate=math.min(255,floor((128+draw)*q.rate/256))
  end
  local out=ind.produced
  if not original and out then
    if out.rate then vary(out)
    else
      local last=#out
      while last>0 and not out[last].cargo do last=last-1 end
      for i=1,last do vary(out[i]) end
    end
  end
  local r=random()%65536
  ind.random_colour,ind.counter,ind.random=r%16,floor(r/16),seed_bits
  ind.construction_type="gameplay"
  for _,tile in ipairs(ind.tiles) do
    tile.stage,tile.construction_counter,tile.completed=0,0,false
    tile.random_bits=random()%256
  end
  return ind
end
return initialize
