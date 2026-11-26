-- Native Lua async timings. Save copied fixture only, never a live world.
local mod=core.get_modpath("luanttd_core")
for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
core.after(0,function()
  assert(core.handle_async(function()
    local m=core.get_modpath("luanttd_core")
    local old,new=dofile(m.."/baseline_fleet.lua")(m),dofile(m.."/road_fleet_perf.lua")(m)
    local pack=dofile(m.."/packed_campaign.lua")
    local results={}
    local function make(F)
      collectgarbage("collect")
      local t,c=core.get_us_time(),os.clock()
      local s=F.make(24,8,function(sim,world)
        world.road_stock_house_supply=true
        sim.mount_road_bus_market(world,dofile(m.."/openttd/stock_engine_calendar.lua"),1950)
      end,function(i) return i%2==0 and "leopard_bus" or "bus" end)
      local m_setup, cpu_setup=(core.get_us_time()-t)/1000,(os.clock()-c)*1000
      collectgarbage("collect")
      t,c=core.get_us_time(),os.clock()
      local raw=pack.encode(s)
      local tmp=core.compress(raw,"zstd",3)
      local m_save,cpu_save=(core.get_us_time()-t)/1000,(os.clock()-c)*1000
      local restored=pack.decode(core.decompress(tmp,"zstd"))
      local unique,lists={}, {}
      local n,total=0,0
      for id,v in pairs(restored.fleet) do
        local fs=assert(v.road_motion_frames)
        assert(not lists[fs],"Two vehicles own the same mutable route list")
        lists[fs]=id
        for _,f in ipairs(fs) do
          total=total+1
          if not unique[f] then n=n+1;unique[f]=true end
        end
      end
      return {sim=F.Sim,world=restored},{m_setup,cpu_setup,m_save,cpu_save,#raw,#tmp,n,total}
    end
    for i=1,4 do
      local a,b,r1,r2
      if i%2==1 then a,r1=make(old);b,r2=make(new) else b,r2=make(new);a,r1=make(old) end
      assert(r1[8]==r2[8] and r2[7]<r1[7])
      for d=1,12 do
        a.sim.daily(a.world);b.sim.daily(b.world)
        local visible,moving,arrived=old.check({a,b})
        assert(visible>=168 and moving>=150)
        if d==12 then assert(arrived>=24) end
      end
      results[i]={r1,r2}
    end
    return results
  end,function(results)
    for i,pair in ipairs(results) do
      for j,r in ipairs(pair) do
        core.log("action",("ROUTE_SHARE trial=%d side=%s setup=%.2f setup_cpu=%.2f save=%.2f save_cpu=%.2f raw=%d zstd=%d unique=%d total=%d"):format(i,j==1 and "before" or "after",unpack(r)))
      end
    end
    core.request_shutdown("Road geometry benchmark complete",false,0)
  end))
end)
