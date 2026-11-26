-- Registered paid streetcars, exact poses and source tick; works in the
-- portable test and in a real Luanti save and restart.
return function(S,mod)
  local Terrain=dofile(mod.."/openttd/terrain.lua")
  local H=dofile(mod.."/openttd/town_passengers.lua")
  local Track=dofile(mod.."/openttd/yapf_road_follow.lua")
  local Bindings=dofile(mod.."/campaign_simulation_bindings.lua")(S,mod)
  local Slope=dofile(mod.."/openttd/slope.lua")
  local F={}
  local owner="Coastal tram QA"
  local west,east,sea=S.id(11,12),S.id(17,12),S.id(11,13)
  local function bind(s)
    local net,run=Bindings.tram(s,Slope,1.25)
    S.mount_shared_road_tram(s,run.traffic(net.frame_z))
    return {net=net,run=run}
  end
  function F.start(s)
    local g=s.corner_grid or Terrain.new(S.W,S.H)
    s.corner_grid=g
    for i in ipairs(g.levels) do g.levels[i]=0 end
    for i in ipairs(s.tiles) do s.tiles[i]={terrain="grass",h=0,variant=1} end
    for z=20,29 do
      for x=1,g.width+1 do g.levels[(z-1)*(g.width+1)+x]=1 end
    end
    s.tram_enabled,s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true,true
    S.mount_coastal_flood(s)
    S.company(s,owner)
    local R=bind(s)
    local function place(z,more)
      local a,b,d=S.id(11,z),S.id(17,z),S.id(12,z-1)
      assert(R.net.construct(s,owner,"road",S.line(S.id(10,z),S.id(18,z))))
      for _,stop in ipairs({a,b}) do assert(R.net.construct(s,owner,"drive_stop",{stop},0)) end
      assert(R.net.construct(s,owner,"depot",{d},Track.SE))
      local p,why=R.run.start_paid(s,owner,d,a,b,R.run.offer().price,more)
      assert(p,why)
      return p,a,b,d
    end
    local wet=place(12,false)
    local dry,u,v,d=place(24,true)
    local stop=assert(S.tram_stop_station(s,west))
    stop.stock.passenger={{units=17,source=11,origin_station=stop.id,age=0}}
    local emitted,aboard
    -- Reach the target exactly when the purchased streetcar has actually
    -- boarded passengers at this platform, not by constructing a wreck.
    local function visit(clock,ticks,read,before)
      H.advance(clock,ticks,read,before)
      local c=wet.carrier
      if not aboard and c.load_state and c.load_state.station==stop.id and c.units>0 then
        aboard=c.units
        s.tiles[sea]={terrain="water",water_class="sea",h=0,variant=1}
        for _,id in ipairs({S.id(10,13),S.id(12,13),S.id(10,14),S.id(11,14),S.id(12,14)}) do
          s.tiles[id]={terrain="water",water_class="river",h=0,variant=1}
        end
        local x,z=S.xy(sea)
        read((z-1)*2^clock.log_x+x-1,clock.counter)
      end
    end
    S.mount_news(s,nil,function(id,n,tram)
      assert(id==west and tram and n>=1 and n<=1+aboard and not emitted)
      emitted=true
    end)
    for _=1,12 do
      S.daily(s,visit)
      if wet.road_flood_age then break end
    end
    assert(aboard and emitted and wet.road_flood_age>=2000 and wet.road_flood_age<2220)
    assert(wet.carrier.crashed and not wet.carrier.load_state and #stop.loading_order==0 and wet.carrier.units==0)
    assert(R.run.frame(wet)[4]==west and R.net.frame_z(s,R.run.frame(wet))==0 and not dry.road_flood_age)
    assert(S.tram_stop_station(s,west)==stop and not R.run.clear(s,owner,wet.carrier.id))
    return {wet=wet.carrier.id,dry=dry.carrier.id,dry_ticks=dry.ticks,stop=stop.id,east=S.tram_stop_station(s,east).id,u=u,v=v,depot=d}
  end
  function F.finish(s,proof)
    local R=bind(s)
    local wet,dry=assert(R.run.current(s,proof.wet)),assert(R.run.current(s,proof.dry))
    assert(wet.road_flood_age and R.run.frame(wet)[4]==west and not dry.road_flood_age)
    for _=1,20 do
      S.daily(s)
      if not R.run.current(s,proof.wet) and s.tiles[west].terrain=="water" then break end
    end
    assert(s.tiles[west].water_class=="sea" and not s.tiles[west].tram and not s.stations[proof.stop])
    assert(s.stations[proof.east] and R.run.current(s,proof.dry)==dry and dry.ticks>proof.dry_ticks and not dry.road_flood_age)
    local later=assert(R.run.start_paid(s,owner,proof.depot,proof.u,proof.v,R.run.offer().price,false))
    assert(later.carrier.id>proof.dry and R.run.current(s,proof.dry)==dry)
    return true
  end
  return F
end
