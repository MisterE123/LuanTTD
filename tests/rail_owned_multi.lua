-- SPDX-License-Identifier: GPL-2.0-only
-- Purchased stock steam, a real coach, paid orders and shared clock.
local root="mods/luanttd_core/"
local src=root.."openttd/"
local function port(name,...) return dofile(src..name..".lua")(...) end
local Sim=dofile(root.."sim.lua")
local Terrain=dofile(src.."terrain.lua")
local RoadSlope=dofile(src.."slope.lua")
local T=dofile(src.."rail_track.lua")
local F=port("rail_follow",T)
local C=port("rail_yapf_cost",T,F)
local Search=port("rail_yapf_search",T,F,C)
local Raw=port("rail_motion",T)
local PBS=port("rail_reservation",T,F,C)
local Life=port("rail_consist_reservation",T,F,PBS)
local Signal=port("rail_signals",T)
local Consist=port("rail_consist_motion",T,Raw,F,Life)
local Speed=port("rail_station_speed",T,F)
local Reverse=port("rail_reverse",T,Raw,Consist,Life,Signal,F,PBS)
local H=port("rail_height",T,RoadSlope)
local Q=port("rail_construction",T,Signal,H)
local Site=dofile(src.."rail_span_site.lua")
local B=port("rail_bridge",port("road_bridge",RoadSlope),Q,Site)
local U=port("rail_tunnel",dofile(src.."road_tunnel.lua"),Q,Site,T)
local L=dofile(root.."rail_span_life.lua")(T,PBS,Life)
local Motion=dofile(root.."rail_span_consist.lua")(T,Raw,F,Consist,Life)
local Dispatch=dofile(root.."rail_consist_dispatch.lua")(Motion,L)
local W=dofile(root.."rail_span_world.lua")(Sim,Terrain,H,B,U,T)
local CrossWorld=dofile(root.."level_crossing_world.lua")(Sim,Terrain,port("level_crossing",T),T)
local Cross=dofile(root.."level_crossing_runtime.lua")(Sim,CrossWorld)
local Roster=dofile(src.."rail_roster.lua")
local Block=port("rail_block_signals",T,Signal)
local s=Sim.new(1751)
s.rail_paid_service,s.rail_owned_service,s.rail_block_preview=true,true,true
s.road_economy,s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply=true,true,true,true
s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 0 end)
local function terrain(id) return Terrain.tile(s.corner_grid,Sim.xy(id)) end
for i=1,#s.tiles do s.tiles[i]={terrain="grass",h=0} end
local Lab=dofile(root.."trackworks.lua")(Sim,T,F,RoadSlope,C,Search,terrain)
local Fleet=dofile(root.."rail_depot_fleet.lua")(Sim,Lab,Roster)
local Run=dofile(root.."rail_dispatch_run.lua")(T,F,C,Search,PBS,L,Signal,Motion,Dispatch,Speed,Lab,nil,Reverse,W,Cross,Roster,Block)
local Owned=dofile(root.."rail_owned_service.lua")(Fleet,Roster,Run)
local function mount() Sim.mount_paid_rail(s,Run) end
mount()
assert(Owned.initialize(s,{starting_year=1950,generation_seed=s.seed,startup_random=9001}))
local fixture=dofile("tests/rail_owned_multi_fixture.lua")(Sim,s,Lab,Owned,Run,T,Signal)
local owner=fixture.owner
local u,v={id=fixture.a},{id=fixture.b}
local id=Sim.id
local waited,passed,paid,reload={},{},{},false
local diamond=id(15,15)
local function copy(t)
  if type(t)~="table" then return t end
  local out={}
  for k,v in pairs(t) do out[k]=copy(v) end
  return out
end
for _=1,250 do
  Sim.daily(s)
  local state=Run.current(s)
  assert(not state.failure,state.failure)
  for _,e in ipairs(Sim.rail_paid_motion_events(s)) do
    if e.kind=="waiting" and (e.tile==id(13,15) or e.tile==id(15,13) or
        e.tile==id(17,15) or e.tile==id(15,17)) then waited[e.train]=true end
    if e.kind=="front_entered" and e.tile==diamond then
      passed[e.train]=(passed[e.train] or 0)+1
    end
  end
  for _,which in ipairs({u,v}) do
    local status=assert(Sim.rail_paid_status(s,which.id))
    if status.fare>0 then paid[which.id]=status.fare end
  end
  if not reload and next(waited) then
    s=copy(s);mount()
    assert(Run.current_paid(s,u.id) and Run.current_paid(s,v.id))
    reload=true
  end
  if paid[u.id] and paid[v.id] and (passed[1] or 0)>=2 and (passed[2] or 0)>=2 and next(waited) then break end
end
assert(reload and paid[u.id] and paid[v.id] and passed[1]>=2 and passed[2]>=2 and next(waited))
assert(s.companies[owner].revenue==paid[u.id]+paid[v.id])
print(("PASS two independently bought and ordered shuttles share a mixed-signal diamond; waits and rear clears, both reverse, cross after restore, and earn $%d/$%d"):format(paid[u.id],paid[v.id]))
