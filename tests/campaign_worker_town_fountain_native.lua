-- Observe real, player-targeted Luanti spawners without replacing their engine implementations.
local FountainProbe={handles={},adds={},deletions=0}
local native_add_spawner,native_delete_spawner=core.add_particlespawner,core.delete_particlespawner
function core.add_particlespawner(spec)
  local handle=native_add_spawner(spec)
  if spec.playername=="TownFountainQA" and type(spec.texture)=="table" and
      spec.texture.name=="bl_fountain_droplet.png" then
    assert(handle>=0 and spec.time==0,"Luanti failed to create a permanent fountain spawner")
    FountainProbe.handles[handle]=spec
    FountainProbe.adds[#FountainProbe.adds+1]=spec
  end
  return handle
end
function core.delete_particlespawner(handle,name)
  native_delete_spawner(handle,name)
  if FountainProbe.handles[handle] then
    assert(name=="TownFountainQA","A local fountain was not culled per client")
    FountainProbe.handles[handle]=nil
    FountainProbe.deletions=FountainProbe.deletions+1
  end
end
local function fountain_native()
  local p=core.get_player_by_name("TownFountainQA")
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.2,fountain_native);return
  end
  local disk=assert(OwnerCheckpoint.read())
  local selected
  for id,tile in ipairs(disk.tiles) do
    local rec=tile.house and tile.source_house
    if rec and rec.completed and rec.id==0x0A then
      local x,z=Sim.xy(id)
      selected={x=x*2+.5,y=tile.h,z=z*2+.5}
      break
    end
  end
  assert(selected,"Generated test town has no completed stock fountain")
  local function add_count()
    local n=0
    for _,spec in ipairs(FountainProbe.adds) do
      if math.abs(spec.pos.min.x-selected.x)<.04 and math.abs(spec.pos.min.z-selected.z)<.04 then
        assert(math.abs(spec.pos.min.y-(selected.y+1.365))<.001,"Fountain droplets misplaced vertically")
        n=n+1
      end
    end
    return n
  end
  local function live()
    local n=0
    for _,spec in pairs(FountainProbe.handles) do
      if math.abs(spec.pos.min.x-selected.x)<.04 and math.abs(spec.pos.min.z-selected.z)<.04 then n=n+1 end
    end
    assert(n<=1,"Fountain has duplicate client spawners")
    return n==1
  end
  local function camera()
    p:set_pos({x=selected.x,y=selected.y+1.15,z=selected.z-2.8})
    p:set_look_horizontal(0);p:set_look_vertical(.47)
  end
  local function wait_for(check,next_,reason,n)
    if check() then next_()
    elseif n<65 then core.after(.2,function() wait_for(check,next_,reason,n+1) end)
    else error(reason) end
  end
  camera()
  wait_for(live,function()
    assert(add_count()==1)
    core.log("action","TOWN_FOUNTAIN_WORKER_VISIBLE: real stock town mesh plus native per-player spawner")
    core.after(3,function()
      assert(live() and add_count()==1,"Stationary viewer's fountain spawner churned")
      -- Move vertically: distant viewing must not keep spawning droplets
      -- merely because the terrain projection keeps the same 2D sectors.
      p:set_pos({x=selected.x,y=selected.y+46,z=selected.z-2.8})
      wait_for(function() return not live() end,function()
        assert(FountainProbe.deletions>0)
        camera()
        wait_for(live,function()
          assert(add_count()==2)
          core.log("action","PASS NATIVE WORKER TOWN FOUNTAIN: stable while nearby, culled beyond view, reissued once on return")
        end,"Fountain failed to restart when reentering",1)
      end,"Fountain did not stop when the player flew away",1)
    end)
  end,"Worker town never showed the fountain spawner",1)
end
core.after(.2,fountain_native)
