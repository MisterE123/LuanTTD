-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 table/build_industry.h, industry_cmd.cpp
-- GetScaledIndustryGenerationProbability, GetNumberOfIndustries,
-- GetScaledProbabilities and GenerateIndustries. This is the vanilla
-- selection order; PlaceInitialIndustry is supplied by the world host.
local I={}
local floor,ceil,min=math.floor,math.ceil,math.min
local landscape={temperate=1,arctic=2,tropic=3,toyland=4}
local densities={[0]=0,0,10,25,55,80,0}
local dir=(core and core.get_modpath and core.get_modpath("luanttd_core").."/openttd/") or "mods/luanttd_core/openttd/"
local Stock=dofile(dir.."stock_industry_specs_rc1.lua")
I.registry=Stock.industry
I.LAST_ID=36
local function density(opts) return opts.editor and 2 or opts.density or 4 end
function I.count(board,opts)
  local d=density(opts)
  if d==6 then return min(64000,assert(opts.custom_count)) end
  return min(64000,ceil(assert(densities[d])*board.width*board.height/65536))
end
function I.probability(board,id,opts,water)
  local rule=I.registry[id]
  if not rule or opts.enabled and opts.enabled[id]==false or density(opts)==0 then return 0,false end
  local built_on_water,skip_force=false,false
  for _,b in ipairs(rule[14]) do
    if b=="BuiltOnWater" then built_on_water=true end
    if b=="NoBuildMapCreation" then skip_force=true end
  end
  if water~=nil and built_on_water~=water then return 0,false end
  local weight=rule[5][assert(landscape[opts.landscape or "temperate"])]*16
  local coastal=rule[8]=="Refinery" or rule[8]=="OilRig"
  local chance=coastal and ceil(weight*(board.width+board.height)/512)
    or ceil(weight*board.width*board.height/65536)
  return chance,chance>0 and not opts.editor and not skip_force
end
function I.probabilities(board,opts,water)
  local probs,forced={},{}
  local total=0
  for id=0,I.LAST_ID do
    local p,f=I.probability(board,id,opts,water)
    probs[id]=p
    total=total+p
    if f then forced[#forced+1]=id end
  end
  return {weights=probs,total=total,forced=forced,water=water}
end
-- Stock RandomTile, then CreateNewIndustry's three input draws.
-- The attempt consumes these even when its quote is rejected.
function I.candidate(width,height,variants,random)
  local tile=random()%(width*height)
  local seed,bits=random(),random()%65536
  local layout=floor(variants*random()/4294967296)
  return tile%width,floor(tile/width),seed,bits,layout
end
function I.generate(board,opts,random,place,progress,reset)
  if density(opts)==0 then return end
  local land,water=I.probabilities(board,opts,false),I.probabilities(board,opts,true)
  local all=land.total+water.total
  local desired=I.count(board,opts)
  for _,p in ipairs{land,water} do
    local amount=all>0 and floor(p.total*desired/all) or 0
    if not p.water and opts.density~=6 then
      amount=floor(amount*assert(board.initial_land_count)/(board.width*board.height))
    end
    if p.total==0 or amount<#p.forced then amount=#p.forced end
    if progress then progress(p.water,amount,#p.forced) end
    for _,id in ipairs(p.forced) do place(id,p.water,true) end
    for _=#p.forced+1,amount do
      local r=floor(p.total*random()/4294967296)
      local id=0
      while r>=p.weights[id] do r=r-p.weights[id];id=id+1 end
      place(id,p.water,false)
    end
  end
  if reset then reset() end
end
return I
