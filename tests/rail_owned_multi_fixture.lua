-- Shared authority fixture, native and standalone.
return function(Sim,s,Lab,Owned,Run,T,Signal)
local owner="Mixed Railways"
Sim.company(s,owner)
local id=Sim.id
local function rail(x,z,bits)
  local t=s.tiles[id(x,z)];t.owner,t.rail_tracks,t.build=owner,bits,"stock_rail"
end
for i=4,25 do rail(i,15,1);rail(15,i,2) end
rail(15,15,3)
local a,b=id(4,15),id(15,4)
assert(Lab.depot(s,owner,a,T.SW) and Lab.depot(s,owner,b,T.SE))
assert(Lab.station(s,owner,id(8,15),id(9,15)))
assert(Lab.station(s,owner,id(23,15),id(25,15)))
assert(Lab.station(s,owner,id(15,8),id(15,9)))
assert(Lab.station(s,owner,id(15,23),id(15,25)))
local A,B=s.tiles[id(8,15)].rail_station_id,s.tiles[id(23,15)].rail_station_id
local C0,D0=s.tiles[id(15,8)].rail_station_id,s.tiles[id(15,23)].rail_station_id
for _,pos in ipairs({{13,15,8},{17,15,8},{15,13,1},{15,17,1}}) do
  assert(Run.place_signal(s,owner,id(pos[1],pos[2]),pos[3],Signal.BLOCK,true))
end
assert(Run.place_signal(s,owner,id(20,15),8,Signal.PBS))
s.sites[1].tile=id(8,13);s.sites[2].tile=id(23,13)
for _,t in ipairs({{8,15},{23,15},{15,8},{15,23}}) do
  for i=-2,2 do
    for j=-2,2 do
      local k=s.tiles[id(t[1]+i,t[2]+j)]
      if not k.owner then k.house,k.parcel,k.variant=true,"shop",2 end
    end
  end
end
local u=assert(Owned.commit(s,owner,assert(Owned.quote(s,owner,a,{0,27}))))
local v=assert(Owned.commit(s,owner,assert(Owned.quote(s,owner,b,{0,27}))))
local ok,why,first=Owned.start(s,owner,u.id,B,A)
assert(ok,why)
local yes,note,second=Owned.start(s,owner,v.id,D0,C0)
assert(yes,note)
assert(first.local_signals and second.local_signals and first.paid_clock~=second.paid_clock)
return {owner=owner,a=u.id,b=v.id,diamond=id(15,15),stops={id(13,15),id(15,13),id(17,15),id(15,17)}}
end
