-- Actual native registered bridge and portal assets beneath original fitted
-- wires. The authority executes the same construction gesture as the game.
local owner="PierQA"
local Terrain=dofile(mod.."/openttd/terrain.lua")
local function at(x,z) return assert(Sim.id(x,z)) end
local grid=S.corner_grid
for z=1,Sim.H+1 do for x=1,Sim.W+1 do
  grid.levels[(z-1)*(Sim.W+1)+x]=(x>=24 and x<=27 and z>=21 and z<=29) and 1 or 0
end end
for z=1,Sim.H do for x=1,Sim.W do
  local _,h=Terrain.tile(grid,x,z)
  local water=z==12 and x>=24 and x<=26
  S.tiles[at(x,z)]={h=h,terrain=water and "water" or "grass",variant=(x+z)%4,
    water_class=water and "sea" or nil}
end end
S.sites,S.stock_farm_fields={},{}
S.speed=0
api.tram_clock=function()end
local company=Sim.company(S,owner)
company.cash=200000
assert(Sim.road_bridge(S,owner,at(23,12),at(27,12),0))
assert(Sim.road_tunnel(S,owner,at(23,25)))
local cap=api.capabilities
local R=dofile(mod.."/campaign_authority_runtime.lua")(Sim,mod,S,cap)
local E=dofile(mod.."/campaign_authority_endpoint.lua")(Sim,R)
for _,z in ipairs({12,25}) do
  local q=E.road_place(owner,{tool="tram_lay",axis=0,first=at(23,z),start_half=false,end_half=false})
  assert(q.ok,q.why or q.note)
  for _,item in ipairs({{21,22},{28,29}}) do
    assert(R.tram.net.construct(S,owner,"road",Sim.line(at(item[1],z),at(item[2],z))))
  end
  assert(R.tram.net.construct(S,owner,"road",{at(22,z)},2))
  assert(R.tram.net.construct(S,owner,"road",{at(28,z)},8))
end
local n,run=R.tram.net,R.tram.run
local depot,stop1,stop2=at(20,11),at(21,12),at(29,12)
assert(n.construct(S,owner,"depot",{depot},1))
assert(n.construct(S,owner,"road",Sim.line(at(19,12),at(21,12))))
assert(n.construct(S,owner,"road",{at(20,12)},1))
assert(n.construct(S,owner,"road",Sim.line(at(29,12),at(31,12))))
assert(n.construct(S,owner,"drive_stop",{stop1},0))
assert(n.construct(S,owner,"drive_stop",{stop2},0))
local pilot=assert(run.start(S,owner,depot,stop1,stop2))
local frame
for _=1,3700 do
  run.advance(S,1)
  frame=run.frame(pilot)
  if frame and frame[4]==at(25,12) and frame[1]%16>=7 then break end
end
assert(frame and frame[4]==at(25,12) and frame[12])
local camera={
  tram_bridge={{x=51,y=1.6,z=24.5},{x=44.2,y=5.6,z=16.5}},
  tram_tunnel={{x=46.7,y=.85,z=50.5},{x=41,y=3.6,z=44}},
}
local player,ready,seen
local function look(view)
  if not player then return end
  local w,c=unpack(camera[view])
  player:set_pos(c)
  local dx,dy,dz=w.x-c.x,w.y-c.y-1.625,w.z-c.z
  player:set_look_horizontal(math.atan2(-dx,dz))
  player:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
end
core.register_on_joinplayer(function(p)
  if p:get_player_name()~=owner then return end
  player=p
  core.emerge_area({x=37,y=-1,z=17},{x=62,y=10,z=57},function(_,_,left)
    if left~=0 or ready then return end
    local dirty={}
    for x=19,31 do for z=9,28 do dirty[#dirty+1]=at(x,z) end end
    api.render.update(dirty)
    local function name(x,y,z)return core.get_node({x=x,y=y,z=z}).name end
    assert(name(50,1,24):find("road_bridge_wood_span",1,true))
    assert(name(50,2,24)=="luanttd_core:tramway_10")
    assert(name(46,2,24)=="luanttd_core:tramway_grade_3")
    assert(name(54,2,24)=="luanttd_core:tramway_grade_12")
    assert(name(46,1,50):find("road_tunnel_portal",1,true))
    assert(name(46,2,50)=="luanttd_core:tramway_crossing_0")
    assert(name(54,2,50)=="luanttd_core:tramway_crossing_0")
    assert(name(50,2,50)~="luanttd_core:tramway_crossing_0")
    look("tram_bridge")
    api.interest.refresh({p})
    api.tram_view.step(.2,true)
    local streetcar
    for _,obj in ipairs(core.get_objects_inside_radius({x=50.5,y=1.52,z=24.5},2)) do
      local ent=obj:get_luaentity()
      if ent and ent.name=="luanttd_core:tram_preview_vehicle" then streetcar=obj end
    end
    assert(streetcar and math.abs(streetcar:get_pos().y-1.52)<.005,
      "the real electric streetcar must run on the deck, not on the lower ground")
    ready=true
    core.log("action","TRAM_SPAN_NATIVE_READY real streetcar on deck; rails and catenary on both ramps/portals; no overlay on the hill")
  end)
end)
core.register_globalstep(function()
  if not ready then return end
  local f=io.open(core.get_worldpath().."/pier-view.txt","r")
  if not f then return end
  local view=f:read("*l");f:close()
  if view and view~=seen and camera[view] then
    seen=view;look(view)
    core.log("action","TRAM_SPAN_NATIVE_VIEW "..view)
  end
end)
