core.set_mapgen_setting("mg_name","singlenode",true)
for _,node in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..node,"air") end
core.after(0,function()
  assert(core.handle_async(function()
    local m=assert(core.get_modpath("luanttd_core"))
    local F=dofile(m.."/road_fleet_perf.lua")(m)
    local S=F.Sim
    local results={}
    local function same(a,b)
      if a==b then return true end
      if type(a)~="table" or type(b)~="table" then return false end
      for k,v in pairs(a) do if not same(v,b[k]) then return false end end
      for k in pairs(b) do if a[k]==nil then return false end end
      return true
    end
    for _,want in ipairs({0,480}) do
      local s=F.make(24,8,function(sim,world)
        if want==0 then return end
        local owner="Bywater Rail and Coach"
        sim.company(world,owner).cash=100000000
        local count=0
        for z=111,251,4 do
          assert(sim.build(world,owner,"road",sim.line(sim.id(6,z),sim.id(115,z))))
          for x=7,112,4 do
            local id=sim.id(x,z)
            if count%2==0 then
              world.sites[#world.sites+1]={id=#world.sites+1,name="Bench Town",kind="town",tile=id,stock={},produced={},received={},population=280,service=0}
            end
            assert(sim.build(world,owner,"road_station",{id}))
            count=count+1
            if count==want then return end
          end
        end
      end,nil,256)
      local base=F.backend(s,dofile(m.."/baseline_sim.lua"))
      -- Bootstrapping with the real unit test fixture starts all buses on
      -- nonoverlapping routed legs, then genuine arrivals and payments.
      local patch=F.backend(s,S)
      local function step(b)
        collectgarbage("collect")
        local wall,cpu=core.get_us_time(),os.clock()
        b.sim.daily(b.world)
        return (core.get_us_time()-wall)/1000,(os.clock()-cpu)*1000
      end
      local event_count=0
      for i=1,16 do
        local aw,ac,bw,bc
        if i%4<=1 then aw,ac=step(base);bw,bc=step(patch)
        else bw,bc=step(patch);aw,ac=step(base) end
        local shown,moving,arrived=F.check({base,patch})
        local left=base.sim.road_loading_events(base.world)
        local right=patch.sim.road_loading_events(patch.world)
        assert(same(left,right),"loading event differs")
        event_count=event_count+#left
        if i==16 then
          assert(shown==192 and moving>=160 and arrived>=48 and event_count>0,
            "the comparison needs a moving fleet and genuine station arrivals")
        end
        results[#results+1]={want,i,aw,ac,bw,bc,shown,moving,arrived,#left}
      end
    end
    return results
  end,function(rows)
    assert(rows)
    for _,r in ipairs(rows) do core.log("action",("ROAD HASH PROFILE idle=%d day=%d baseline_wall=%.3f baseline_cpu=%.3f candidate_wall=%.3f candidate_cpu=%.3f fleet=%d moving=%d arrived=%d events=%d"):format(unpack(r))) end
    core.request_shutdown("Road occupancy benchmark complete",false,0)
  end))
end)
