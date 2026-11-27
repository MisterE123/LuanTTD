for _,node in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..node,"air") end
core.after(0,function()
  assert(core.handle_async(function()
    local m=assert(core.get_modpath("luanttd_core"))
    local F=dofile(m.."/road_fleet_perf.lua")(m)
    local cap={road={start_year=1950,breakdowns=0,service_interval=150}}
    local Sim,s=F.Sim,F.make(60,16,function(sim,world)
      sim.mount_road_bus_market(world,dofile(m.."/openttd/stock_engine_calendar.lua"),cap.road.start_year)
    end,function(i) return i%2==0 and "leopard_bus" or "bus" end,256,3)
    Sim.daily(s)
    local runtime=dofile(m.."/campaign_authority_runtime.lua")(Sim,m,s,cap)
    local base=dofile(m.."/baseline_endpoint.lua")(Sim,setmetatable({
      actors=(function()
        local make=dofile(m.."/baseline_projection.lua")
        return function(x,z,w,h,f,frame) return make(Sim,runtime,x,z,w,h,f,frame) end
      end)(),
    },{__index=runtime}))
    local test=dofile(m.."/campaign_authority_endpoint.lua")(Sim,runtime)
    local function same(a,b)
      if a==b then return true end
      if type(a)~="table" or type(b)~="table" then return false end
      for k,v in pairs(a) do if not same(v,b[k]) then return false end end
      for k in pairs(b) do if a[k]==nil then return false end end
      return true
    end
    local windows={
      {{x=33,z=32,w=31,h=15}},
      {{x=19,z=63,w=21,h=25},{x=32,z=65,w=32,h=25},{x=70,z=82,w=19,h=8}},
      {{x=88,z=230,w=30,h=24},{x=129,z=242,w=12,h=12},{x=1,z=1,w=32,h=32}},
      {{x=249,z=249,w=8,h=8}},
    }
    local visible=0
    for _,batch in ipairs(windows) do
      for k=0,16 do
        local a,b=base.actor_frames(batch,k/16),test.actor_frames(batch,k/16)
        assert(a.ok and same(a,b),"Active actors changed in the interest union")
        for _,r in ipairs(b.value) do visible=visible+#r.actors end
        a,b=base.actor_frames(batch,k/16,true),test.actor_frames(batch,k/16,true)
        assert(a.ok and same(a,b),"Live tick poses changed in the interest union")
      end
      local a,b=base.snapshots(batch,.37,{},false),test.snapshots(batch,.37,{},false)
      assert(a.ok and same(a,b),"A static scene changed in the interest union")
    end
    assert(visible>960)
    local invalid={{x=1,z=1,w=32,h=32},{x=243,z=250,w=4,h=8}}
    for _,k in ipairs({"snapshots","actor_frames"}) do
      assert(same(base[k](invalid,.5),test[k](invalid,.5)))
      assert(same(base[k](windows[1],.5),test[k](windows[1],.5)))
    end
    local function measure(a,k)
      collectgarbage("collect")
      local start=os.clock()
      for i=1,140 do assert(a.actor_frames(windows[k],(i%17)/16).ok) end
      local cpu=(os.clock()-start)*1000
      collectgarbage("collect");collectgarbage("stop")
      local heap=collectgarbage("count")
      for i=1,20 do assert(a.actor_frames(windows[k],(i%17)/16).ok) end
      local alloc=collectgarbage("count")-heap
      collectgarbage("restart")
      return cpu,alloc
    end
    local out={}
    for i=1,8 do
      local k=math.floor((i-1)/2)%4+1
      local a,b,c,d
      if i%2==1 then a,c=measure(base,k);b,d=measure(test,k)
      else b,d=measure(test,k);a,c=measure(base,k) end
      assert(d<c,"Interest scoping must reduce temporary actor heap")
      out[i]={k,a,b,c,d}
    end
    return out
  end,function(out)
    assert(out and #out==8)
    for i,r in ipairs(out) do
      core.log("action",("ACTOR INTEREST %d view=%d cpu=%.3f/%.3f ms allocation=%.1f/%.1f KiB"):format(i,unpack(r)))
    end
    core.request_shutdown("Actor interest benchmark finished",false,0)
  end))
end)
