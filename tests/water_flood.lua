local p="mods/luanttd_core/"
local T=dofile(p.."openttd/terrain.lua")
local Flood=dofile(p.."openttd/water_flood.lua")
local Sim=dofile(p.."sim.lua")
local F=dofile("tests/water_flood_fixture.lua")(Sim,T)
local W=dofile(p.."water_flood_world.lua")(Sim,T,Flood)
local Track=dofile(p.."openttd/rail_track.lua")
local Water=dofile(p.."openttd/ship_follow.lua")(Track)
local Network=dofile(p.."ship_network.lua")(Sim,T,Water,{})
local ids=Sim.id
local legacy=F.seed(Sim.new(1751))
legacy.stock_coastal_flood=nil
local legacy_cut=F.edit(legacy)
for _=1,24 do Sim.daily(legacy) end
assert(legacy.tiles[legacy_cut.bay].terrain=="grass","Legacy terrain must not flood unless explicitly mounted")
local s=F.seed(Sim.new(1751))
local q=F.edit(s)
local stale_topology=s.topology
local reached=F.flood(s,q)
assert(s.topology>stale_topology and s.passenger_house_clock.counter==75*74)
local board=Network.board(s)
assert(board.tile(q.bay).kind=="sea" and Water.at(board,q.bay)~=0)
local shore,wet_turn
for z=5,15 do for x=2,9 do
  local id=ids(x,z)
  if s.tiles[id].coastal_water then
    local t=board.tile(id)
    if Flood.one_raised(t.slope) then
      assert(t.kind=="coast" and t.is_coast and not Sim.mode_on(s,id,"water"))
      assert(Water.status(t,x-1,z-1)~=0 and Water.status(t,x-1,z-1)~=63)
      wet_turn=wet_turn or {x,z}
    else
      assert(t.kind=="coast" and Water.at(board,id)==0)
      shore=shore or {x,z}
    end
  end
end end
assert(shore and wet_turn)

-- Existing stock canals keep their deliberate demolition restriction.
local a,b=20,20
local t=s.tiles[ids(a,b)]
t.terrain,t.water_class,t.build,t.stock_canal="water","canal","canal",true
local ok,msg=Sim.landscape(s,"Survey","lower",a,b)
assert(not ok and msg:find("canal"))
-- Plain water may legally be cleared as part of a raise. Cost and
-- exclusive occupation are validated without committing quote changes.
local probe_x,probe_z=2,22
Sim.mount_coastal_flood(s,function(id) return ids(probe_x,probe_z)==id end)
ok,msg=Sim.landscape(s,"Survey","raise",probe_x,probe_z)
assert(not ok and msg:find("vessel"))
Sim.mount_coastal_flood(s)
local qok,cost=Sim.landscape(s,"Survey","raise",probe_x,probe_z,nil,nil,nil,true)
assert(qok and cost==40250 and s.tiles[ids(probe_x,probe_z)].terrain=="water")
assert(Sim.landscape(s,"Survey","raise",probe_x,probe_z))
assert(s.tiles[ids(probe_x,probe_z)].terrain=="grass" and s.tiles[ids(probe_x,probe_z)].water_class==nil)
assert(T.corner(s.corner_grid,probe_x,probe_z)==1)

-- No-support multi-corner coast dries, one-raised coast stays active,
-- and Canal/River are never newly promoted to sea by adjacency.
local away=F.seed(Sim.new(1752))
for _,d in ipairs{{20,20,"canal"},{22,20,"river"}} do
  local x,z,name=unpack(d)
  for _,o in ipairs{{0,0},{1,0},{0,1},{1,1}} do
    away.corner_grid.levels[(z+o[2]-1)*(Sim.W+1)+x+o[1]]=0
  end
  local rec=away.tiles[ids(x,z)]
  rec.terrain,rec.water_class="water",name
  assert(W.visit(away,x,z)==0 and rec.water_class==name)
