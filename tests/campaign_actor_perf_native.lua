local mod=assert(core.get_modpath("luanttd_core"))
core.set_mapgen_setting("mg_name","singlenode",true)
for _,node in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..node,"air") end
core.after(0,function()
  assert(core.handle_async(function()
    local m=assert(core.get_modpath("luanttd_core"))
    local F=dofile(m.."/road_fleet_perf.lua")(m)
    local cap={road={start_year=1950,breakdowns=0,service_interval=150}}
    local Sim,s=F.Sim,F.make(24,8,function(sim,world)
      sim.mount_road_bus_market(world,dofile(m.."/openttd/stock_engine_calendar.lua"),cap.road.start_year)
    end,function(i) return i%2==0 and "leopard_bus" or "bus" end)
    Sim.daily(s)
    local base=dofile(m.."/baseline_runtime.lua")(Sim,m,s,cap)
    local next_=dofile(m.."/campaign_authority_runtime.lua")(Sim,m,s,cap)
    local old=dofile(m.."/campaign_authority_endpoint.lua")(Sim,base)
    local new=dofile(m.."/campaign_authority_endpoint.lua")(Sim,next_)
    local function same(a,b)
      if a==b then return true end
      if type(a)~="table" or type(b)~="table" then return false end
      for k,v in pairs(a) do if not same(v,b[k]) then return false end end
      for k in pairs(b) do if a[k]==nil then return false end end
      return true
    end
    local function windows(left,top)
      local out={}
      for z=top,top+64,32 do for x=left,left+64,32 do out[#out+1]={x=x,z=z,w=32,h=32} end end
      return out
    end
    local cameras={windows(1,33),windows(33,33),{{x=55,z=33,w=19,h=28},{x=61,z=38,w=22,h=25}},
      {{x=58,z=37,w=4,h=4}}}
    local visible=0
    for j,window in ipairs(cameras) do
      for i=0,16 do
        local p,q=old.actor_frames(window,i/16),new.actor_frames(window,i/16)
        assert(p.ok and q.ok and same(p,q),"actor window or output differs: "..j.." fraction "..i)
        if j==1 and i==8 then for _,r in ipairs(q.value) do visible=visible+#r.actors end end
      end
    end
    assert(visible>0 and visible<192,"viewport must cover only part of the living fleet")
    local original=Sim.road_surface
    local function measure(a,window)
      collectgarbage("collect")
      local start=os.clock()
      for i=1,100 do assert(a.actor_frames(window,(i%17)/16).ok) end
      return (os.clock()-start)*10
    end
    local records={}
    for n=1,8 do
      local which=math.floor((n-1)/2)%2+1
      local window=cameras[which]
      if n%2==0 then
        records[n]={new=measure(new,window),old=measure(old,window),camera=which}
      else
        records[n]={old=measure(old,window),new=measure(new,window),camera=which}
      end
    end
    local function lookups(a)
      local seen=0
      Sim.road_surface=function(...) seen=seen+1; return original(...) end
      a.actor_frames(cameras[1],.5)
      Sim.road_surface=original
      return seen
    end
    local result={records=records,old_surface=lookups(old),new_surface=lookups(new),visible=visible}

    -- Sparse fixture at real 4096² coordinates. Use the production RC1
    -- footprint constructors without allocating millions of unrelated tiles.
    assert(Sim.mount_oil_world(s,base.terrain,true))
    Sim.W,Sim.H=4096,4096
    local path=m.."/openttd/"
    local P,Rate=dofile(path.."passengers.lua"),dofile(path.."station_rating.lua")
    local Coal=dofile(path.."coal_industry.lua")(P,Rate,dofile(path.."station_catchment.lua")(P,Rate),
      dofile(path.."income.lua"))
    local Oil=assert(Sim.oil_rules())
    local rules,registry=dofile(path.."industry_machinery_rc1.lua"),dofile(m.."/oil_animation_registry.lua")
    local initial=dofile(m.."/baseline_industry_machinery_world.lua")(Sim,rules,registry)
    local optimized=dofile(m.."/industry_machinery_world.lua")(Sim,rules,registry)
    local function region(n)
      local world={stock_generated_profile={},stock_coal_industries={},stock_oil_industries={},tiles={},
        passenger_house_clock={counter=0}}
      for i=1,n do
        local x,z=(i-1)%32*13+5,math.floor((i-1)/32)*13+5
        -- Spread the bulk of the stock industries across the map.
        if i>96 then x,z=x*7,z*7 end
        local kind=i%3==0 and "oil_well" or i%3==1 and "coal_mine" or "power_station"
        local r=(i%3==0 and Oil or Coal).new(kind,i,x,z,{completed=true,layout=i%2})
        local firms=i%3==0 and world.stock_oil_industries or world.stock_coal_industries
        firms[i]=r
        for _,part in ipairs(r.tiles) do
          local id=Sim.id(part.x+1,part.z+1)
          assert(not world.tiles[id])
          world.tiles[id]={stock_industry={id=i,chain=i%3==0 and "oil" or nil},h=2}
          if part.gfx==0 then part.gfx,part.animated,part.animation_frame=1,true,i%256
          elseif part.gfx==29 then part.gfx,part.animation_frame=30+i%8,i%4 end
        end
      end
      return world
    end
    result.machinery={}
    local machinery_windows=windows(1,1)
    for _,n in ipairs({48,1024}) do
      local wide=region(n)
      local function projects(a,tick)
        wide.passenger_house_clock.counter=tick
        local packets={}
        for i,w in ipairs(machinery_windows) do packets[i]=a.visible(wide,w.x,w.z,w.w,w.h) end
        return packets
      end
      for _,tick in ipairs({0,1024,1439,1440,1536,1950,1952,4096}) do
        local p,q=projects(initial,tick),projects(optimized,tick)
        assert(same(p,q),"machinery phases or visibility differ")
        local total=0
        for _,rows in ipairs(q) do for _ in pairs(rows) do total=total+1 end end
        assert(total>0,"fixture needs visible machinery")
      end
      local function profile(a)
        collectgarbage("collect")
        local start=os.clock()
        for i=1,100 do projects(a,1024+i*8) end
        return (os.clock()-start)*10
      end
      local samples={}
      for i=1,4 do
        local a,b
        if i%2==0 then b=profile(optimized);a=profile(initial)
        else a=profile(initial);b=profile(optimized) end
        samples[i]={old=a,new=b}
      end
      result.machinery[#result.machinery+1]={industries=n,samples=samples}
    end
    return result
  end,function(result)
    assert(result and result.records,"actor benchmark did not return")
    for i,p in ipairs(result.records) do
      core.log("action",("NATIVE ACTOR BENCH road camera=%d sample=%d baseline_cpu_ms=%.3f optimized_cpu_ms=%.3f"):format(p.camera,i,p.old,p.new))
    end
    core.log("action",("NATIVE ACTOR BENCH exact receipts; 192 running buses; %d visible in first camera; terrain lookups %d → %d"):format(
      result.visible,result.old_surface,result.new_surface))
    for _,region in ipairs(result.machinery) do
      for i,p in ipairs(region.samples) do
        core.log("action",("NATIVE ACTOR BENCH machinery industries=%d sample=%d baseline_cpu_ms=%.3f optimized_cpu_ms=%.3f"):format(
          region.industries,i,p.old,p.new))
      end
    end
    core.request_shutdown("Native actor projection comparison complete",false,0)
  end))
end)
