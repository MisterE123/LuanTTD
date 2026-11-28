-- Stock climate cargo uses the same station, industry, income and town
-- state as the ordinary farm pipeline. The fixture hands off paid
-- packets between stops; it is not a vehicle movement or asset test.
local p="mods/luanttd_core/"
local function m(n) return dofile(p..n..".lua") end
local function o(n) return m("openttd/"..n) end
local Packets,Rating,Income=o("passengers"),o("station_rating"),o("income")
local Catch=o("station_catchment")(Packets,Rating)
local Commons=o("coal_industry")(Packets,Rating,Catch,Income)
local Timber=o("timber_industry")(Packets,Catch,Rating,Income,Commons,o("town_goods"))
local Water,Food,Houses=o("town_water_industry_rc1"),o("town_food_supply_rc1"),o("town_house_acceptance_rc1")
local F=o("town_climate_industry_rules_rc1")(o("farm_factory_industry")(Packets,Catch,Rating,Income,Commons,Timber),
  Water,Food,Houses,"tropic")
local G,Stats=o("town_growth"),o("town_cargo_stats")
local Codec=m("packed_campaign")
local w=256
local function tile(x,z) return x+z*w end
local function xy(id) return id%w,math.floor(id/w) end
local function point(id,x,z)
  return {id=id,owner="Company",town=33,x=x,z=z,tile=tile(x,z),tiles={{x=x,y=z,kind="truck"}},stock={}}
end
-- Supply and tower location follow the native RC1 Tropic 49832 source
-- region, with a real three-tile truck catchment by each footprint.
local s={
  industry={
    [15]=F.new("water_supply",15,25,91,{original=true,completed=true,counter=1}),
    [49]=F.new("water_tower",49,26,106,{original=true,completed=true,counter=1}),
    [50]=F.new("food_process",50,48,105,{original=true,completed=true,counter=1}),
  },
  stations={point(1,27,92),point(2,27,105),point(3,47,104),point(4,51,105)},
  stock_town_growth={towns={[33]=G.new(33,26,106,{population=467,
    climate="tropic",has_effect=function(i)return i==4 or i==5 end})}},
}
local function covers()
  local points={}
  for _,st in ipairs(s.stations) do points[st.id]=Catch.build(st,w,w) end
  return points
end
local function households(x,z)
  if z==104 and x>=25 and x<=28 then return {id=44+x-25,town=33} end
end
local function pick(st,cargo)
  local queue=F.queue(st,cargo)
  local p=assert(table.remove(queue,1),"The live industry did not supply its stop")
  Packets.pickup(p,{id=st.id,tile=st.tile},xy)
  return p
end
local function sell(st,cargo,packet)
  local report=F.acceptance(st,covers()[st.id],cargo,s.industry,households)
  local out=F.deliver(st,report,packet,function(i)return s.industry[i] end,{cargo_tile=st.tile,xy=xy,economy_date=42})
  if out.units>0 then Stats.accept(s,st.town,cargo,out.units,out.town_units or 0) end
  return out,report
end
local function deliver_water()
  local source=s.industry[15]
  assert(F.goods(s.stations[1],"water").rating>0)
  F.goods(s.stations[1],"water").rating=255
  local n=0
  repeat n=F.production_tick(source) until n>0
  assert(n==12 and source.produced[1].waiting==12)
  local emitted,moved=F.tile_loop(source,source.tiles[1],{},function(i,cargo,units)
    return F.distribute(i,cargo,units,{s.stations[1]},covers(),{select_goods=false})
  end)
  assert(emitted==12 and moved>0 and moved<=12)
  local water,wet=sell(s.stations[2],"water",pick(s.stations[1],"water"))
  assert(wet.accepts and not wet.always_accepted and water.units==moved and water.payment>0 and not water.town_units)
  assert(#water.industries==1 and water.industries[1].id==49 and water.industries[1].units==moved)
  local produced,consumed=F.trigger(s.industry[49])
  assert(produced==0 and consumed==moved and F.input(s.industry[49],"water").waiting==0)
  return moved
end
local moved=deliver_water()
local t=s.stock_town_growth.towns[33]
local function climate() return {is_desert=true} end
local serve={{x=t.x,z=t.z,time_since_load=0}}
assert(not G.month(t,serve,2,nil,climate)) -- real water alone is not enough
assert(t.received[4].old_act==moved and not t.accepted.water)

-- Both effects must reach the same month's town statistics.
assert(deliver_water()==moved)

-- Independent input slots for the processor. The inbound fruit/maize
-- consignments here are controlled fixtures, not planted harvests.
for _,cargo in ipairs{"fruit","maize"} do
  local pack={cargo=cargo,source_type="industry",source=91,units=5,origin_station=1,
    age=0}
  Packets.pickup(pack,{id=1,tile=s.stations[1].tile},xy)
  local out,report=sell(s.stations[4],cargo,pack)
  assert(report.accepts and not out.town_units and out.units==5)
end
assert(F.trigger(s.industry[50])==10)
s=assert(Codec.decode(Codec.encode(s)))
local processor=s.industry[50]
F.goods(s.stations[3],"food").rating=255
local n,food_moved=F.tile_loop(processor,processor.tiles[1],{},function(i,cargo,units)
  return F.distribute(i,cargo,units,{s.stations[3]},covers(),{select_goods=false})
end)
assert(n==10 and food_moved>0)
local food,report=sell(s.stations[2],"food",pick(s.stations[3],"food"))
assert(report.accepts and report.always_accepted and report.raw_eighths==8)
assert(food.units==food_moved and food.town_units==food_moved and #food.industries==0 and food.payment>0)
t=s.stock_town_growth.towns[33]
assert(t.accepted.food.new_act==food_moved)
assert(G.month(t,serve,2,nil,climate))
assert(t.received[4].old_act==moved and t.accepted.food.old_act==food_moved)
assert(not G.month(t,serve,2,nil,climate)) -- both receipts expire without repeat service
print(("PASS stock climate cargo ledger after packed open: %d industry-only Water, %d household Food, and real stock fares"):format(moved,food_moved))
