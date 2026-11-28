-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 table/build_industry.h and
-- table/cargo_const.h. Bind the exact climate records to the existing
-- stock industry accounting, rather than a second water/food economy.
local directory=(core and core.get_modpath and core.get_modpath("luanttd_core").."/openttd/") or "mods/luanttd_core/openttd/"
local Geometry=dofile(directory.."industry_footprint_rc1.lua")
local Layout=dofile(directory.."stock_industry_layouts_rc1.lua")
local Stock=dofile(directory.."industry_spec_rc1.lua")
local life={Organic="organic",Extractive="extractive",Processing="processing",INDUSTRYLIFE_BLACK_HOLE="black_hole"}
return function(F,Water,Food,Houses,climate)
  if climate~="arctic" and climate~="tropic" then return F end
  local base_tile_acceptance=F.tile_acceptance
  local function name(cargo)
    local row=cargo.definition
    local k=row[1]:sub(4):lower()
    if not F.cargo[k] then
      local class=row[11][1]:gsub("(%l)(%u)","%1_%2"):lower()
      F.cargo[k]={id=cargo.id,label=({food="FOOD",water="WATR",fruit="FRUT",wheat="WHEA",maize="MAIZ"})[k],
        class=class,payment=row[6],days1=row[7],days2=row[8],weight_16=row[4],capacity_multiplier=row[5]}
    end
    return k
  end
  local ids={food_process=13}
  if climate=="tropic" then
    ids.fruit_plantation,ids.maize_farm,ids.water_supply,ids.water_tower=19,24,21,22
  end
  local physical={}
  for kind,id in pairs(ids) do
    local src=assert(Stock.get(id,climate))
    local out,rates,input,multipliers={},{},{},{}
    for _,c in ipairs(src.produce) do
      if c.cargo then out[#out+1]=name(c.cargo);rates[#rates+1]=c.value end
    end
    for _,c in ipairs(src.accept) do
      if c.cargo then input[#input+1]=name(c.cargo);multipliers[#multipliers+1]=c.value end
    end
    F.layout[kind]=Layout[id]
    F.spec[kind]={id=id,life=assert(life[src.life]),minimum=src.minimum,
      cost_factor=src.cost_factor,procurement_probability=src.procurement_probability,climates=src.climates,sounds=0,
      out=out,rates=rates,input=input,multiplier=multipliers,appearance=src.appearance,generation=src.generation,
      map_colour=src.map_colour,plant_fields=src.behavior.PlantFields,plant_on_built=src.behavior.PlantOnBuild}
    physical[kind]=src
  end
  for _,cargo in ipairs(climate=="tropic" and {"food","fruit","maize","water"} or {"food","wheat"}) do
    F.trucks[cargo]={load_amount=5,age_ticks=185,speed=96}
  end
  F.house_acceptance=function(id,cargo)
    if cargo=="food" then return Houses.eighths(id,cargo,climate) end
    return 0
  end
  -- Quote the built-in location and physical footprint phases. The
  -- campaign host still owns town/pool admission and platform grading.
  function F.climate_footprint(kind,variant,x,z,board,instances,worldgen)
    local src=assert(physical[kind],"Not a stock climate industry")
    local s=board.tile(x,z)
    if not s or not s.valid then return nil,"SITE_UNSUITABLE" end
    for _,other in ipairs(instances or {}) do
      for _,t in ipairs(src.conflicts) do
        if t==other.type and math.max(math.abs(x-other.x),math.abs(z-other.z))<=14 then
          return nil,"INDUSTRY_TOO_CLOSE"
        end
      end
    end
    if src.check=="Water" then
      local ok,why=Water.anchor(s.zone)
      if not ok then return nil,why end
    elseif src.check=="Plantation" and not Food.plantation_anchor(s.zone) then return nil,"SITE_UNSUITABLE" end
    local plan,why=Geometry.tiles_free(assert(F.layout[kind][variant]),Layout.slope_refused,
      x,z,{only_in_town=src.behavior.OnlyInTown},board)
    if not plan then return nil,why end
    local ok,needs_grading=Geometry.slopes(plan,Layout.slope_refused,worldgen,worldgen,false)
    if not ok then return nil,needs_grading end
    return plan,needs_grading
  end
  function F.tile_acceptance(gfx,cargo)
    local food=Food.acceptance_eighths(gfx,cargo,climate)
    if food>0 then return food end
    if climate=="tropic" then
      local water=Water.tile_acceptance(gfx,cargo)
      if water>0 then return water end
    end
    return base_tile_acceptance(gfx,cargo)
  end
  return F
end
