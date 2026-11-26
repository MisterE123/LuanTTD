local mod=assert(core.get_modpath("luanttd_core"))
core.set_mapgen_setting("mg_name","singlenode",true)
for _,node in ipairs({"stone","water_source","river_water_source"}) do
  core.register_alias("mapgen_"..node,"air")
end
core.after(0,function()
  assert(core.handle_async(function()
    local m=assert(core.get_modpath("luanttd_core"))
    local F=dofile(m.."/road_fleet_perf.lua")(m)
    local s=F.make(24,8)
    local base=F.backend(s,dofile(m.."/baseline_sim.lua"))
    local patch=F.backend(s,F.Sim)
    local function run(b)
      -- Sample production daily stepping inside Luanti's async VM. This
      -- timer excludes world setup, full parity checks, and async IPC.
      -- Collect before each run so reclamation from the other comparison
      -- world does not randomly land in a measured step.
      collectgarbage("collect")
      local t,c=core.get_us_time(),os.clock()
      b.sim.daily(b.world)
      return (core.get_us_time()-t)/1000,(os.clock()-c)*1000
    end
    local results={}
    for i=1,12 do
      local a,b,ac,bc
      if i%2==0 then b,bc=run(patch);a,ac=run(base) else a,ac=run(base);b,bc=run(patch) end
      local shown,moving,arrived=F.check({base,patch})
      assert(shown==192 and moving>=160,"the benchmark needs a large moving fleet")
      if i==12 then assert(arrived>=24,"the fleet must exercise actual station arrivals") end
      results[i]={a=a,b=b,ac=ac,bc=bc,shown=shown,moving=moving,arrived=arrived}
    end
    -- Untimed copies use the same two versions with a single counter in
    -- Sim's actual road-surface resolver, not an estimate based on a mock.
    local old=F.backend(s,dofile(m.."/profile_baseline_sim.lua"))
    local new=F.backend(s,dofile(m.."/profile_current_sim.lua"))
    for _=1,4 do old.sim.daily(old.world);new.sim.daily(new.world) end
    F.check({old,new})
    results.calls={old=old.sim.perf_road_shape_calls,new=new.sim.perf_road_shape_calls}
    assert(results.calls.new<=results.calls.old)
    return results
  end,function(results)
    assert(results and #results==12,"native road fleet harness did not complete")
    local a,b,ac,bc={},{},{},{}
    for i,m in ipairs(results) do
      core.log("action",("NATIVE ROAD FLEET BENCH day=%d baseline_ms=%.3f optimized_ms=%.3f baseline_cpu_ms=%.3f optimized_cpu_ms=%.3f fleet=%d moving=%d arrived=%d parity=exact"):format(
        i,m.a,m.b,m.ac,m.bc,m.shown,m.moving,m.arrived))
      if i>2 then a[#a+1]=m.a;b[#b+1]=m.b;ac[#ac+1]=m.ac;bc[#bc+1]=m.bc end
    end
    for _,sample in ipairs({a,b,ac,bc}) do table.sort(sample) end
    core.log("action",("NATIVE ROAD FLEET BENCH MEDIAN baseline_ms=%.3f optimized_ms=%.3f baseline_cpu_ms=%.3f optimized_cpu_ms=%.3f"):format(
      (a[5]+a[6])/2,(b[5]+b[6])/2,(ac[5]+ac[6])/2,(bc[5]+bc[6])/2))
    core.log("action",("NATIVE ROAD FLEET BENCH SURFACE_BUILDS four_days baseline=%d optimized=%d"):format(
      results.calls.old,results.calls.new))
    core.request_shutdown("Native road fleet comparison complete",false,0)
  end))
end)
