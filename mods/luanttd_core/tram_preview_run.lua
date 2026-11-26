-- One electric streetcar service. A shared road-clock adapter may drive
-- this same saved state; the standalone caller keeps dedicated tracks only.
local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local body=dofile(mod.."/tram_market.lua")
local Index=dofile(mod.."/tram_fleet_index.lua")
local Flood=dofile(mod.."/openttd/ground_vehicle_flood.lua")
return function(Network,Trip,Speed,shared,Passenger)
  local R={VERSION=1}
  local speed_cap=body.speed
  local function paid_stop(s,id,owner)
    local station=Passenger.station(s,id,owner)
    return station and station.id
  end
  function R.offer()
    return {name=body.name,price=body.price,capacity=body.capacity,speed=body.speed/2}
  end
  local function compile(s,owner,a,b,td,wants)
    local board=Network.board(s)
    local path,last,cost,frames,trace=Trip.route(board,a,b,
      {owner=owner,tram_arrival_td=td,display_max_speed=speed_cap,cargo="passenger"})
    if not path then return nil,last end
    if not frames then return nil,"ordered_stop_must_differ" end
    if not (shared and shared(s)) then
      for _,id in ipairs(path) do
        if board.tile(id).roadtype~=nil then return nil,"mixed_traffic_not_enabled" end
      end
    end
    if wants then
      local first=frames[1]
      if first[1]~=wants[1] or first[2]~=wants[2] or first[3]~=wants[3] or
          first[4]~=wants[4] then return nil,"seam_discontinuous" end
    end
    return {path=path,last=last,source=a,target=b,cost=cost,frames=frames,trace=trace}
  end
  function R.current(s,id)
    local p=Index.get(s,id)
    return p and p.version==R.VERSION and p or nil
  end
  local function compile_loop(s,owner,depot,first,second)
    local board=Network.board(s)
    local d,a,b=board.tile(depot),board.tile(first),board.tile(second)
    if not d or d.kind~="depot" or not a or not b or
       a.kind~="drive_stop" or b.kind~="drive_stop" or first==second then
      return nil,"depot_and_two_stops_required"
    end
    local lead,why=compile(s,owner,depot,first)
    if not lead then return nil,why end
    local leg1,msg=compile(s,owner,first,second,lead.last,lead.frames[#lead.frames])
    if not leg1 then return nil,msg end
    local leg2,msg2=compile(s,owner,second,first,leg1.last,leg1.frames[#leg1.frames])
    if not leg2 then return nil,msg2 end
    local loop,msg3=compile(s,owner,first,second,leg2.last,leg2.frames[#leg2.frames])
    if not loop then return nil,msg3 end
    local check,msg4=compile(s,owner,second,first,loop.last,loop.frames[#loop.frames])
    if not check or check.last~=leg2.last or loop.last~=leg1.last then
      return nil,msg4 or "unstable_arrival_orientation"
    end
    lead.order_index,leg1.order_index,leg2.order_index,loop.order_index=1,2,1,2
    local active={version=R.VERSION,owner=owner,depot=depot,orders={first,second},
      legs={lead,leg1,leg2,loop},leg=1,index=1,
      heading=lead.frames[1][3],speed=0,subspeed=0,progress=0,arrivals=0,phase="depot",
      wait=18,ticks=0,steps=0}
    return active
  end
  function R.start(s,owner,depot,first,second)
    if R.current(s) then return nil,"pilot_already_exists" end
    local p,why=compile_loop(s,owner,depot,first,second)
    if not p then return nil,why end
    s.tram_test_generation=(s.tram_test_generation or 0)+1
    p.test_generation=s.tram_test_generation
    s.tram_pilot=p
    return p
  end
  function R.start_paid(s,owner,depot,first,second,quoted_price,additional)
    if additional and s.next_vehicle==1 then additional=false end
    if not Passenger or not shared or not shared(s) then return nil,"TRAM_SERVICE_UNAVAILABLE" end
    if quoted_price~=body.price then return nil,"TRAM_PRICE_CHANGED" end
    local a,b=paid_stop(s,first,owner),paid_stop(s,second,owner)
    if not a or not b or a==b then return nil,"TWO_OWNED_TRAM_PLATFORMS_REQUIRED" end
    local c=s.companies[owner]
    if not c or c.cash<body.price then return nil,"NOT_ENOUGH_MONEY" end
    if not additional and R.current(s) then return nil,"pilot_already_exists" end
    local p,why=compile_loop(s,owner,depot,first,second)
    if not p then return nil,why end
    local id=s.next_vehicle
    s.next_vehicle=id+1
    p.carrier={id=id,owner=owner,engine="native_streetcar",cargo="passenger",
      stock_tram={capacity=body.capacity,slice=body.slice,aging=body.aging,speed=body.speed},
      running=true,batches={},units=0,revenue=0,delivered=0,bought=s.day,stock_purchase_value=body.price}
    c.cash,c.expense,c.month_exp=c.cash-body.price,c.expense+body.price,c.month_exp+body.price
    if additional then
      s.stock_tram_fleet=s.stock_tram_fleet or {}
      s.stock_tram_fleet[id]=p
    else s.tram_pilot=p end
    return p
  end
  function R.orders(s,owner,id)
    local p=R.current(s,id)
    if not p or p.owner~=owner then return end
    return p.orders or {p.legs[1].target,p.legs[2].target}, p.order_revision or 0, p
  end
  -- Luanti's tram adapter precompiles its stock YAPF/vehicle-table legs.
  -- Keep the active physical leg, then enter the edited order sequence
  -- from its legal through-stop approach. Verify the entire directed
  -- loop before changing anything, including the seam at wraparound.
  function R.replace_orders(s,owner,orders,next_order,retained,id)
    local _,_,p=R.orders(s,owner,id)
    if not p or #orders<2 or #orders>254 then return false,"Choose at least two tram stops." end
    if p.road_flood_age then return false,"That streetcar is a wreck." end
    if p.carrier then
      local ids={}
      for _,tile in ipairs(orders) do
        local id=paid_stop(s,tile,owner)
        if not id then return false,"Passenger trams need owned tram platforms." end
        ids[id]=true
      end
      local a=next(ids)
      if not a or not next(ids,a) then return false,"Choose two distinct stations." end
    end
    local current=p.legs[p.leg]
    local end_pose=current.frames[#current.frames]
    local previous,td,pose=current.target,current.last,end_pose
    local prefix={}
    for k,v in pairs(current) do prefix[k]=v end
    prefix.order_index=retained
    local legs,seen={prefix},{}
    local i=next_order
    for _=1,16*#orders+1 do
      if not orders[i] then return false,"Invalid tram order." end
      local key=("%d/%s/%s"):format(i,tostring(previous),tostring(td))
      if seen[key] then
        if #legs<2 then return false,"Choose at least two distinct tram stops." end
        p.depot=p.depot or p.legs[1].source
        p.legs,p.leg,p.loop=legs,1,seen[key]
        p.orders,p.order_revision,p.pending_order=orders,(p.order_revision or 0)+1,next_order
        return true,"Tram orders updated."
      end
      seen[key]=#legs+1
      local stop=orders[i]
      if stop~=previous then
        local leg,why=compile(s,owner,previous,stop,td,pose)
        if not leg then return false,why end
        leg.order_index=i
        legs[#legs+1]=leg
        previous,td,pose=stop,leg.last,leg.frames[#leg.frames]
      end
      i=i%#orders+1
    end
    return false,"unstable_arrival_orientation"
  end
  function R.clear(s,owner,id)
    local p=R.current(s,id)
    if not p or p.owner~=owner then return nil,"no_owned_pilot" end
    if p.road_flood_age then return nil,"TRAM_WRECK_IN_THE_WAY" end
    if p.carrier and p.carrier.load_state and not Passenger.depart(s,p.carrier,s.stock_load_tick,true) then
      return nil,"TRAM_LOADING_NOT_SETTLED"
    end
    if p==s.tram_pilot then s.tram_pilot=nil
    else s.stock_tram_fleet[id]=nil end
    return true
  end
  function R.frame(p) return p and Index.frame(p) end
  R.uses=Index.uses
  R.all=Index.sorted
  function R.ui_id(s,p) return p==s.tram_pilot and 1 or Index.serial(p) end
  function R.by_ui(s,id)
    if id==1 then return R.current(s) end
    local p=R.current(s,id)
    if p and p~=s.tram_pilot then return p end
  end
  R.serial=Index.serial
  function R.retirement_key(p)
    return p.carrier and ("paid:"..p.carrier.id) or ("test:"..(p.test_generation or 0))
  end
  -- The registered road vehicles are visited in increasing ID order.
  -- The separate streetcar slot comes after them, sharing the *same*
  -- candidate set; it is not a time-delayed visual collision detector.
  local timelines=setmetatable({},{__mode="k"})
  function R.pose_frames(s,fraction,id)
    local p=R.current(s,id)
    if not p then return end
    local sample=timelines[p]
    if not sample or not fraction then
      local f=R.frame(p)
      return f,f,0
    end
    local at=1+math.max(0,math.min(1,fraction))*(#sample.frames-1)
    local i=math.floor(at)
    local a=sample.frames[i]
    if not a then return end
    local b=sample.frames[i+1] or a
    return a,b,at-i
  end
  function R.traffic(z)
    local C={}
    local ordered={}
    function C.seed(s,W,_,k)
      if k==1 or ordered.world~=s then ordered={world=s,runs=R.all(s)} end
      if #ordered.runs==0 then return end
      local records={}
      for _,p in ipairs(ordered.runs) do
        local id=Index.serial(p)
        if R.current(s,id)==p then
          if k==1 then timelines[p]={frames={R.frame(p) or false}} end
          local record={id=id,first=id,type="road",companion=true,
            clock=p,max_speed=speed_cap,stopped=p.phase~="running"}
          local f=R.frame(p)
          if f then W.put(record,f,false,z(s,f)) end
          records[#records+1]=record
        end
      end
      return records
    end
    function C.advance(s,W,tick,record,k,ready)
      local p=R.advance(s,1,nil,W,record,z,tick,ready,record.clock)
      local sample=p and timelines[p]
      if sample and k then sample.frames[k]=R.frame(p) or false end
      return p
    end
    C.coastal_in_use=R.uses
    function C.coastal_index(s)
      local rows={}
      for _,p in ipairs(R.all(s)) do
        local f=R.frame(p)
        if f and not (f[10] or f[12] or f[13] or f[14] or f[16]) then
          local id=f[4]
          local row=rows[id] or {};rows[id]=row
          row[#row+1]=p
        end
      end
      return rows
    end
    function C.flood(s,p,id,tick,station,crash)
      local f=R.frame(p)
      local v=p.carrier
      if p.phase~="stopped" or not (v and v.load_state and v.load_state.station==station and
          f and f[4]==id and z(s,f)<=0) then return end
      local count=crash(v,tick)
      if count==nil then return end
      p.phase,p.speed,p.subspeed,p.progress,p.road_flood_age="crashed",0,0,0,Flood.road_crash_age(true)
      return count
    end
    return C
  end
  function R.advance(s,n,observe,W,record,z,tick,ready,run)
    local p=run or R.current(s)
    if not p then return end
    if p.carrier then assert(n==1 and tick and ready,"Commercial tram requires the owner road clock") end
    for _=1,n do
      p.ticks=p.ticks+1
      if p.road_flood_age then
        local retire
        p.road_flood_age,retire=Flood.road_wreck_tick(p.road_flood_age,p.ticks)
        if retire then
          if p==s.tram_pilot then s.tram_pilot=nil else s.stock_tram_fleet[Index.serial(p)]=nil end
          if W then W.erase(record) end
          return
        end
        return p
      end
      local leg=p.legs[p.leg]
      local carrier=p.carrier
      if carrier and carrier.load_state then
        if not ready[carrier.id] then
          Passenger.age(s,carrier,tick)
          return p
        end
        assert(Passenger.depart(s,carrier,tick))
        p.wait=1
      end
      if p.wait>0 then
        p.wait=p.wait-1
        if p.wait==0 then
          if p.phase~="depot" then
            -- The first trip uses the compiler's approach direction; the
            -- stable loop may return to that platform from the other side.
            local following=p.loop and (p.leg<#p.legs and p.leg+1 or p.loop) or ({[1]=2,[2]=3,[3]=4,[4]=3})[p.leg]
            p.leg,p.index=following,1
          end
          local front=p.legs[p.leg].frames[1]
          local height=W and z(s,front)
          if W and p.phase=="depot" then
            record.z=height
            if W.find(record,p,front[1],front[2],front[3],false) then
              p.wait,p.traffic_wait=1,"depot"
            end
          end
          if p.wait==0 then
            p.phase,p.speed,p.subspeed,p.progress="running",0,0,0
            p.heading,p.traffic_wait=front[3],nil
            if W then record.stopped=false;W.put(record,front,false,height) end
          end
        end
      else
        local here=leg.frames[p.index]
        local span=here[10] and s.stock_road_bridges and s.stock_road_bridges[here[10]]
        local cap=span and math.min(speed_cap,span.spec.speed*2) or speed_cap
        Speed.tick(p,cap,false,function(c)
          local previous=leg.frames[c.index]
          local f=leg.frames[c.index+1]
          if not f then return false end
          local new_z
          if W then
            new_z=z(s,f)
            local lead=W.find(record,c,f[7] or f[1],f[8] or f[2],f[3])
            if lead then
              c.speed,c.traffic_wait=not lead.stopped and lead.clock and lead.clock.speed or 0,"road"
              return false
            end
          end
          local function commit()
            c.traffic_wait=nil
            if W then
              Speed.grade(c,record.z,new_z,cap)
              W.put(record,f,false,new_z)
            end
            c.crossing_wait=nil
            if c.heading~=f[3] then c.heading=f[3];Speed.turn(c) end
            c.index=c.index+1
            c.steps=c.steps+1
            if observe then observe(f,c) end
            if c.index==#leg.frames then
              local serviced=not c.loop or leg.order_index~=nil
              if serviced then c.arrivals=c.arrivals+1 end
              c.phase,c.wait,c.speed,c.subspeed,c.progress="stopped",serviced and 30 or 1,0,0,0
              if record then record.stopped=true end
              if serviced and carrier then
                assert(Passenger.arrive(s,carrier,f,{},tick),"Paid tram station disappeared during its owned itinerary")
              end
            end
            return true
          end
          if not Network.move or previous[4]==f[4] then return commit() end
          local moved,why=Network.move(s,previous,f,commit)
          if not moved then c.speed,c.crossing_wait=0,why end
          return moved
        end)
        if p.phase=="stopped" then p.progress=0 end
      end
      if carrier then Passenger.age(s,carrier,tick) end
    end
    return p
  end
  return R
end