end
local unconnected={["1,1"]={kind="coast",slope=3,base=0},["0,1"]={kind="river",slope=0,base=0}}
local function cell(x,z)return unconnected[x..","..z] end
local d=Flood.visit({tile=cell},1,1)
assert(#d==1 and d[1].kind=="clear")
assert(Flood.behaviour({kind="coast",slope=1})=="active")
print(("PASS real landscaping and source clock: bay reached day %d, level-0 inland trench stayed dry, shore tracks and vessel/canal safeguards"):format(reached))


-- RC1's flat-only TunnelBridge dispatch. A bridge on a slope or
-- above sea level never asks for vehicle flooding or demolition.
local reach={
  ["0,0"]={kind="sea",slope=0,base=0},
  ["0,-1"]={kind="rail_bridge",slope=0,base=0,id=101,other=401,water_z=8,span=7},
  ["1,0"]={kind="rail_bridge",slope=3,base=0,id=102,other=402,water_z=8,span=9},
  ["0,1"]={kind="rail_bridge",slope=0,base=1,id=103,other=403,water_z=16,span=10},
}
local calls,clear=0,false
local bridge={
  tile=function(x,z) return reach[x..","..z] end,
  flood_bridge=function(t)
    calls=calls+1
    assert(t.id==101 and t.other==401 and t.water_z==8)
    return clear
  end
}
assert(#Flood.visit(bridge,0,0)==0 and calls==1)
clear=true
local changes=Flood.visit(bridge,0,0)
assert(calls==2 and #changes==1 and changes[1].x==0 and changes[1].z==-1
  and changes[1].from=="rail_bridge" and changes[1].kind=="sea" and changes[1].span==7)
print("PASS: only a flat coastal rail bridge requests flooding, with deck height and both physical endpoints")

-- The native flood target shortcut is an adapter only. For identical
-- visits, both ways must return the same stock direction-ordered edits.
do
  local s=F.seed(Sim.new(1753))
  local q=F.edit(s)
  assert(q)
  local b=W.board(s)
  local fast,source=b.flood_target,b.flood_source
  local function same(a,c)
    if type(a)~="table" then return a==c end
    if type(c)~="table" then return false end
    for k,v in pairs(a) do if not same(v,c[k]) then return false end end
    for k in pairs(c) do if a[k]==nil then return false end end
    return true
  end
  -- Mix untouchable water and void neighbors with actual floodable
  -- dry ground around the bay and active one-corner coast.
  s.tiles[ids(2,9)].stock_void=true
  s.tiles[ids(2,11)].water_class="river"
  s.tiles[ids(2,12)].water_class="canal"
  local visited,wet=0,0
  for z=7,15 do for x=1,10 do
    b.flood_target,b.flood_source=nil,nil
    local full=Flood.visit(b,x,z)
    b.flood_target,b.flood_source=fast,source
    local changes=Flood.scan(b,x,z)
    local narrow=changes or {}
    assert((changes~=nil)==(#full>0))
    assert(same(full,narrow))
    wet=wet+#narrow;visited=visited+1
  end end
  assert(wet>0 and visited==90)
  assert(b.tile(1,9).kind=="sea" and not b.flood_target(1,9))
  assert(b.tile(2,9).kind=="void" and not b.flood_target(2,9))
end
print("PASS water-target prefilter is identical to full stock classification at the shore")


-- The road-admission cache may retain its graph only for other surface
-- writes that provably did not touch any infrastructure.
for _,object in ipairs({false,true}) do
  local s=F.seed(Sim.new(1751))
  s.corner_grid=T.new(Sim.W,Sim.H,function() return 0 end)
  local ground=s.tiles[ids(3,10)]
  if object then ground.stock_landmark={kind="statue",town=1,owner="Survey"} end
  local before=s.topology
  local changed,plain=W.visit(s,2,10)
  assert(changed>0 and ground.terrain=="water" and s.topology==before+1)
  assert(plain==not object,"Only simple neighbor floods can preserve the junctions")
  assert(not ground.stock_landmark)
end
print("PASS real plain land floods preserve road geometry fingerprints; a flooded town object does not")
