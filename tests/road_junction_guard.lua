-- Native-only 3D clearance, deliberately not asserted to equal 14.1
-- viewport behavior. Exercise whole rotated model radius vs. a live T.
local root="mods/luanttd_core/"
local Sim=dofile(root.."sim.lua")
local Terrain=dofile(root.."openttd/terrain.lua")
local L=dofile(root.."road_lanes.lua")
local P=dofile(root.."road_motion_presentation.lua")(L)
local G=dofile(root.."road_junction_guard.lua")(Sim,P)
local s=Sim.new(1751)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 0 end)
s.road_economy,s.road_stock_clock,s.road_stock_loading,s.road_junction_clearance=true,true,true,true
local id=Sim.id
local f=dofile("tests/road_junction_fixture.lua")(Sim,s,"A")
local west,east,south,joint,a,b=f.west,f.east,f.south,f.joint,f.depot_a,f.depot_b
local function model(x,z,d,alpha)
  -- Pass source motion coordinates so the test uses the actual view
  -- mapping. Shifting X by one pixel keeps predictable motion probes.
  local tile=id(math.floor(x/16),math.floor(z/16))
  return {x,z,d,tile,alpha}
end
local holder={id=1,frame=model(15*16+8,12*16+5,5,1),z=0}
local W={vehicles_at=function(tile) return tile==joint and {holder} or {} end}
local enter=model(15*16+5,12*16+17,7,0)
local prev=model(15*16+5,12*16+21,7,0)
assert(not G.check(s,W,{id=2},prev,enter,0))
assert(G.check(s,W,{id=2},prev,enter,8),"grade-separated vehicle falsely blocked")
assert(G.check(s,W,{id=1},prev,enter,0),"holder cannot clear its own path")
assert(G.check(s,W,{id=2},enter,prev,0),"vehicle cannot travel away from existing occupied region")
s.road_junction_clearance=false
assert(G.check(s,W,{id=2},prev,enter,0),"strict stock mode must not consult this host rule")
s.road_junction_clearance=true
holder.frame=model(15*16+21,12*16+5,5,1)
assert(G.check(s,W,{id=2},prev,enter,0),"release waited after the visible tail was clear")

-- Only consult altitude after a model enters one of the same possible
-- clusters and finds a plausible occupant. Altitude 0 is a valid result.
holder.frame=model(15*16+8,12*16+5,5,1)
local reads=0
local function z_at(state,pose)
  assert(state==s and pose==enter)
  reads=reads+1;return 0
end
local far=model(6*16+8,8*16+5,5,1)
assert(G.check(s,W,{id=2},prev,far,nil,z_at) and reads==0)
assert(G.check(s,W,{id=1},prev,enter,nil,z_at) and reads==0)
local clear,height=G.check(s,W,{id=2},prev,enter,nil,z_at)
assert(not clear and height==0 and reads==1)
local road_bits=Sim.road_bits
local checks=0
Sim.road_bits=function(...) checks=checks+1;return road_bits(...) end
local before=s.topology
s.topology=before+1 -- plain tide is known not to touch roads or bays
G.preserve_after_tide(s,before)
assert(not G.check(s,W,{id=2},prev,enter,0) and checks==0,
  "A plain tide should not rescan the road network")
local old_bits=s.tiles[joint].road_bits
s.tiles[joint].road_bits=2;s.topology=s.topology+1
before=s.topology
s.topology=before+1
G.preserve_after_tide(s,before) -- must not acknowledge the intervening road edit
assert(G.check(s,W,{id=2},prev,enter,nil,z_at) and reads==1 and checks>0,
  "Removed junction retained a stale halo through a later tide")
Sim.road_bits=road_bits
s.tiles[joint].road_bits=old_bits;s.topology=s.topology+1
assert(not G.check(s,W,{id=2},prev,enter,nil,z_at) and reads==2,"rebuilt junction missed its halo")

-- Preserve candidate *centers* just off-map; occupancy scans themselves
-- still query only playable tiles.
local edge=id(1,5)
s.tiles[edge]={build="road",road_bits=7}
s.topology=s.topology+1
local across_edge=model(15,5*16+8,5,1)
local past_edge=model(11,5*16+8,5,1)
local edge_holder={id=1,frame=model(1*16+8,5*16+8,5,1),z=0}
local edge_world={vehicles_at=function(tile) return tile==edge and {edge_holder} or {} end}
assert(not G.check(s,edge_world,{id=2},past_edge,across_edge,0),"missed junction just inside the map edge")

-- A large unrelated part of the board must not be scanned after every
-- municipal topology bump. The local halo still discovers the complete
-- connected component and sees an occupant outside the candidate's 3x3.
local wide=Sim.new(1751)
wide.corner_grid=Terrain.new(Sim.W,Sim.H,function() return 0 end)
wide.road_junction_clearance=true
for tile=1,Sim.W*Sim.H do wide.tiles[tile]={h=0,terrain="grass"} end
for x=8,14 do
  wide.tiles[id(x,8)]={h=0,terrain="grass",build="road",road_bits=14}
end
for z=18,Sim.H-1 do for x=3,Sim.W-1 do
  wide.tiles[id(x,z)]={h=0,terrain="grass",build="road",road_bits=15}
end end
local tail=id(14,8)
local far_holder={id=71,z=0,frame=model(14*16+8,8*16+8,5,1)}
local bounded_world={vehicles_at=function(t) return t==tail and {far_holder} or {} end}
local outside=model(8*16+5,8*16+27,7,0)
local entering=model(8*16+5,8*16+8,7,0)
local checked=0
Sim.road_bits=function(...) checked=checked+1;return road_bits(...) end
assert(not G.check(wide,bounded_world,{id=72},outside,entering,0),
  "Local lookup must include the full adjoining junction cluster")
assert(checked<100,"A local driver visit read distant junctions")
wide.tiles[id(11,8)].road_bits=13 -- still a junction, but breaks the east edge
wide.topology=wide.topology+1
assert(G.check(wide,bounded_world,{id=72},outside,entering,0),
  "A changed road edge left two disconnected junctions in one cached component")
assert(checked<200,"Local lookup fell back to a whole-map scan on topology change")
Sim.road_bits=road_bits

local function copy(t)
  if type(t)~="table" then return t end
  local o={}
  for k,v in pairs(t) do o[k]=copy(v) end
  return o
end
local function flow(state,delay)
  local function purchase(depot,from,to)
    local v=assert(Sim.purchase(state,"A","bus","passenger",nil,depot))
    assert(Sim.add_order(state,"A",v,state.tiles[from].station))
    assert(Sim.add_order(state,"A",v,state.tiles[to].station))
    return v
  end
  local x=purchase(a,east,west)
  local y=purchase(b,east,south)
  assert(Sim.toggle(state,"A",x))
  local held,loaded=false,false
  for day=1,38 do
    if day==1+delay then assert(Sim.toggle(state,"A",y)) end
    Sim.daily(state)
    for _,fid in ipairs{x,y} do
      local actor=state.fleet[fid]
      if actor.road_junction_waits and actor.road_junction_waits>0 then
        if not held then state=copy(state) end
        held=true
      end
    end
    if held and state.fleet[x].last_road_arrival_tick and state.fleet[y].last_road_arrival_tick then
      loaded=true;break
    end
  end
  return held and loaded
end
local transit
for k=0,7 do
  if flow(copy(s),k) then transit=k;break end
end
assert(transit~=nil,"No actual ordered turn waited, reloaded, then made it across the T")
print(("PASS: genuine three-arm turn admission after reload, visible tail and grade guard, valid live delay=%d"):format(transit))
