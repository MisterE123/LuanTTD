local mod="mods/luanttd_core/"
local S=dofile(mod.."sim.lua")
local T=dofile(mod.."openttd/terrain.lua")
local Encode=dofile(mod.."packed_campaign.lua")
local Command=dofile(mod.."campaign_road_construction.lua")
local s=S.new(1751)
s.tiles,s.sites={},{}
for i=1,S.W*S.H do s.tiles[i]={terrain="grass",h=1,variant=1} end
s.corner_grid=T.new(S.W,S.H,function() return 1 end)
s.road_stock_clock,s.road_economy,s.road_stock_loading,s.road_stock_house_supply=true,true,true,true
s.stock_load_tick=500
local own="Station Renewal"
S.company(s,own)
local R=S.road_station_retirement()
local function id(x,z)return S.id(x,z) end
local a,b=id(13,14),id(19,14)
assert(S.build(s,own,"road",S.line(id(9,14),id(27,14))))
local C=Command(S,s)
local function place(tile,kind,choose,explicit)
  return assert(C.commit(own,{tool="stock_terminal_auto",first=tile,kind=kind,adjacent=explicit,join=choose},nil,true))
end
local function remove(tile)
  return assert(C.commit(own,{tool="stock_stop_remove",first=tile},nil,true))
end
place(a,"bus");place(b,"truck")
local aa,bb=s.tiles[a].station,s.tiles[b].station
s.stations[aa].name="Old Junction"
s.stations[aa].stock.passenger=6
s.stations[aa].time_since_load,s.stations[aa].time_since_unload,s.stations[aa].town_growth_service_clock=20,255,true
local service=dofile(mod.."town_station_services.lua")(S)
local G=dofile(mod.."openttd/town_growth.lua")
local t=G.new(1,13,14)
remove(a);remove(b)
assert(not s.stations[aa] and not s.stations[bb])
assert(G.active_stations(t,service.view(s))==1,"Clearing the last platform must not erase town service")
assert(R.closest(s,"station",own,id(16,14)).id==aa)
assert(not R.closest(s,"station","Other rail",id(16,14)))
assert(not R.closest(s,"station",own,id(27,14)),"distance eight is excluded")
s=assert(Encode.decode(Encode.encode(s)));C=Command(S,s)
local options=assert(C.join_choices(own,{tool="stock_terminal_auto",first=id(16,14),kind="bus"}))
assert(#options.choices==3 and options.choices[1].name=="New station")
local names={}
for _,r in ipairs(options.choices) do names[r.name]=true end
assert(names["Rebuild Old Junction"])
place(id(16,14),"bus")
assert(s.tiles[id(16,14)].station==aa and s.stations[aa].name=="Old Junction")
assert(s.stations[aa].stock.passenger==6 and s.stations[aa].time_since_load==20)
local next=s.next_station
place(id(22,14),"truck",nil,true)
assert(s.tiles[id(22,14)].station==next and s.next_station==next+1)
local retirement=s.retired_road_stations[bb]
s.stock_load_tick=retirement.until_tick-1
assert(R.get(s,"station",bb))
s.stock_load_tick=retirement.until_tick
assert(not R.get(s,"station",bb))
R.expire(s);assert(not s.retired_road_stations[bb])
print("PASS retired roads stations reuse saved names and identity, discover them by picker, skip reuse for New, and expire at stock big ticks")

assert(S.build(s,own,"road",S.line(id(11,16),id(22,16))))
assert(S.build(s,own,"road",S.line(id(22,17),id(22,25))))
local p,q=id(17,16),id(22,20)
assert(C.commit(own,{tool="road_waypoint",first=p},nil,true))
local mark=s.tiles[p].road_waypoint_id
local picked=assert(C.join_choices(own,{tool="road_waypoint",first=q,separate=true}))
assert(picked.choices[2].id==mark)
assert(C.commit(own,{tool="road_waypoint",first=q,separate=true,join=mark},nil,true))
assert(s.tiles[q].road_waypoint_id==mark and s.tiles[p].road_bits==10 and s.tiles[q].road_bits==5)
local F=dofile(mod.."openttd/yapf_road_follow.lua")
local board=dofile(mod.."road_yapf_board.lua")(S,s,F)
assert(board.tile(p).dir==0 and board.tile(q).dir==1)
assert(C.commit(own,{tool="road_waypoint",first=p,remove=true},nil,true))
assert(not s.tiles[p].road_waypoint_id and s.tiles[p].road_bits==10 and s.stock_road_waypoints[mark].tile==q)
local low,high=id(22,18),id(22,24)
place(low,"bus",nil,true);place(high,"bus",nil,true)
local start,finish=s.stations[s.tiles[low].station],s.stations[s.tiles[high].station]
local bus={owner=own,engine="bus",cargo="passenger"}
local path,_,_,frames=S.path(s,start,finish,"road",own,nil,bus,{mark})
assert(path and frames and path[#path]==high)
local crossed=false
for _,f in ipairs(frames) do if f[4]==q then
  assert(f[6]<16,"the perpendicular marker still uses a passing frame, not a loading stop")
  crossed=true
end end
assert(crossed)

assert(C.commit(own,{tool="road_waypoint",first=q,remove=true},nil,true))
assert(not s.stock_road_waypoints[mark] and s.tiles[q].road_bits==5)
local opts=assert(C.join_choices(own,{tool="road_waypoint",first=id(22,23),separate=true}))
assert(opts.choices[2].name=="Rebuild Road waypoint #"..mark)
assert(C.commit(own,{tool="road_waypoint",first=id(22,23)},nil,true))
assert(s.tiles[id(22,23)].road_waypoint_id==mark and s.stock_road_waypoints[mark].tile==id(22,23))
print("PASS mixed-axis waypoint uses tile geometry, removal keeps each road, and nearby rebuilding reuses the marker ID")
