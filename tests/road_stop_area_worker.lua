local m="mods/luanttd_core/"
local S=dofile(m.."sim.lua")
local T=dofile(m.."openttd/terrain.lua")
local own="Area Transit"
local s=S.new(1751)
s.sites,s.tiles={},{}
for i=1,S.W*S.H do s.tiles[i]={terrain="grass",h=1,variant=1} end
s.corner_grid=T.new(S.W,S.H,function()return 1 end)
s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
local p=S.company(s,own)
local function id(x,z)return S.id(x,z) end
for z=10,12 do assert(S.build(s,own,"road",S.line(id(5,z),id(15,z)))) end
local C=dofile(m.."campaign_road_construction.lua")(S,s)
local r={tool="stock_stop_area",first=id(9,10),last=id(9,11),kind="bus",direction=0,through=true}
local initial=p.cash
s.sites={{id=1,name="North",kind="town",tile=id(9,7)}}
s.stock_road_town_policy={dist_local_authority=4}
p.stock_town_authority_ratings={[1]=-200}
assert(select(2,C.quote(own,r))=="The local council won't let your company build a station here.")
assert(p.cash==initial)
s.stock_road_town_policy.dist_local_authority=3
local q=assert(C.quote(own,r))
assert(q.cost==400 and #q.tiles==2 and p.cash==initial)
assert(C.commit(own,r,q))
local sid=s.tiles[r.first].station
assert(s.tiles[r.last].station==sid)
local st=s.stations[sid]
local Catches=dofile(m.."openttd/station_catchment.lua")({}, {})
local function same_coverage()
  local stock=Catches.build({id=sid,tiles=S.road_stop_tiles(st)},S.W,S.H,s.stock_modified_catchment)
  local live=S.road_stop_catchment(s,st,3)
  for z=6,17 do for x=4,14 do
    assert((live[id(x,z)]==true)==Catches.contains(stock,x-1,z-1))
  end end
end
same_coverage()
assert(not S.road_stop_covers(s,st,9,15,3))
assert(st.road_members[r.first]=="bus" and st.road_members[r.last]=="bus" and st.road_stop_areas.bus.h==2)
assert(p.cash==initial-400 and st.tile==r.first and s.next_station==sid+1)
assert(not S.build(s,own,"clear",{r.last}),"generic bulldozer must not discard a shared cargo registry")
st.stock.passenger=17
local ext={tool="stock_stop_area",first=r.last,last=id(9,12),kind="bus",direction=0,through=true}
local ticket=assert(C.quote(own,ext))
assert(ticket.cost==200 and #ticket.tiles==1)
assert(C.commit(own,ext,ticket))
assert(s.tiles[ext.last].station==sid and st.road_stop_areas.bus.h==3)
assert(st.stock.passenger==17 and s.next_station==sid+1)
assert(S.road_stop_covers(s,st,9,15,3) and not S.road_stop_covers(s,st,13,15,3))
same_coverage()
local foreign="Rival"
S.company(s,foreign)
assert(not C.quote(foreign,ext))
local separate={tool="stock_stop_area",first=id(10,10),kind="bus",direction=0,through=true,adjacent=true}
assert(C.commit(own,separate,nil,true))
assert(s.tiles[separate.first].station~=sid)
print("PASS authoritative road-station area receipt, joined extension, unchanged stock, ownership, and separate station")

local remove={tool="stock_stop_remove",first=r.first,last=r.last}
local got=assert(C.quote(own,remove))
assert(got.cost==100 and #got.tiles==2)
assert(C.commit(own,remove,got))
assert(s.tiles[r.first].build=="road" and s.tiles[r.first].road_bits==10 and not s.tiles[r.first].station)
assert(st.tile==ext.last and st.road_stop_areas.bus.h==1 and st.stock.passenger==17)
assert(not S.road_stop_covers(s,st,9,7,3) and S.road_stop_covers(s,st,9,15,3))
same_coverage()
local last={tool="stock_stop_remove",first=ext.last}
s.fleet[45]={id=45,owner=own,engine="bus",orders={{station=sid}}}
assert(not C.quote(own,last))
s.fleet[45]=nil
assert(C.commit(own,last,nil,true))
assert(not s.stations[sid] and s.tiles[ext.last].road_bits==10)
print("PASS road stop removal preserves pavement, clamps the shared sign, and keeps orders from losing their last platform")


-- Two bay stops in a strip. Each gets its own stock optional frontage,
-- and the extra road edits are not included in the station spread.
for z=22,23 do
  local t=s.tiles[id(21,z)]
  t.build,t.owner,t.road_bits="road",own,8
end
local strip={tool="stock_stop_area",kind="truck",direction=0,first=id(22,22),last=id(24,23)}
local requested=assert(C.quote(own,strip))
assert(#requested.tiles==4 and requested.tiles[1]==id(22,22) and requested.tiles[2]==id(22,23))
assert(C.commit(own,strip,requested))
local two=assert(s.stations[s.tiles[id(22,22)].station])
assert(two.stop_type=="truck" and two.spread.w==1 and two.spread.h==2)
assert(two.road_members[id(22,23)]=="truck" and not two.road_members[id(21,22)])
assert(s.tiles[id(21,22)].road_bits==10 and s.tiles[id(21,23)].road_bits==10)
print("PASS stock-catchment geometry updates after each edit, and multi-bay frontage stays separate from the station")

local gap={tool="stock_stop_area",kind="truck",direction=0,first=id(22,27),last=id(22,28)}
local found=assert(C.join_choices(own,gap))
assert(#found.choices==2 and found.choices[1].name=="New station" and found.choices[2].id==two.id)
assert(found.area.tile==id(22,27) and found.area.h==2)
gap.adjacent,gap.join,gap.join_picker_cost=true,two.id,found.cost+1
assert(not C.commit(own,gap,nil,true) and not s.tiles[gap.first].station)
gap.join_picker_cost=found.cost
assert(C.commit(own,gap,nil,true))
assert(s.tiles[gap.first].station==two.id and two.spread.h==7)
assert(not C.join_choices(own,gap),"Station on the exact footprint requires a normal extension gesture.")

for z=2,10,4 do assert(S.build(s,own,"road",S.line(id(5,z),id(15,z)))) end
assert(C.commit(own,{tool="road_waypoint",first=id(9,2)},nil,true))
local wp=assert(s.tiles[id(9,2)].road_waypoint_id)
local distant={tool="road_waypoint",first=id(9,10),separate=true}
found=assert(C.join_choices(own,distant))
assert(#found.choices==2 and found.choices[1].name=="New waypoint" and found.choices[2].id==wp)
distant.join,distant.join_picker_cost=wp,found.cost
assert(C.commit(own,distant,nil,true))
assert(s.tiles[id(9,10)].road_waypoint_id==wp)
print("PASS isolated chooser returns only eligible stations and road waypoints, validates price, and joins by ID")

-- A real multi-platform station whose sign tile is bulldozed.
local anchor=id(32,19)
for z=18,21 do
  for x=30,34 do
    local t=s.tiles[id(x,z)]
    t.build,t.owner,t.road_bits="road",own,10
  end
end
local function station_area(first,last,adjacent)
  return {tool="stock_stop_area",kind="bus",direction=0,first=first,last=last,through=true,adjacent=adjacent}
end
assert(C.commit(own,station_area(anchor,anchor,true),nil,true))
local gap_id=s.tiles[anchor].station
local gap=s.stations[gap_id]
local view=dofile(m.."town_station_services.lua")(S).view
gap.town_growth_service_clock,gap.time_since_load=true,20
assert(C.commit(own,station_area(id(32,18),id(32,20)),nil,true))
assert(C.commit(own,{tool="stock_stop_remove",first=anchor},nil,true))
assert(gap.tile==anchor and not s.tiles[anchor].station)
local function find()
  for _,row in ipairs(view(s)) do if row.id==gap_id then return row end end
end
local index=assert(find(),"The sign is still active if any platform remains")
assert(index.x==32 and index.z==19 and index.time_since_load==20)
assert(C.commit(own,{tool="stock_stop_remove",first=id(32,18),last=id(32,20)},nil,true))
assert(not s.stations[gap_id] and assert(find()).z==19)
local first,last=id(33,17),id(33,20)
for z=17,20 do s.tiles[id(33,z)]={terrain="grass",h=1,variant=1,build="road",owner=own,road_bits=10} end
assert(C.commit(own,station_area(first,last),nil,true))
assert(s.tiles[first].station==gap_id and s.stations[gap_id].tile==first)
index=assert(find())
assert(index.x==33 and index.z==17 and index.time_since_load==20)
print("PASS a station with a gap stays in the town index and its reopened sign moves to the actual first platform")
