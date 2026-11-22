-- SPDX-License-Identifier: GPL-2.0-only
-- Real Harbor Valley stock board entry point and unaltered houses;
-- isolates construction/acceptance before mounting live paid orders.
local p="mods/bayline/"
local function m(n) return dofile(p..n..".lua") end
local S,T=m("sim"),m("openttd/terrain");local w=S.new(1751)
m("town_layout")(S,w)
w.corner_grid=m("harbor_valley_seed")(S,T,w,m("terrain_preview")(S,T,w))
local Timber=m("timber_world")(S,T,S.timber_rules())
assert(Timber.default_1751(w))
local P,R,I=m("openttd/passengers"),m("openttd/station_rating"),m("openttd/income")
local C=m("openttd/station_catchment")(P,R);local hosts=m("town_passenger_runtime")(S,m("openttd/town_passengers"))
hosts.start(w)
local at=S.id
local Track,Follow,Slope=m("openttd/rail_track"),nil,m("openttd/slope")
Follow=m("openttd/rail_follow")(Track)
local COST=m("openttd/rail_yapf_cost")(Track,Follow)
local SEARCH=m("openttd/rail_yapf_search")(Track,Follow,COST)
local LAB=m("trackworks")(S,Track,Follow,Slope,COST,SEARCH,function(tile)
 local x,z=S.xy(tile); return T.tile(w.corner_grid,x,z)
end)
w.road_stock_clock,w.road_stock_loading,w.road_stock_house_supply,w.road_economy,w.road_timber=true,true,true,true,true
local l=Timber.scenario_1751(w);local owner="Timber and Goods"
for i=2,#l.road_waypoints[1] do
 assert(S.build(w,owner,"road",S.line(l.road_waypoints[1][i-1],l.road_waypoints[1][i])))
end
assert(S.build_truck_stop(w,owner,l.forest_stop));assert(S.build_truck_stop(w,owner,l.sawmill_stop))
assert(S.build(w,owner,"road_depot",{l.depot}))
local function track(x,z,k)
 local a=T.tile(w.corner_grid,x,z)
 assert(LAB.change(w,owner,at(x,z),k,false,a))
end
for x=13,16 do track(x,12,Track.X) end
track(17,12,Track.RIGHT)
for z=13,20 do track(17,z,Track.Y) end
assert(LAB.depot(w,owner,at(17,20),Track.NW))
assert(LAB.station(w,owner,at(17,16),at(17,18)))
assert(LAB.station(w,owner,at(13,12),at(15,12)))
local src=w.tiles[at(17,16)].rail_station_id;local dst=w.tiles[at(13,12)].rail_station_id
local Conv=m("openttd/coal_industry")(P,R,C,I)
local Roster,Timing,Factory=m("openttd/rail_roster"),m("openttd/loading_timing"),m("road_loading_runtime")
local St=m("station_rating_runtime")(S,R,P)
local RailStation=m("rail_coal_service")(S,Conv,C,Roster,P,R,St,I,Factory,Timing)
local Goods=m("rail_goods_service")(S,S.timber_rules(),C,Roster,RailStation,P,R,St,Factory,Timing)
local B=m("road_timber_service")(S,S.timber_rules(),m("timber_industry_runtime")(S.timber_rules(),C),P,I,R,St).bind(w,
 {station_union=function(st,open,scan,rating)
 return Goods.bind(w,Goods.new(),{roles={[src]="load",[dst]="unload"},road_stations=st,pipeline=open,post_scan=scan,rating=rating})
 end})
assert(#B.rail.report(src).sources==1 and B.rail.report(dst).eighths==9)
print("PASS stock real Harbor board and timber road, rail depot (17,20) westbound through RIGHT curve to town platform (13,12)..(15,12), source platform (17,16)..(17,18)")
