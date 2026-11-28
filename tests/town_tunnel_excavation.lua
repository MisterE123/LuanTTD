-- Municipal CmdBuildTunnel, using the ordinary town earthworks adapter.
local mod=core and core.get_modpath(core.get_current_modname()).."/" or "mods/luanttd_core/"
local function m(n)return dofile(mod..n..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local G=m("openttd/town_growth")
local W=m("openttd/town_worldgen")(G,m("openttd/town_growth_build")(G,m("openttd/town_growth_houses")))
local function state()
  local s=Sim.new(1751)
  s.stock_generated_profile={map_height_limit=30}
  local start,finish,z=23,27,12
  s.corner_grid=T.new(Sim.W,Sim.H,function(x,y)
    if x>=24 and x<=27 or x==28 and y==12 then return 2 end
    return 1
  end)
  for id,t in ipairs(s.tiles) do
    local x,y=Sim.xy(id)
    local _,base=T.tile(s.corner_grid,x,y)
    t.terrain,t.h="hill",base
    t.stock_clear_density=0
    t.wood,t.house,t.site,t.build,t.owner=nil,nil,nil,nil,nil
  end
  local function read(x,y)
    local id=Sim.id(x,y)
    local t=id and s.tiles[id]
    if not t then return end
    local slope,base,top=T.tile(s.corner_grid,x,y)
    return {kind=t.build and "road" or "clear",slope=slope,base=base,max_z=8*top,owner=t.owner,
      road_bits=t.road_bits or 0,road_town=t.road_town}
  end
  return s,m("town_generation_board")(Sim,T,s,G,W,read),Sim.id(start,z),Sim.id(finish,z)
end
local s,b,start,finish=state()
assert(T.tile(s.corner_grid,23,12)==3 and T.tile(s.corner_grid,27,12)==13)
-- Medium construction prices measured through the compiled native RC1
-- command on these same corners, as OWNER_TOWN after generation.
local R=m("openttd/terragenesis")(m("openttd/slope"))
local rng,raw={3348994613,436421385},0
local function rand()raw=raw+1;return R.next_random(rng) end
local approach=s.tiles[Sim.id(22,12)]
approach.build,approach.owner,approach.road_bits,approach.road_town="road","town",10,1
local obstacle=s.tiles[Sim.id(24,12)]
obstacle.build,obstacle.owner,obstacle.road_bits,obstacle.road_town="road","town",5,1
local proposal=b.road_span({id=1,population=0},23,12,2,rand)
assert(proposal and proposal.kind=="tunnel" and proposal.quote["end"]==finish)
local old_top,old_terrain=s.topology,s.corner_grid.revision
assert(not Sim.road_tunnel(s,"town",start,true,1), "Player/non-adapted call did not preserve existing rules")
local ok,price,quote=Sim.road_tunnel(s,"town",start,true,1,b.excavation)
assert(ok and quote["end"]==finish and quote.excavation and #quote.excavation.changes==1)
assert(quote.excavation.changes[1].height==1 and quote.excavation.changes[1].x==28 and quote.excavation.changes[1].z==12)
assert(price==3815)
assert(raw==0 and rng[1]==3348994613 and rng[2]==436421385 and s.topology==old_top and s.corner_grid.revision==old_terrain)
assert(T.corner(s.corner_grid,28,12)==2 and not s.stock_road_tunnels)
assert(Sim.road_tunnel(s,"town",start,false,1,b.excavation,rand))
assert(T.tile(s.corner_grid,27,12)==12 and raw==8 and rng[1]==396377203 and rng[2]==2936347255)
assert(s.tiles[finish].build=="stock_road_tunnel" and s.tiles[finish].road_town==1)
assert(s.stock_road_tunnels[1].excavation==nil and s.stock_road_tunnels[1].base==1)
assert(s.tunnel_below[Sim.id(26,12)]==1 and T.corner(s.corner_grid,26,12)==2)
local bad,c,a=state()
bad.tiles[Sim.id(28,11)].owner="Other owner"
assert(not Sim.road_tunnel(bad,"town",a,false,1,c.excavation,rand))
assert(not bad.stock_road_tunnels and T.corner(bad.corner_grid,28,12)==2 and raw==8)
print("PASS RC1 town tunnel exit lowers only the shared raised corner, charges it once, and will not excavate protected terrain")

if core then
  for _,kind in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..kind,"air") end
  core.register_on_mods_loaded(function()
    core.after(0,function()
      core.log("action","TOWN_TUNNEL_EXCAVATION_NATIVE_PASS")
      core.request_shutdown("Town tunnel QA complete",false,0)
    end)
  end)
end
