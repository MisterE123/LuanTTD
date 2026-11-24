-- Appended to the real Luanti game only in this isolated visual test.
local owner="PierQA"
local terrain_model=dofile(mod.."/openttd/terrain.lua")
local grid=S.corner_grid
for i=1,#grid.levels do grid.levels[i]=1 end
for id=1,Sim.W*Sim.H do S.tiles[id]={terrain="grass",h=1,variant=id%4} end
S.sites,S.stock_farm_fields={},{}
S.speed=0
api.tram_clock=function() end
local function at(x,z) return assert(Sim.id(x,z)) end
local c=Sim.company(S,owner)
c.cash=200000
local rails=assert(api.rail_build)
local rq=assert(rails.quote_track(owner,at(24,12),at(24,21),1,false))
assert(rails.build(owner,rq))
local net,run=api.tram.network,api.tram.run
local crossing=at(24,16)
local depot,west,east=at(19,18),at(20,16),at(27,16)
local function build(kind,tiles,axis)
  local ids,why=net.construct(S,owner,kind,tiles,axis)
  assert(ids,why)
end
build("depot",{depot},3)
build("road",Sim.line(at(18,16),at(29,16)))
build("road",Sim.line(at(19,16),at(19,17)))
build("road",{at(19,17)},4)
build("drive_stop",{west},0)
build("drive_stop",{east},0)
S.stock_rail_dispatch=S.stock_rail_dispatch or {}
S.stock_rail_dispatch.life=S.stock_rail_dispatch.life or {bits={}}
S.stock_rail_dispatch.life.bits[crossing]=2
Sim.refresh_crossing_construction(S)
assert(S.tiles[crossing].level_crossing.barred)
local pilot=assert(run.start(S,owner,depot,west,east))
local wanted={x=48,y=1.9,z=32.5}
local camera={x=53.6,y=4.5,z=27.6}
local ready
local function aim(p)
  p:set_pos(camera)
  local dx,dy,dz=wanted.x-camera.x,wanted.y-camera.y-1.625,wanted.z-camera.z
  p:set_look_horizontal(math.atan2(-dx,dz))
  p:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
end
local function paint(p)
  local changed={}
  for x=17,30 do for z=12,22 do changed[#changed+1]=at(x,z) end end
  api.render.update(changed)
  api.interest.refresh({p})
  api.tram_view.step(.2,true)
end
local function verify_art(closed)
  local bark=core.get_node({x=48,y=2,z=32}).name
  assert(bark=="luanttd_core:level_crossing_1_"..(closed and "closed" or "open"),bark)
  local wire=core.get_node({x=48,y=3,z=32}).name
  assert(wire=="luanttd_core:tramway_crossing_0",wire)
end
core.register_on_joinplayer(function(p)
  if p:get_player_name()~=owner then return end
  core.emerge_area({x=35,y=-1,z=22},{x=61,y=12,z=45},function(_,_,left)
    if left~=0 or ready then return end
    aim(p)
    for _=1,7000 do
      run.advance(S,1)
      if pilot.crossing_wait then break end
    end
    assert(pilot.crossing_wait=="CROSSING_BARRED")
    assert(run.frame(pilot)[4]==at(23,16))
    paint(p)
    verify_art(true)
    ready=true
    core.log("action","TRAM_CROSSING_NATIVE_READY stock tram waits outside a locally reserved railway")
  end)
end)
local seen
core.register_globalstep(function()
  if not ready then return end
  local marker=io.open(core.get_worldpath().."/pier-view.txt","r")
  if not marker then return end
  local view=marker:read("*l");marker:close()
  if not view or view==seen then return end
  seen=view
  local p=assert(core.get_player_by_name(owner))
  if view=="tram_crossing" then
    S.stock_rail_dispatch.life.bits[crossing]=nil
    Sim.refresh_crossing_construction(S)
    assert(not S.tiles[crossing].level_crossing.barred)
    for _=1,7000 do
      run.advance(S,1)
      local f=run.frame(pilot)
      if f[4]==crossing and f[1]%16>=6 and f[1]%16<=10 then break end
    end
    assert(run.frame(pilot)[4]==crossing and not pilot.crossing_wait)
    paint(p)
    verify_art(false)
  end
  if view=="tram_modal" then
    assert(run.clear(S,owner))
    assert(world.go_menu(p,"roads"))
    local index
    for i,j in ipairs(world.hotbar_layout(p)) do if j==9 then index=i end end
    assert(index)
    p:set_pos({x=48.5,y=8.5,z=32.5})
    p:set_look_horizontal(0);p:set_look_vertical(math.pi/2-.002)
    local show=core.show_formspec
    core.show_formspec=function(n,name,form)
      if n==owner and form:find("Remove tram tracks",1,true) then
        assert(S.tiles[crossing].level_crossing.tramtype==1 and form:find("Remove the railway",1,true))
        core.log("action","TRAM_CROSSING_NATIVE_MODAL road and tram remain untouched until a layer is confirmed")
        core.show_formspec=show
      end
      return show(n,name,form)
    end
    core.log("action","TRAM_CROSSING_NATIVE_SLOT "..(index==10 and 0 or index))
  elseif view=="tram_remove_rail" then
    local t=S.tiles[crossing]
    assert(not t.level_crossing and not t.rail_tracks and t.tram and t.tram.tram_bits==10)
    assert(core.get_node({x=48,y=2,z=32}).name=="luanttd_core:tramway_10")
    core.log("action","TRAM_CROSSING_NATIVE_RAIL_REMOVE actual confirmation preserved tramway")
    aim(p)
  else aim(p) end
  core.log("action","TRAM_CROSSING_NATIVE_VIEW "..view)
end)
