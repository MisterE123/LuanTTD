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
