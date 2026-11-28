-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 industry_cmd.cpp DoCreateNewIndustry, for stock
-- industry construction after the platform has already been handled.
local R={}
local floor,min=math.floor,math.min
function R.draw(plan,spec,random,original,generating_world)
  local used=0
  for i,p in ipairs(spec.produce) do if p.cargo then used=i end end
  plan.production_raw={}
  if not original then
    for i=1,used do plan.production_raw[i]=random() end
  end
  local r=random()%65536
  plan.random_colour,plan.counter=r%16,floor(r/16)
  plan.selected_layout=plan.layout+1
  for _,tile in ipairs(plan.cells) do
    tile.random_bits=random()%256
    tile.stage,tile.construction_counter,tile.completed=generating_world and 2 or 0,generating_world and 3 or 0,false
  end
  -- The vanilla construction callback still evaluates the RNG argument
  -- for every physical cell. Its row-major order does not change any
  -- local tile or industry random bits without NewGRF callbacks.
  for _=1,#plan.cells do random() end
  return plan
end
function R.rate(base,raw)
  if raw==nil then return base end
  return min(255,floor((128+floor(raw/16777216))*base/256))
end
return R
