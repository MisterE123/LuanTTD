-- Bought stock buses on actual built roads. Start from nonoverlapping
-- points on their routed legs to immediately exercise a busy network.
return function(mod)
  local Sim=dofile(mod.."/sim.lua")
  local Terrain=dofile(mod.."/openttd/terrain.lua")
  local F={}
  local function copy(value)
    if type(value)~="table" then return value end
    local out={}
    for k,v in pairs(value) do out[k]=copy(v) end
    return out
  end
  function F.make(lines,count,prepare,choose,size,lines_per_company)
    Sim.W,Sim.H=size or 128,size or 128
    local s=Sim.new(1751)
    s.sites={}
    for _,t in ipairs(s.tiles) do
      t.terrain,t.h,t.wood,t.site,t.house="grass",1,nil,nil,nil
    end
    s.corner_grid=Terrain.new(Sim.W,Sim.H,function() return 1 end)
    s.road_economy,s.road_stock_clock,s.road_stock_loading,s.road_junction_clearance=true,true,true,true
    if prepare then prepare(Sim,s) end
    s.day=9000
    local route={}
    for line=1,lines do
      local owner="Fleet Company "..math.floor((line-1)/(lines_per_company or 6))
      Sim.company(s,owner).cash=100000000
      local z=4+line*4
      local a,b,d=Sim.id(12,z),Sim.id(97,z),Sim.id(17,z+1)
      for _,id in ipairs({a,b}) do
        s.sites[#s.sites+1]={id=#s.sites+1,name="Bench Town",kind="town",tile=id,stock={},produced={},received={},population=280,service=0}
      end
      assert(Sim.build(s,owner,"road",Sim.line(a,b)))
      assert(Sim.build(s,owner,"road_station",{a,b}))
      assert(Sim.build(s,owner,"road_depot",{d}))
      route[line]={start=s.tiles[a].station,dest=s.tiles[b].station,depot=d,ids={}}
      local r=route[line]
      for i=1,count do
        local engine=choose and choose(i) or i%3==0 and "coach" or i%2==0 and "leopard_bus" or "bus"
        local id=assert(Sim.purchase(s,owner,engine,"passenger",nil,d))
        assert(Sim.add_order(s,owner,id,r.dest))
        assert(Sim.add_order(s,owner,id,r.start))
        assert(Sim.toggle(s,owner,id))
        r.ids[i]=id
      end
    end
    Sim.daily(s)
    for _,r in ipairs(route) do
      for i,id in ipairs(r.ids) do
        local v=s.fleet[id]
        local frames=assert(v.road_motion_frames)
        local idx=14+math.floor((#frames-70)*(i-.5)/count)
        local f=assert(frames[idx])
        assert(f[6]==8 and f[3]==5, "seed must start on an ordinary driven lane")
        v.road_speed_state={index=idx,speed=20+i,subspeed=0,progress=0,heading=f[3],ticks=0}
      end
    end
    return s
  end
  -- Capture every vehicle timeline, not just endpoint positions, as well
  -- as the full durable state after each compared tick batch.
  local function difference(a,b)
    if a==b then return end
    if type(a)~="table" or type(b)~="table" then return "" end
    for k,v in pairs(a) do
      local below=difference(v,b[k])
      if below then return "."..k..below end
    end
    for k in pairs(b) do if a[k]==nil then return "."..k end end
  end
  local function same(a,b,where)
    local below=difference(a,b)
    assert(not below,below and ("parity differs at "..where..below))
  end
  function F.check(benchmarks)
    for _,b in ipairs(benchmarks) do assert(b.world.day==benchmarks[1].world.day) end
    local pos,motion,arrivals=0,0,0
    local s=benchmarks[1].world
    for i=2,#benchmarks do same(s,benchmarks[i].world,"world") end
    for id,v in pairs(s.fleet) do
      if v.last_road_arrival_tick then arrivals=arrivals+1 end
      local timeline=benchmarks[1].sim.road_motion_timeline(s,id)
      for i=2,#benchmarks do
        local backend=benchmarks[i]
        same(timeline,backend.sim.road_motion_timeline(backend.world,id),"timeline."..id)
      end
      if timeline then
        assert(#timeline.cursors==75)
        if timeline.cursors[1]~=0 and timeline.cursors[75]~=0 then
          local a,b=timeline.frames[timeline.cursors[1]],timeline.frames[timeline.cursors[75]]
          if a[1]~=b[1] or a[2]~=b[2] then motion=motion+1 end
        end
        pos=pos+1
      end
    end
    return pos,motion,arrivals
  end
  function F.backend(s,sim)
    sim.W,sim.H=Sim.W,Sim.H
    return {world=copy(s),sim=sim}
  end
  F.Sim=Sim
  return F
end
