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
