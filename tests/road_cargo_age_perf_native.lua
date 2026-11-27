local dir=core.get_modpath("luanttd_core")
if not core.register_node then
  function core.age_profile()
    local function make()
      local vs={}
      for i=1,192 do
        vs[i]={cargo_age_counter=i%185+1,batches={{age=10},{age=65400}},
          load_state={unload={{packet={age=3}}},reserved={{age=4}}}}
      end
      return vs
    end
    local old=dofile(dir.."/baseline_loading.lua")()
    local new=dofile(dir.."/road_loading_runtime.lua")()
    local function run(L)
      local v=make()
      collectgarbage("collect")
      local a=os.clock()
      for day=1,40 do
        local t=(day%7==0) and 190 or 1
        for _=1,74 do for i=1,192 do L.age_vehicle(v[i],t,185) end end
      end
      local ms=(os.clock()-a)*1000
      local stamp={}
      for i=1,192 do
        local r=v[i];local l=r.load_state
        stamp[i]=table.concat({r.cargo_age_counter,r.batches[1].age,r.batches[2].age,l.unload[1].packet.age,l.reserved[1].age},":")
      end
      return ms,table.concat(stamp," ")
    end
    run(old);run(new)
    local out={}
    for i=1,12 do
      local a,ar,b,br
      if i%2==0 then b,br=run(new);a,ar=run(old)
      else a,ar=run(old);b,br=run(new) end
      assert(ar==br)
      out[i]=("CARGO AGE NATIVE baseline_cpu_ms=%.3f candidate_cpu_ms=%.3f"):format(a,b)
    end
    return out
  end
  return
end
for _,n in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..n,"air") end
core.register_async_dofile(dir.."/init.lua")
core.after(0,function()
  assert(core.handle_async(function() return core.age_profile() end,function(rows)
    for _,r in ipairs(rows) do core.log("action",r) end
    core.request_shutdown("Cargo timing complete",false,0)
  end))
end)
