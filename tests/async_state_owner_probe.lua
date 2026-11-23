-- Load this fixture both as the test mod and in each engine worker.
-- Production campaign state is not routed through this experiment.
local mod=assert(core.get_modpath(core.get_current_modname()))
local W=dofile(mod.."/world_storage.lua")
local inbox,outbox="owner_probe:in","owner_probe:out"
if not core.get_player_by_name then
  function core.sector_owner_probe(allow_idle)
    -- This is the only VM that constructs or mutates this sparse world.
    local world=W.new(4096,4096,{seed=1751,base_id="test.flat/1",
      corner=function() return 0 end,tile=function() return 0 end})
    local sequence=0
    core.ipc_set(outbox,{sequence=0})
    while core.ipc_poll(inbox,650) do
      local cmd=assert(core.ipc_get(inbox))
      core.ipc_set(inbox,nil)
      assert(cmd.sequence==sequence+1)
      sequence=cmd.sequence
      if cmd.kind=="stop" then return "stopped",sequence end
      local accepted=cmd.kind=="edit" and W.commit(world,cmd.revision,
        {{kind="corner",x=cmd.at,z=cmd.at,value=1}})
      local s=W.snapshot(world,cmd.at-1,cmd.at-1,cmd.at+1,cmd.at+1)
      assert(#s.corners==16 and #s.tiles==36)
      core.ipc_set(outbox,{sequence=sequence,accepted=accepted,
        revision=s.revision,corner=W.snapshot_corner(s,cmd.at,cmd.at),
        first=W.get_corner(world,2048,2048)})
    end
    assert(allow_idle,"worker lost its owner commands")
    return "idle",sequence
  end
  return
end
core.register_async_dofile(mod.."/init.lua")
for _,group in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..group,"air") end
local function worker(allow_idle) return core.sector_owner_probe(allow_idle) end
local function wait_receipt(expected,done)
  local expires=core.get_us_time()+4000000
  local function poll()
    local m=core.ipc_get(outbox)
    if m then
      assert(m.sequence==expected)
      core.ipc_set(outbox,nil)
      done(m)
    else
      assert(core.get_us_time()<expires,"worker reply deadline expired")
      core.after(.01,poll)
    end
  end
  poll()
end
local function send(kind,n,rev,at,done)
  assert(not core.ipc_get(inbox))
  core.ipc_set(inbox,{kind=kind,sequence=n,revision=rev,at=at})
  if done then wait_receipt(n,done) end
end
core.register_on_mods_loaded(function()
  assert(core.handle_async(worker,function(reason,n)
    assert(reason=="stopped" and n==5 and not core.ipc_get(inbox))
    -- A fresh owner can reuse empty channel keys and time out on idle.
    assert(core.handle_async(worker,function(exit,empty)
      assert(exit=="idle" and empty==0 and not core.ipc_get(inbox) and not core.ipc_get(outbox))
      -- Shut the native server down while a third job is idle in IPC, not
      -- after all jobs have returned. Its finite wait must let teardown
      -- join the async worker without a server-side blocking poll.
      assert(core.handle_async(worker,function() end,true))
      wait_receipt(0,function()
        core.log("action","PASS NATIVE ASYNC OWNER: private 4096² sparse world persisted across commands; stale edit rejected; stopped and idle worker returned")
        core.request_shutdown("IPC assertions passed",false,0)
      end)
    end,true))
    wait_receipt(0,function() end)
  end,false))
  wait_receipt(0,function()
    send("edit",1,0,2048,function(a)
      assert(a.accepted==1 and a.first==1)
      send("edit",2,0,190,function(b)
        assert(not b.accepted and b.revision==1 and b.corner==0 and b.first==1)
        send("edit",3,1,190,function(c)
          assert(c.accepted==2 and c.corner==1 and c.first==1)
          send("read",4,2,2048,function(d)
            assert(d.revision==2 and d.corner==1)
            send("stop",5)
          end)
        end)
      end)
    end)
  end)
end)
