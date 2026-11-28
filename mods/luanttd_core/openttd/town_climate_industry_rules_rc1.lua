-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 table/build_industry.h and
-- table/cargo_const.h. Bind the exact climate records to the existing
-- stock industry accounting, rather than a second water/food economy.
return function(F,Water,Food,Houses,climate)
  local a,b=Food.inputs(climate)
  if not a then return F end
  local base_tile_acceptance=F.tile_acceptance
  local function commodity(spec,id,class)
    return {id=id,label=spec.label,class=class,payment=spec.base_payment,
      days1=spec.transit_period_1,days2=spec.transit_period_2,
      weight_16=spec.weight_sixteenths,capacity_multiplier=spec.capacity_multiplier}
  end
  F.cargo.food=commodity(Food.cargo,11,"express")
  if climate=="arctic" then
    F.cargo.wheat=commodity(Food.inputs_cargo.wheat,6,"bulk")
  else
    F.cargo.fruit=commodity(Food.inputs_cargo.fruit,4,"bulk")
    F.cargo.maize=commodity(Food.inputs_cargo.maize,6,"bulk")
    F.layout.fruit_plantation=Food.fruit.layout
    F.layout.maize_farm=F.layout.farm
    for kind,src in pairs{fruit_plantation=Food.fruit,maize_farm=Food.maize} do
      F.spec[kind]={id=src.id,life="organic",minimum=src.minimum_to_distribute,
        cost_factor=src.cost_factor,procurement_probability=src.probability,climates=4,sounds=0,
        out={src.cargo},rates={src.rate},input={},multiplier={},
        appearance={0,0,src.appearance,0},generation={0,0,src.generation,0},
        map_colour=src.map_colour,plant_fields=src.plant_fields,plant_on_built=src.plant_on_built}
    end
  end
  for _,cargo in ipairs(climate=="tropic" and {"food","fruit","maize"} or {"food","wheat"}) do
    F.trucks[cargo]={load_amount=5,age_ticks=185,speed=96}
  end
  F.house_acceptance=function(id,cargo)
    if cargo=="food" then return Houses.eighths(id,cargo,climate) end
    return 0
  end
  local processors=Food.process
  F.layout.food_process={[0]=processors.layout[1],[1]=processors.layout[2]}
  F.spec.food_process={id=processors.id,life="processing",minimum=processors.minimum_to_distribute,
    cost_factor=processors.cost_factor,procurement_probability=0xFFFFFFFF,climates=6,sounds=0,
    out={"food"},rates={0},input={a,b},multiplier={256,256},
    appearance={0,2,2,0},generation={0,3,4,0},map_colour=processors.map_colour}
  if climate=="tropic" then
    F.cargo.water=commodity(Water.cargo,9,"liquid")
    F.trucks.water={load_amount=5,age_ticks=185,speed=Water.road_tankers[1].speed}
    F.layout.water_supply={[0]=Water.supply.layout}
    F.layout.water_tower={[0]=Water.tower.layout}
    F.spec.water_supply={id=Water.supply.id,life="extractive",minimum=5,
      cost_factor=Water.supply.construction_factor,procurement_probability=0xB3333333,climates=4,sounds=0,
      out={"water"},rates={Water.supply.rate},input={},multiplier={},
      appearance={0,0,3,0},generation={0,0,4,0},map_colour=Water.supply.map_colour}
    F.spec.water_tower={id=Water.tower.id,life="black_hole",minimum=5,
      cost_factor=Water.tower.construction_factor,procurement_probability=0xFFFFFFFF,climates=4,sounds=0,
      out={},rates={},input={"water"},multiplier={256},
      appearance={0,0,4,0},generation={0,0,8,0},map_colour=Water.tower.map_colour}
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
