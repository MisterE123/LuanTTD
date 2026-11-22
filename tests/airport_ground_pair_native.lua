-- Appended only in an isolated test copy of the native game, not mounted
-- as a public pair or two-airline commercial runtime.
local source=mod.."/openttd/"
local Terrain=dofile(source.."terrain.lua")
local Small=dofile(source.."airport_small.lua")
local Motion=dofile(source.."airport_motion.lua")(Small)
local Network=dofile(mod.."/airport_network.lua")(Sim,Terrain,Small)
local Pair=dofile(mod.."/airport_ground_pair.lua")(Sim,Small,Motion,Terrain)
local Art=dofile(mod.."/airport_airframe_art.lua").sampson
local Visual=dofile(mod.."/road_motion.lua")
local owner="Paired Sampson QA"
local id=Sim.id
local function test()
  local stage=S.airport_pair_native
  local pair=Pair.current(S)
  local function step()
    local events,why=Pair.advance(S,nil,(pair.last_world_tick or 0)+1)
    assert(events and not why,why)
    return events
  end
  if stage then
    assert(pair.owner==owner and pair.ticks==1109)
    local hub=S.stock_small_airports[stage.hub]
    assert(hub.flags==Small.block.BUSY+Small.block.TERM1)
    assert(pair.actors[1].phase=="holding" and pair.actors[2].phase=="rollout")
    local first_release,second_approach
    while pair.actors[1].phase~="terminal" or pair.actors[2].phase~="terminal" do
      for _,e in ipairs(step()) do
        if e.airport==hub.id and e.vehicle==2 and Small.has(e.flags,Small.block.BUSY) and
            not Small.has(e.after_flags,Small.block.BUSY) then first_release=e.world_tick end
        if e.airport==hub.id and e.vehicle==1 and e.kind=="approach" then second_approach=e.world_tick end
      end
      assert(pair.ticks<5000)
    end
    assert(first_release==1133 and second_approach==1984)
    assert(hub.flags==Small.block.TERM1+Small.block.TERM2)
    local mounted=assert(core.registered_entities[Art.entity]).initial_properties
    assert(mounted.mesh==Art.mesh and mounted.textures[1]==Art.atlas)
    for _,p in ipairs(pair.actors) do
      local pos,yaw=Pair.pose(p)
      assert(pos.y==.5 and not p.vehicle.hidden)
      local ob=assert(core.add_entity(pos,Art.entity))
      ob:set_rotation({x=0,y=Visual.nose_yaw(yaw),z=0})
      local prop=ob:get_properties()
      assert(prop.mesh==Art.mesh and math.abs(prop.visual_size.x-Art.scale)<1e-6 and
        math.abs(prop.visual_size.y-Art.scale)<1e-6 and math.abs(prop.visual_size.z-Art.scale)<1e-6)
      assert(math.abs(ob:get_pos().y-pos.y)<1e-6)
      assert(Pair.request_return(S,owner,p.id))
    end
    assert(pair.actors[1].last_terminal_tile~=pair.actors[2].last_terminal_tile)
    local waits=0
    while pair.actors[1].phase~="returned" or pair.actors[2].phase~="returned" do
      for _,e in ipairs(step()) do
        if e.airport==hub.id and e.kind=="blocked" and Small.has(e.flags,Small.block.BUSY) then waits=waits+1 end
      end
      assert(pair.ticks<10000)
    end
    assert(hub.flags==0 and waits==584)
    assert(S.stock_small_airports[stage.origin_a].flags==Small.block.TERM1)
    assert(S.stock_small_airports[stage.origin_b].flags==Small.block.TERM1)
    core.log("action",("AIRPORT_PAIR_NATIVE_PASS release=%d inbound=%d taxi_waits=%d mesh_scale=%.2f"):format(
      first_release,second_approach,waits,Art.scale))
    core.request_shutdown("Both real Sampsons cleared the saved country runway",false,0)
    return
  end
  assert(api.airport_tools and not pair)
  for i=1,#S.corner_grid.levels do S.corner_grid.levels[i]=0 end
  for _,t in ipairs(S.tiles) do t.terrain,t.h,t.build,t.owner,t.wood,t.house,t.site="grass",0,nil,nil,nil,nil,nil end
  local a=assert(Network.build(S,owner,id(7,13)))
  local b=assert(Network.build(S,owner,id(32,13)))
  local hub,dirty=Network.build(S,owner,id(22,13));assert(hub,dirty)
  api.render.update(dirty)
  pair=assert(Pair.start(S,owner,a.id,b.id,hub.id))
  for _=1,5000 do
    for _,e in ipairs(step()) do
      if e.airport==hub.id and e.vehicle==1 and e.kind=="hold" and Small.has(e.flags,Small.block.BUSY) then
        assert(pair.ticks==1109)
        S.airport_pair_native={origin_a=a.id,origin_b=b.id,hub=hub.id}
        api.save()
        core.log("action","AIRPORT_PAIR_NATIVE_SAVED_HOLD")
        core.request_shutdown("Saved the busy airport and its holding second aircraft",false,0)
        return
      end
    end
  end
  error("Stock runway queue not reached")
end
core.after(0,function()
  core.emerge_area({x=40,y=-1,z=24},{x=53,y=5,z=34},function(_,_,remaining)
    if remaining==0 then core.after(0,test) end
  end)
end)
