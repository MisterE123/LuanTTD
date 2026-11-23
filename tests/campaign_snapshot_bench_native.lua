local mod=assert(core.get_modpath("luanttd_core"))
core.set_mapgen_setting("mg_name","singlenode",true)
core.register_alias("mapgen_stone","air")
core.register_alias("mapgen_water_source","air")
core.register_alias("mapgen_river_water_source","air")
core.after(0,function()
  assert(core.handle_async(function()
    local m=assert(core.get_modpath("luanttd_core"))
    local run=dofile(m.."/campaign_snapshot_bench.lua")
    local function clock()return core.get_us_time()/1e6 end
    local results={}
    for i=1,3 do
      local base,v=run(m,m.."/baseline_endpoint.lua",40,m.."/baseline_projection.lua",clock)
      local now,w=run(m,nil,40,nil,clock)
      assert(v==w and v>0)
      results[i]={baseline_ms=base,optimized_ms=now,visible=v}
    end
    return results
  end,function(results)
    assert(results and #results==3,"native snapshot performance harness returned no observations")
    for i,m in ipairs(results) do
      core.log("action",("NATIVE SNAPSHOT BENCH run=%d baseline_ms=%.3f optimized_ms=%.3f visible=%d 3x3x32²"):format(
        i,m.baseline_ms,m.optimized_ms,m.visible))
    end
    core.request_shutdown("Native campaign observation comparison complete",false,0)
  end))
end)
