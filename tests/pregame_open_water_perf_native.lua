for _,alias in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..alias,"air") end
core.after(0,function()
  assert(core.handle_async(function(path)
    local mod=core.get_modpath("luanttd_core")
    local Sim=dofile(mod.."/sim.lua")
    local Generate=dofile(mod.."/campaign_generation.lua")(core,mod,Sim,dofile(mod.."/world_setup.lua"))
    local start,settling=os.clock(),nil
    local s=Generate.run({width=1024,depth=1024,seed=4216,coast=15,sea=2,towns=3,industries=4},function(_,stage)
      if not settling and stage=="Settling the landscape" then settling=os.clock() end
    end)
    assert(settling and s.stock_generated_profile.initial_landscape.ticks==1280)
    local done=os.clock()
    local codec=dofile(mod.."/packed_campaign.lua")
    local result=core.compress(codec.encode(s),"zstd",1)
    assert(core.safe_file_write(path.."/state.zst",result))
    return (done-start)*1000,(done-settling)*1000
  end,function(total,settle)
    assert(total and settle)
    core.log("action",("PREGAME PERF total=%.3f settle=%.3f"):format(total,settle))
    core.request_shutdown("Pregame water full state comparison",false,0)
  end,core.get_worldpath()))
end)
