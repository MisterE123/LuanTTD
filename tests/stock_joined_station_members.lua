-- SPDX-License-Identifier: GPL-2.0-only
local Sim=dofile("mods/luanttd_core/sim.lua")
local M=Sim.stock_joined_station
local Codec=dofile("mods/luanttd_core/packed_campaign.lua")
local road={id=1,mode="road",stock_station_id=0,owner="A"}
local plane={id=6,stock_station_id=0,owner="A"}
local s={stock_pool_authority=true,stations={[1]=road},stock_small_airports={[6]=plane}}
local ok=pcall(Sim.stock_station_slot,s)
assert(not ok,"A numeric collision is not a physical join")
local group=M.attach(s,0,"A","road",1)
assert(not pcall(Sim.stock_station_slot,s),"Both entries must be explicit")
assert(M.attach(s,0,"A","air",6)==group)
assert(Sim.stock_station_slot(s)==1)
assert(M.member(s,group,"road")==road and M.member(s,group,"air")==plane)
assert(not pcall(M.attach,s,0,"B","air",6),"Ownership cannot be overwritten")
-- Loading creates fresh mode records and even a fresh book; references are
-- regenerated from saved scalars rather than requiring Lua table identity.
s=assert(Codec.decode(Codec.encode(s)))
local restored=s.stock_joined_stations[0]
assert(M.resolve(s,0,"road",1,s.stations[1])==restored)
assert(not M.resolve(s,0,"road",1,road),"Stale runtime object must not alias")
assert(Sim.stock_station_slot(s)==1)
s.stock_road_waypoints={[99]={stock_station_id=0,owner="A"}}
assert(not pcall(Sim.stock_station_slot,s),"Waypoints cannot alias stations")
s.stock_road_waypoints=nil
assert(M.member(s,restored,"air")~=plane)
M.detach(s,0,"air",6,s.stock_small_airports[6])
s.stock_small_airports[6]=nil
assert(Sim.stock_station_slot(s)==1 and not M.member(s,restored,"air"))
M.detach(s,0,"road",1,s.stations[1])
s.stations[1]=nil
assert(Sim.stock_station_slot(s)==0 and s.stock_joined_stations[0]==nil)
print("PASS joined station allocates one physical slot only for validated, reload-safe facility IDs")
