-- SPDX-License-Identifier: GPL-2.0-only
local path="mods/luanttd_core/"
local Sim=dofile(path.."sim.lua")
local Terrain=dofile(path.."openttd/terrain.lua")
local B=dofile(path.."openttd/road_bridge.lua")(dofile(path.."openttd/slope.lua"))
local s=Sim.new(1751)
local id=Sim.id
local maker="Bridge Engineer"
local cash=Sim.company(s,maker)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 1 end)
for i in pairs(s.tiles) do s.tiles[i]={terrain="grass",h=1} end
local a,b=id(11,11),id(14,11)
local middle=id(12,11)
s.tiles[middle].terrain="water"
local under_rail=id(13,11)
s.tiles[under_rail].build="stock_rail"
s.tiles[under_rail].rail_tracks=2
s.tiles[under_rail].owner="Another company"
Sim.engine_calendar=dofile(path.."openttd/stock_engine_calendar.lua")
s.stock_bus_market={epoch=Sim.engine_calendar.date(1929,12,31)}
local legal,reason=Sim.road_bridge(s,maker,a,b,9,true)
assert(not legal and reason=="BRIDGE_UNAVAILABLE")
s.stock_bus_market.epoch=s.stock_bus_market.epoch+1
local allowed,_,short=Sim.road_bridge(s,maker,a,b,9,true)
assert(allowed and short.spec.speed==256 and #short.middle==2)
local long,err=Sim.road_bridge(s,maker,id(10,11),b,9,true)
assert(not long and err=="BRIDGE_TOO_LONG")
s.stock_bus_market=nil
local original=cash.cash
assert(Sim.road_bridge(s,maker,a,b,0))
local bridge=s.tiles[a].road_bridge_id
local Speed=dofile(path.."road_speed_runtime.lua")()
local in_flight={[10]=bridge,[11]=64,[12]=true}
local first=s.stock_road_bridges[bridge]
assert(Speed.bridge_limit(s,in_flight)==64 and Speed.bridge_limit(s,{[14]=bridge})==nil)
assert(first and first.spec.speed==32 and first.roadtype==0 and first.road_owner==maker)
assert(s.bridge_above[middle]==bridge and s.tiles[middle].terrain=="water")
assert(s.bridge_above[under_rail]==bridge and s.tiles[under_rail].rail_tracks==2 and s.tiles[under_rail].owner=="Another company")
local ids=s.next_stock_road_bridge
local fail,why=Sim.road_bridge(s,maker,a,b,0,true)
assert(not fail and why=="ALREADY_BUILT",tostring(why))
fail,why=Sim.road_bridge(s,"Another company",a,b,2,true)
assert(not fail and why=="AREA_IS_OWNED_BY_ANOTHER",tostring(why))
local balance=cash.cash
local okay,price,p=Sim.road_bridge(s,maker,b,a,2,true)
assert(okay and p.replacement and p.spec.speed==64 and cash.cash==balance)
local total=4
local ledger=total*(B.base_prices.clear_bridge+2*B.base_prices.clear_road)+
  total*2*B.base_prices.road+math.floor(B.length_factor(total)*B.base_prices.bridge*B.catalog[2].multiplier/256)
assert(price==ledger and p.road_owner==maker and p.roadtype==0)
s.tiles[middle].stock_industry={id=100}
fail,why=Sim.road_bridge(s,maker,a,b,2,true)
assert(not fail and why:match("BRIDGE_MIDDLE_OBSTRUCTED") and cash.cash==balance)
s.tiles[middle].stock_industry=nil
assert(Sim.road_bridge(s,maker,a,b,2))
local now=s.stock_road_bridges[bridge]
assert(Speed.bridge_limit(s,in_flight)==128 and in_flight[11]==64)
assert(s.next_stock_road_bridge==ids and now.bridge_type==2 and now.road_owner==maker)
assert(s.tiles[a].road_bridge_id==bridge and s.tiles[b].road_bridge_id==bridge and s.bridge_above[middle]==bridge)
assert(cash.cash==balance-price and cash.expense==original-cash.cash and s.tiles[middle].terrain=="water")
assert(not Sim.road_bridge(s,maker,id(10,11),b,2,true))
local prior=cash.cash
local r,fee,foot=Sim.remove_wood_bridge(s,maker,b,true)
assert(r and fee==total*(50+2*40) and foot.bridge_type==2 and cash.cash==prior)
cash.cash=fee-1
assert(not Sim.remove_wood_bridge(s,maker,a))
assert(cash.cash==fee-1 and s.tiles[a].road_bridge_id==bridge and s.bridge_above[middle]==bridge)
cash.cash=fee
assert(Sim.remove_wood_bridge(s,maker,b))
assert(cash.cash==0 and s.tiles[middle].terrain=="water" and not s.bridge_above[middle])
assert(s.tiles[under_rail].rail_tracks==2 and not s.bridge_above[under_rail])
print("PASS RC1 road bridge replacement preserves both ramps, owners, water and span identity, charges stock cost and rechecks ground")
