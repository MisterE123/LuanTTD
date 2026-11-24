-- Isolated real Luanti rendering: build raised terminal foundations and a
-- true incline, run the stock pilot and inspect the body pose.
local terrain_grade=dofile(mod.."/openttd/terrain.lua")
local owner="PierQA"
local depot_x,route_x,ramp_z=21,24,17
local grid=S.corner_grid
for z=1,Sim.H+1 do for x=1,Sim.W+1 do
  local h=z>ramp_z and 2 or 1
  if x==depot_x and z==15 then h=0 end
  if x==route_x+1 and z==21 then h=1 end
  grid.levels[(z-1)*(Sim.W+1)+x]=h
end end
for z=1,Sim.H do for x=1,Sim.W do
  local id=Sim.id(x,z)
  local _,base=terrain_grade.tile(grid,x,z)
  S.tiles[id]={terrain="grass",variant=(x+z)%4,h=base}
end end
S.sites,S.stock_farm_fields={},{}
S.speed=0
api.tram_clock=function()end
local function at(x,z) return assert(Sim.id(x,z)) end
local net,run=api.tram.network,api.tram.run
local company=Sim.company(S,owner);company.cash=200000
local depot,first,last,ramp=at(depot_x,15),at(route_x,13),at(route_x,21),at(route_x,ramp_z)
local function construct(kind,tiles,arg)
  assert(net.construct(S,owner,kind,tiles,arg))
end
construct("road",Sim.line(at(depot_x+1,15),at(route_x,15)))
assert(S.tiles[at(depot_x+1,15)].tram.tram_bits==2)
local served,price=net.construct(S,owner,"depot",{depot},2)
assert(served and served[2]==at(depot_x+1,15) and price==940)
assert(S.tiles[at(depot_x+1,15)].tram.tram_bits==10)
construct("road",Sim.line(at(route_x,12),at(route_x,22)))
construct("drive_stop",{first},1)
construct("drive_stop",{last},1)
local pilot=assert(run.start(S,owner,depot,first,last))
local wanted={x=2*route_x+.5,y=2,z=2*ramp_z+.5}
local camera={x=wanted.x+6,y=4.4,z=wanted.z-3.8}
local function place_camera(p)
  p:set_pos(camera)
  local dx,dy,dz=wanted.x-camera.x,wanted.y-camera.y-1.625,wanted.z-camera.z
  p:set_look_horizontal(math.atan2(-dx,dz))
  p:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
end
local ready
core.register_on_joinplayer(function(p)
  if p:get_player_name()~=owner then return end
  core.emerge_area({x=37,y=-1,z=20},{x=61,y=12,z=48},function(_,_,left)
    if left~=0 or ready then return end
    place_camera(p)
    local dirty={}
    for x=19,29 do for z=11,23 do dirty[#dirty+1]=at(x,z) end end
    api.render.update(dirty)
    assert(S.tiles[depot].tram.terminal_level==1)
    assert(S.tiles[last].tram.terminal_level==2)
    assert(core.get_node({x=42,y=2,z=30}).name=="luanttd_core:tram_depot_2")
    assert(core.get_node({x=48,y=3,z=42}).name=="luanttd_core:tram_stop_1")
    assert(core.get_node({x=48,y=2,z=34}).name=="luanttd_core:road_grade_6")
    assert(core.get_node({x=48,y=3,z=34}).name=="luanttd_core:tramway_grade_6")
    local function grade_object()
      for _,object in ipairs(core.get_objects_inside_radius(wanted,3)) do
        local e=object:get_luaentity()
        if e and e.name=="luanttd_core:tram_preview_vehicle" then return object end
      end
    end
    for _=1,4000 do
      run.advance(S,1)
      local f=run.frame(pilot)
      if f and f[4]==ramp and f[2]%16>=5 and f[2]%16<=11 then
        api.interest.refresh({p})
        api.tram_view.step(.2,true)
        local ref=assert(grade_object())
        local pos,rot=ref:get_pos(),ref:get_rotation()
        assert(pos.y>1.75 and pos.y<2.28 and rot.x<-.3)
        ready=true
        core.log("action","TRAM_GRADE_NATIVE_READY rendered terminal foundations, automatic entrance rail, graded wire and streetcar pitch")
        break
      end
    end
    assert(ready,"No actual native uphill pose")
  end)
end)
local seen
core.register_globalstep(function()
  if not ready then return end
  local f=io.open(core.get_worldpath().."/pier-view.txt","r")
  if not f then return end
  local view=f:read("*l")
  f:close()
  if not view or view==seen then return end
  seen=view
  local p=core.get_player_by_name(owner)
  if p then
    if view=="tram" then place_camera(p)
    else
      local x,z,y=2*route_x+.5,42.5,2.7
      if view=="depot" then x,z,y=42.5,30.5,1.8 end
      wanted,camera={x=x,y=y,z=z},{x=x+5,y=y+2.5,z=z+4}
      place_camera(p)
    end
  end
  core.log("action","TRAM_GRADE_NATIVE_VIEW "..view)
end)
