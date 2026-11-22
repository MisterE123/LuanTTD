-- Stock conventional bus fault lifecycle on the 74-tick campaign clock.
-- No automatic service detour, hidden second RNG, or separate movement.
return function(Kernel,Sim,s,difficulty,random32)
  assert(difficulty==0 or difficulty==1 or difficulty==2,"Road breakdowns must be 0, 1, or 2.")
  local F={}
  local market=assert(s.stock_bus_market)
  local function now() return market.epoch+s.day end
  local function attach(v)
    if v.road_fault then return v.road_fault end
    if difficulty==0 or not v.stock_bus then return end
    local engine=Sim.stock_road_offer(s,v.engine)
    local offer=Sim.vehicle_offer(s,v.engine)
    if not engine or not offer then return end
    local f=Kernel.new(engine.reliability,engine.reliability_decay,offer.life*365,now(),now())
    v.road_fault=f
    return f
  end
  function F.purchased(v)
    attach(v)
  end
  function F.daily(after)
    local ids={}
    for id,v in pairs(s.fleet) do if v.stock_bus then ids[#ids+1]=id end end
    table.sort(ids)
    for _,id in ipairs(ids) do
      local v=s.fleet[id]
      local f=attach(v)
      if f then
        local c=v.road_speed_state
        Kernel.economy_day(f,{blocked_ctr=c and c.blocked_ctr or 0,
          cur_speed=c and c.speed or 0, stopped=not v.running, difficulty=difficulty},random32)
        Kernel.calendar_day(f,{front=true})
        if after then after(v,f,difficulty,now(),random32) end
      end
    end
  end
  function F.tick(v,tick)
    local f=v.road_fault
    if not f then return false end
    local c=v.road_speed_state
    local result=Kernel.tick(f,{cur_speed=c and c.speed or 0,
      loading=v.load_state~=nil, front=true,
      hidden=v.depot~=nil or c and c.depot_wait, crashed=v.crashed})
    if c then c.speed=result.cur_speed end
    if result.started then
      f.starts=(f.starts or 0)+1;f.last_start=tick
    end
    if result.recovered then
      f.recoveries=(f.recoveries or 0)+1;f.last_recovery=tick
    end
    if result.hold_motion then v.status="Broken down"
    elseif v.status=="Broken down" then
      v.status=not v.running and "Stopped" or v.load_state and "At stop" or "En route"
    end
    return result.hold_motion
  end
  function F.service(v,tick)
    local f=v.road_fault
    if not f then return end
    local e=Sim.stock_road_offer(s,v.engine)
    if not e then return end
    Kernel.service(f,e.reliability,now(),now(),difficulty)
    f.services=(f.services or 0)+1;f.last_service_tick=tick
  end
  function F.report(v)
    local f=v.road_fault
    if not f then return end
    return math.floor(f.reliability*100/65535),f.breakdown_ctr==1,f.breakdown_delay
  end
  return F
end
