for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
core.after(0,function()
  assert(core.handle_async(function()
    local mod=assert(core.get_modpath("luanttd_core"))
    local F=dofile(mod.."/road_fleet_perf.lua")(mod)
    local H=dofile(mod.."/openttd/town_passengers.lua")
    -- Start with paid depots, orders and stations, then use an independent
    -- low plain behind one sea row. Real stock tides advance there without
    -- interacting with the road corridor on higher ground.
    local s=F.make(12,8,nil,nil,512)
    local S=F.Sim
    s.road_stock_house_supply=true
    s.passenger_house_clock=H.new_clock(9,9,1,s.stock_load_tick)
    for x=325,479 do for z=25,485 do
      local i=(z-1)*(S.W+1)+x
      s.corner_grid.levels[i]=0
      local p=s.tiles[S.id(x,z)]
      p.h=0
      if x==326 then p.terrain,p.water_class="water","sea" end
    end end
    local bs=dofile(mod.."/baseline_sim.lua")
    local a,b=F.backend(s,bs),F.backend(s,S)
    bs.mount_coastal_flood(a.world)
    S.mount_coastal_flood(b.world)
    s=nil
    local out={}
    for i=1,8 do
      local function run(r)
        collectgarbage("collect")
        local old=r.world.topology
        local t=os.clock()
        r.sim.daily(r.world)
        return (os.clock()-t)*1000,r.world.topology-old
      end
      local x,y,u,v
      if i%2==1 then x,u=run(a);y,v=run(b) else y,v=run(b);x,u=run(a) end
      local shown,move,arrive=F.check({a,b})
      assert(u==v and u>0 and shown==96 and move>0)
      local line=("COASTAL NETWORK day=%d baseline=%.3f optimized=%.3f revisions=%d shown=%d moving=%d arrived=%d"):format(i,x,y,u,shown,move,arrive)
      core.log("action",line);out[i]=line
    end
    return out
  end,function(out)
    assert(out and #out==8)
    core.request_shutdown("Coastal junction parity completed",false,0)
  end))
end)
