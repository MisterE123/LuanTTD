-- Native rendering test: a real-generated worker map, actual node meshes,
-- native per-client particles, real fixed-camera graphical captures.
local QA={enabled=false,active={},adds=0,deletions=0}
local add,remove=core.add_particlespawner,core.delete_particlespawner
function core.add_particlespawner(spec)
  local texture=spec.texture
  local smoke=spec.playername=="IndustrySmokeQA" and type(texture)=="table" and
    texture.name:find("bl_industry_smoke.png",1,true)==1
  if smoke and not QA.enabled then return -1 end
  local handle=add(spec)
  if smoke then
    assert(spec.time==0 and handle>=0)
    QA.active[handle]=spec;QA.adds=QA.adds+1
  end
  return handle
end
function core.delete_particlespawner(handle,name)
  remove(handle,name)
  if QA.active[handle] then
    assert(name=="IndustrySmokeQA")
    QA.active[handle]=nil;QA.deletions=QA.deletions+1
  end
end
local function test()
  local p=core.get_player_by_name("IndustrySmokeQA")
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.2,test);return
  end
  if not QA.paused then
    local sent=authority.query({kind="company",player=p:get_player_name()},function(company)
      assert(company.ok)
      assert(authority.query({kind="command",player=p:get_player_name(),
        command={kind="speed",speed=0,revision=company.revision}},function(r)
        assert(r.ok,r.why)
        QA.paused=true
        core.after(.35,test)
      end))
    end)
    if not sent then core.after(.2,test) end
    return
  end
  local disk=assert(OwnerCheckpoint.read())
  local chosen={}
  for id,tile in ipairs(disk.tiles) do
    local b=tile.stock_industry
    if b and b.style=="power_station" and b.x==1 and b.z==1 then
      local x,z=Sim.xy(id)
      local own=disk.stock_coal_industries[b.id]
      assert(own and own.kind=="power_station")
      local t2=disk.tiles[Sim.id(x+1,z)]
      assert(t2.stock_industry and t2.stock_industry.id==b.id and t2.stock_industry.x==2)
      chosen={{x=2*x+.48,y=tile.h+3.914,z=2*z+.10,base=tile.h,tx=x,tz=z},
              {x=2*x+2.34,y=t2.h+4.054,z=2*z+.10,base=t2.h,tx=x+1,tz=z}}
      break
    end
  end
  assert(#chosen==2,"Generated map did not include the stock power station")
  local a,b=chosen[1],chosen[2]
  local function camera(high)
    p:set_pos({x=(a.x+b.x)*.5,y=a.y+(high and 53 or -2.55),z=a.z-8.4})
    p:set_look_horizontal(0);p:set_look_vertical(-.19)
  end
  local function painted()
    local n=core.get_node_or_nil({x=a.tx*2,y=a.base+1,z=a.tz*2})
    return n and n.name=="luanttd_core:power_station_1_1"
  end
  local function count()
    local n=0
    for _,spec in pairs(QA.active) do
      local q=spec.pos
      for _,rim in ipairs(chosen) do
        if math.abs((q.min.x+q.max.x)*.5-rim.x)<.0001 and math.abs((q.min.z+q.max.z)*.5-rim.z)<.0001 then
          assert(math.abs(q.min.y-rim.y)<.0001 and spec.vel.min.y>0)
          n=n+1
        end
      end
    end
    assert(n<=2,"Duplicate spawners for the same power stacks")
    return n
  end
  local function wait_for(check,done,reason,n)
    if check() then done()
    elseif n<95 then core.after(.2,function() wait_for(check,done,reason,n+1) end)
    else error(reason) end
  end
  camera()
  wait_for(painted,function()
    core.after(1,function()
      core.log("action","INDUSTRY_SMOKE_BASELINE: the smoke-free, fully painted worker power station")
      core.after(2.5,function()
        QA.enabled=true
        wait_for(function() return count()==2 end,function()
          core.after(1.9,function()
            assert(count()==2)
            core.log("action","INDUSTRY_SMOKE_ONSCREEN: native transparent plumes from the two painted chimney rims")
            core.after(2.1,function()
              camera(true)
              wait_for(function() return count()==0 end,function()
                assert(QA.deletions>=2)
                camera()
                wait_for(function() return count()==2 end,function()
                  core.log("action","PASS NATIVE WORKER INDUSTRY SMOKE: both rims, stable view, culled at distance, and recreated on return")
                end,"power stacks did not restart when returning",1)
              end,"out-of-view smoke kept spawning",1)
            end)
          end)
        end,"power stacks did not create native plumes",1)
      end)
    end)
  end,"stock power station was never painted",1)
end
core.after(.2,test)
