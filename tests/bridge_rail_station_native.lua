-- Disposable local graphical fixture. The production world renderer and
-- paid railway own the tile and entity output; only the starting land is fixed.
local owner="PierQA"
local terrain=dofile(mod.."/openttd/terrain.lua")
local constructor=assert(api.rail_build)
local function id(x,z) return assert(Sim.id(x,z)) end
local depot=id(7,22)
local grid=terrain.new(Sim.W,Sim.H,function(_,z)
  return (z<=18 or z>=28) and 2 or (z==19 or z==27) and 1 or 0
end)
S.corner_grid.levels=grid.levels
local dirty={}
for z=1,Sim.H do for x=1,Sim.W do
  local _,base=terrain.tile(S.corner_grid,x,z)
  S.tiles[id(x,z)]={terrain="grass",variant=(x+z)%4,h=base}
  if x>=4 and x<=30 and z>=16 and z<=30 then dirty[#dirty+1]=id(x,z) end
end end
S.speed=0
local cash=Sim.company(S,owner)
cash.cash=200000
local function place(q,note) assert(q,note);assert(constructor.build(owner,q));return q end
local road,why,_,level=Sim.road_bridge(S,owner,id(14,18),id(14,27),0,false)
assert(road,why);assert(level==2,level)
api.render.raise_bound(level)
place(constructor.quote_track(owner,id(8,22),id(27,22),0,false))
place(constructor.quote_depot(owner,depot,2))
local short={axis=0,drag=false,tracks=1,length=3}
local roof={axis=0,drag=false,tracks=2,length=5}
place(constructor.quote_station(owner,id(13,22),id(13,22),short))
place(constructor.quote_station(owner,id(23,22),id(23,22),roof))
local west,east=S.tiles[id(14,22)].rail_station_id,S.tiles[id(24,22)].rail_station_id
assert(S.tiles[id(14,22)].rail_station_gfx==2 and S.tiles[id(24,22)].rail_station_gfx==4 and S.tiles[id(24,23)].rail_station_gfx==6)
local guide=Sim.company(S,owner)
S.sites[1].tile,S.sites[2].tile=id(13,25),id(25,26)
for _,z in ipairs({24,25,26}) do for _,x in ipairs({12,13,14,15,23,24,25,26}) do
  local tile=S.tiles[id(x,z)]
  tile.house,tile.parcel,tile.variant=true,"shop",2
end end
local ready,unit,paid,standing
local function draw_train()
  api.interest.refresh({{get_pos=function() return {x=32,z=45} end}})
  api.rail_dispatch_view.step(.2,true,1)
end
local function day()
  Sim.daily(S)
  local s=assert(Sim.rail_paid_status(S,unit.id))
  if s.loading and s.onboard>0 then standing=true end
  if s.delivered>0 and s.fare>0 then paid=s end
  assert(not api.rail_dispatch_controller.current(S).failure,api.rail_dispatch_controller.current(S).failure)
end
core.register_on_joinplayer(function(p)
  if p:get_player_name()~=owner then return end
  local a,b={x=8,y=-1,z=32},{x=61,y=8,z=63}
  core.emerge_area(a,b,function(_,_,left)
    if left~=0 then return end
    api.render.update(dirty)
    local function n(x,y,z)
      return core.get_node({x=2*x,y=y,z=2*z}).name
    end
    assert(n(14,2,22):find("stock_road_bridge_wood",1,true),n(14,2,22))
    assert(n(14,1,22)=="luanttd_core:rail_station_gfx_2",n(14,1,22))
    assert(n(24,1,22)=="luanttd_core:rail_station_gfx_4" and n(24,1,23)=="luanttd_core:rail_station_gfx_6")
    assert(n(23,1,22)=="luanttd_core:rail_station_gfx_0" and n(27,1,23)=="luanttd_core:rail_station_gfx_0")
    for _,gfx in ipairs({0,2,4,6}) do
      local node=assert(core.registered_nodes["luanttd_core:rail_station_gfx_"..gfx])
      assert(node.walkable and node.mesh=="bl_rail_station_gfx_"..gfx..".obj")
    end
    local O=assert(api.rail_owned)
    unit=assert(O.commit(S,owner,assert(O.quote(S,owner,depot,{0,27}))))
    local run,note=O.start(S,owner,unit.id,west,east);assert(run,note)
    for _=1,100 do
      day()
      if standing then break end
    end
    assert(standing,"A native train never loaded at the covered route")
    draw_train()
    p:hud_set_flags({crosshair=false})
    p:override_day_night_ratio(.92)
    ready=true
    core.log("action","BRIDGE_RAIL_STATION_NATIVE_READY loaded a signal-free purchased train at a real platform below a solid bridge deck")
  end)
end)
local last
core.register_globalstep(function()
  if not ready then return end
  local p=core.get_player_by_name(owner)
  local f=io.open(core.get_worldpath().."/pier-view.txt","r")
  if not f or not p then if f then f:close() end;return end
  local mode=f:read("*l");f:close()
  if last==mode or (mode~="underpass" and mode~="canopy" and mode~="fare") then return end
  last=mode
  local x,z=mode=="underpass" and 14 or 25,22
  if mode=="fare" then
    for _=1,160 do day();if paid then break end end
    assert(paid and paid.delivered>0 and guide.revenue>0)
    core.log("action",("BRIDGE_RAIL_STATION_NATIVE_FARE passengers=%d fare=$%d"):format(paid.delivered,paid.fare))
  end
  local from={x=x*2+(mode=="canopy" and 4.5 or -5.4),y=mode=="underpass" and -.53 or 2.65,z=z*2-3.6}
  local to={x=2*x+.5,y=mode=="underpass" and 1.1 or 1.01,z=2*z+1.45}
  local dx,dy,dz=to.x-from.x,to.y-from.y-1.625,to.z-from.z
  p:set_pos(from)
  p:set_look_horizontal(math.atan2(-dx,dz))
  p:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
  draw_train()
  core.log("action","BRIDGE_RAIL_STATION_NATIVE_VIEW "..mode)
end)
