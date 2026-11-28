-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 table/build_industry.h, industry_cmd.cpp
-- GetScaledIndustryGenerationProbability, GetNumberOfIndustries,
-- GetScaledProbabilities and GenerateIndustries. This is the vanilla
-- selection order; PlaceInitialIndustry is supplied by the world host.
local I={}
local floor,ceil,min=math.floor,math.ceil,math.min
local landscape={temperate=2,arctic=3,tropic=4,toyland=5}
local densities={[0]=0,0,10,25,55,80,0}
-- Name, four mapgen weights, coastline scaling, built on water.
I.registry={
  [0]={"coal_mine",8,8,0,0,false,false},
  {"power_station",5,5,0,0,false,false},
  {"sawmill",5,0,0,0,false,false},
  {"forest",5,5,0,0,false,false},
  {"oil_refinery",4,4,4,0,true,false},
  {"oil_rig",0,0,0,0,true,true},
  {"factory",5,0,0,0,false,false},
  {"printing_works",0,5,0,0,false,false},
  {"steel_mill",5,0,0,0,false,false},
  {"farm",9,9,0,0,false,false},
  {"copper_mine",0,0,4,0,false,false},
  {"oil_well",4,5,5,0,false,false},
  {"bank",0,0,0,0,false,false},
  {"food_process",0,3,4,0,false,false},
  {"paper_mill",0,5,0,0,false,false},
  {"gold_mine",0,4,0,0,false,false},
  {"bank2",0,6,5,0,false,false},
  {"diamond_mine",0,0,4,0,false,false},
  {"iron_mine",5,0,0,0,false,false},
  {"fruit_plantation",0,0,4,0,false,false},
  {"rubber_plantation",0,0,4,0,false,false},
  {"water_supply",0,0,4,0,false,false},
  {"water_tower",0,0,8,0,false,false},
  {"factory2",0,0,4,0,false,false},
  {"farm2",0,0,2,0,false,false},
  {"lumber_mill",0,0,0,0,false,false},
  {"cotton_candy",0,0,0,5,false,false},
  {"candy_factory",0,0,0,5,false,false},
  {"battery_farm",0,0,0,4,false,false},
  {"cola_wells",0,0,0,5,false,false},
  {"toy_shop",0,0,0,4,false,false},
  {"toy_factory",0,0,0,5,false,false},
  {"plastic_fountain",0,0,0,5,false,false},
  {"fizzy_drink",0,0,0,4,false,false},
  {"bubble_generator",0,0,0,5,false,false},
  {"toffee_quarry",0,0,0,5,false,false},
  {"sugar_mine",0,0,0,4,false,false},
}
I.LAST_ID=36
local function density(opts) return opts.editor and 2 or opts.density or 4 end
function I.count(board,opts)
  local d=density(opts)
  if d==6 then return min(64000,assert(opts.custom_count)) end
  return min(64000,ceil(assert(densities[d])*board.width*board.height/65536))
end
function I.probability(board,id,opts,water)
  local rule=I.registry[id]
  if not rule or opts.enabled and opts.enabled[id]==false or density(opts)==0
      or water~=nil and rule[7]~=water then return 0,false end
  local weight=rule[assert(landscape[opts.landscape or "temperate"])]*16
  local chance=rule[6] and ceil(weight*(board.width+board.height)/512)
    or ceil(weight*board.width*board.height/65536)
  return chance,chance>0 and not opts.editor
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
