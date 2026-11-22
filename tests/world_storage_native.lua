-- Disposable game for testing the binary snapshot through Luanti's async VM.
local path=core.get_modpath(core.get_current_modname())
local W=dofile(path.."/world_storage.lua")
core.register_alias("mapgen_stone","air")
core.register_alias("mapgen_water_source","air")
local world=W.new(4096,4096,{seed=24680,base_id="native.roundtrip/1",
  corner=function(seed,x,z) return (seed+x+z)%2 end,
  tile=function(seed,x,z) return seed+x+z end})
assert(W.commit(world,0,{
  {kind="tile",x=32,z=4,value=0},
  {kind="tile",x=33,z=4,value=4294967295},
})==1)

local function worker(s)
  -- Run as a serialized function with no main-VM upvalues or trusted ticket.
  assert(core.get_player_by_name==nil,"job is not running in the async VM")
  assert(s.x==32 and s.z==4 and s.width==2 and s.depth==1)
  assert(s.schema=="luanttd-world-job/1" and s.base_id=="native.roundtrip/1")
  assert(s.tiles==string.rep(string.char(0),4)..string.rep(string.char(255),4))
  assert(s.corners==string.char(0,1,0,1,0,1))
  return {{kind="tile",x=33,z=4,value=234}}
end

core.register_on_mods_loaded(function()
  local stale,expired=W.snapshot(world,32,4,33,4)
  core.handle_async(worker,function(patch)
    local rev,why=W.apply_job(world,expired,patch)
    assert(rev==nil and why:find("stale",1,true))
    local fresh,ticket=W.snapshot(world,32,4,33,4)
    core.handle_async(worker,function(result)
      local new,changed=W.apply_job(world,ticket,result)
      assert(new==3 and changed and W.get_tile(world,33,4)==234 and W.stats(world).chunks==2)
      core.log("action","LUANTTD WORLD STORAGE ASYNC PASS")
      core.request_shutdown("Async storage assertions finished",false,0)
    end,fresh)
  end,stale)
  assert(W.commit(world,1,{{kind="tile",x=33,z=25,value=6}})==2)
end)
