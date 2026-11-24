local mod="mods/luanttd_core/"
local S=dofile(mod.."sim.lua")
local T=dofile(mod.."openttd/terrain.lua")
local s=S.new(1751)
s.tiles,s.sites={},{}
s.corner_grid=T.new(S.W,S.H,function()return 1 end)
for i=1,S.W*S.H do s.tiles[i]={h=1,terrain="grass",variant=1} end
s.road_stock_clock,s.road_economy,s.road_stock_loading,s.road_stock_house_supply=true,true,true,true
local own="Metro Company"
S.company(s,own)
local function id(x,z) return S.id(x,z) end
assert(S.build(s,own,"road",S.line(id(8,12),id(22,12))))
assert(S.build(s,own,"road",S.line(id(9,14),id(16,14))))
assert(S.build(s,own,"road",S.line(id(16,14),id(16,12))))
local depot=id(9,15)
assert(S.build(s,own,"road_depot",{depot}))
local hub,alt,destination=id(10,12),id(10,14),id(20,12)
assert(S.build(s,own,"road_station",{hub,alt,destination}))
local h,t=s.tiles[hub].station,s.tiles[alt].station
s.stations[t]=nil
s.tiles[alt].station=h
local station=s.stations[h]
station.road_stop_areas={bus={tile=hub,w=1,h=3}}
station.tiles={[hub]=true,[alt]=true}
local finish=s.stations[s.tiles[destination].station]
local v={engine="bus",owner=own,cargo="passenger"}
local a,td,_,f=S.path(s,{owner=own,mode="road",tile=depot},station,"road",own,nil,v)
assert(a and a[#a]==alt and f[#f][4]==alt and f[#f][6]==64+td)
v.road_stop_pose,v.road_arrival_td=f[#f],td
local route,_,_,frames=S.path(s,station,finish,"road",own,nil,v)
assert(route and route[1]==alt and route[#route]==destination)
for _,axis in ipairs{1,2,3,4,6,15} do assert(frames[1][axis]==v.road_stop_pose[axis]) end
print("PASS joined road station reaches its closest connected tile and departs from the exact physical pose, not the sign")

-- OpenTTD's sign is inside the spread, not necessarily on a station
-- tile. When the sign tile is removed from a corner of a ragged station
-- the remaining tiles are both practical YAPF order destinations.
local far=id(11,12)
assert(S.build(s,own,"road_station",{far}))
s.stations[s.tiles[far].station]=nil
s.tiles[far].station=h
local members=dofile(mod.."road_stop_members.lua")(S)
members.structural_apply(station,members.preview(station,{{id=alt,kind="bus"},{id=far,kind="bus"},{id=hub}}))
assert(station.tile==hub and not station.road_members[hub])
s.tiles[hub].build,s.tiles[hub].station="road",nil
assert(S.road_stop_anchor(station,"bus")==far)
v.road_stop_pose,v.road_arrival_td=nil,nil
a,td,_,f=S.path(s,{owner=own,mode="road",tile=depot},station,"road",own,nil,v)
assert(a and a[#a]==alt and f[#f][4]==alt)
v.road_stop_pose,v.road_arrival_td=f[#f],td
route,_,_,frames=S.path(s,station,finish,"road",own,nil,v)
assert(route and route[1]==alt and route[#route]==destination)
print("PASS road routing uses real platforms after removal leaves a station sign on plain pavement")
