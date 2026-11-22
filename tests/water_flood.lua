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
