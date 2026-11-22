-- Isolated one-vehicle continuation of the validated 14.1 loaded bus.
-- SPDX-License-Identifier: GPL-2.0-only
-- The one-body flat realistic speed adapter follows OpenTTD 14.1
-- GroundVehicle::PowerChanged, CargoChanged, GetAcceleration and
-- RoadVehicle::{GetCurrentMaxSpeed,UpdateSpeed,IndividualRoadVehicleController}.
-- Movement samples, fixed-point progress, loading/aging and fares are
-- supplied by the existing stock kernels. No broader world simulation.
return function(Check,Motion,Speed,Follow,Loading,Packets,Income,hash)
  local M={}
  local floor,min,max=math.floor,math.min,math.max
  local function int(v,lo,hi) return type(v)=="number" and v==floor(v) and v>=lo and v<=hi end
  local function copy(v)
    if type(v)~="table" then return v end
    local o={}
    for k,a in pairs(v) do o[k]=copy(a) end
    return o
  end
  local function canonical(v)
    local t=type(v)
    if t=="string" then return "s"..#v..":"..v end
    if t=="number" then return "n"..("%.17g"):format(v)..":" end
    if t=="boolean" then return v and "t" or "f" end
    assert(t=="table","unsupported fixture identity input")
    local keys={}
    for k in pairs(v) do keys[#keys+1]=k end
    table.sort(keys,function(a,b) return canonical(a)<canonical(b) end)
    local parts={"["}
    for _,k in ipairs(keys) do
      parts[#parts+1]=canonical(k)
      parts[#parts+1]=canonical(v[k])
    end
    parts[#parts+1]="]"
    return table.concat(parts)
  end
  local function trunc(n) return n<0 and -floor(-n) or floor(n) end
  local CAP,PERIOD,LIMIT=112,185,640
  local function flat_accel(speed,units)
    -- MPS Regal: 42 quarter-tonnes, 9×10 horsepower, TE coefficient
    -- 76/256; temperate passengers weight=1/16 tonne. Source truncates
    -- cargo and vehicle weight separately before caching their sum.
    local mass=floor(42/4)+floor(units/16)
    speed=floor(speed/2)
    local power=90*746
    local max_te=floor(9800*mass*76/256)
    local drag=floor(2048/56)
    drag=drag+floor(3*drag/20)
    local resistance=10*mass+mass*floor(75*(128+speed)/128)+floor(6*drag*speed*speed/1000)
    local force
    if speed>0 then force=min(max_te,floor(power*18/(speed*5)))
    else force=max(min(max_te,power),mass*8+resistance) end
    if force==resistance then return 0 end
    local a=trunc((force-resistance)/(mass*4))
    return force<resistance and min(-1,a) or max(1,a)
  end

  -- The loader accepts the narrow paused continuation package only. It
  -- owns an observation-local fare ledger, not the original economy.
  function M.open(input,progress_journal)
    assert(input.schema=="luanttd-bus-first-delivery-input/1","unknown first delivery input")
    local accepted=Check.prepare(input.checkpoint,input.resume.existing_third_station,input.resume.depot_reserve_id)
    local start=accepted.checkpoint()
    local bs=start.vehicle
    local q=input.resume
    local target=assert(start.stations[q.target_station])
    local real_order=bs.orders[bs.order_index+1]
    assert(q.schema=="luanttd-bus-first-delivery/1" and q.paused and q.source_sha256==start.source.sha256
      and target.id==real_order.station and target.stop.kind=="bay_stop" and target.stop.status==3
      and q.target_town==target.town and int(q.target_goods.status,0,255) and q.target_goods.status%2==1
      and q.gradual_loading==1 and q.stock_breakdown_setting==1 and q.starting_company_delivered==0
      and q.starting_company_income=="0" and int(q.current_order_time,0,65535)
      and int(q.lateness_counter,-32768,32767),"unsupported first delivery source envelope")
    local start_tick=tonumber(start.clock.tick_counter)
    local raw_cash=start.companies[bs.owner].money
    local cash=tonumber(raw_cash)
    assert(int(start_tick,0,2^53-LIMIT) and int(cash,-2^53+65536,2^53-65536),"source clock/money arithmetic would lose precision")
    assert(start.settings["vehicle.roadveh_acceleration_model"]==1 and bs.raw.motion.gv_flags==0
      and #bs.raw.motion["path.td"]==0 and bs.cursor.speed==CAP,
      "expected one level realistically-accelerating stock bus without a branch cache")
    assert(bs.onboard<=8,"only one gradual unloading pulse may be exercised")
    assert(bs.timers.breakdown_ctr==0 and bs.timers.breakdown_delay==0,"active breakdown not supported")
    local trace=bs.route_trace
    local anchor
    local route={}
    local td=trace[1].td
    assert(td==0 or td==1 or td==8 or td==9,"only an axial route fits this isolated continuation")
    for i,a in ipairs(trace) do
      local x,z=a.position.x,a.position.z
      local n,w,e,s=accepted.board.tile_corners(x,z)
      anchor=anchor or n
      assert(a.td==td and n==anchor and w==anchor and e==anchor and s==anchor,"inclined or turning routes not supported")
      route[i]={id=a.tile,x=x-1,z=z-1}
      if i>1 then
        local dx,dz=({[0]=-1,0,1,0})[Follow.exit_direction(td)],({[0]=0,1,0,-1})[Follow.exit_direction(td)]
        assert(route[i-1].x+dx==x-1 and route[i-1].z+dz==z-1,"nonadjacent route")
      end
    end
    assert(#route>=2 and #route<=12,"unexpected first delivery route length")
    local st={id=target.id,tile=target.tile.source_id,stock={passenger={}},loading_order={}}
    local v={id=bs.id,cargo="passenger",units=bs.onboard,batches={},running=true,cargo_age_counter=bs.cursor.age_countdown}
    local c={x=bs.cursor.x16,y=bs.cursor.z16,height=bs.cursor.y8,state=bs.cursor.state,frame=bs.cursor.frame,
      direction=bs.cursor.direction,heading=bs.cursor.direction,speed=bs.cursor.speed,subspeed=bs.cursor.subspeed,
      progress=bs.cursor.progress,tile=bs.tile.source_id,part=1}
    local function xy(id)
      local x,z=accepted.board.source_xy(id)
      assert(x,"missing source tile for stock cargo")
      return x-1,z-1
    end
    local function packet(p,waiting)
      return {id=p.packet_id,units=p.count,age=p.periods_in_transit,origin_station=p.source,
        origin_tile=not waiting and p.source_xy or nil,
        travel_x=p["travelled.x"],travel_z=p["travelled.y"],source_type=p.source_type,source=p.source_id,
        feeder_share=0}
    end
    local ids={}
    for _,p in ipairs(bs.packets) do
      assert(p.feeder_share=="0","no feeder transfers in this isolated route")
      ids[p.packet_id]=true
      v.batches[#v.batches+1]=packet(p,false)
    end
    local waiting,keys=0,0
    for key in pairs(q.queue) do
      assert(int(key,1,31),"unknown waiting packet position")
      keys=keys+1
    end
    for i=1,keys do
      local p=q.queue[i]
      assert(p and int(p.packet_id,0,1048575) and not ids[p.packet_id] and int(p.count,1,31)
        and p.source==st.id and p.source_type==1 and p.source_id==target.town
        and p.source_xy==4294967295 and p.feeder_share=="0" and p["travelled.x"]==0 and p["travelled.y"]==0
        and int(p.periods_in_transit,0,65535),"unsupported destination waiting packet")
      ids[p.packet_id]=true
      waiting=waiting+p.count
      st.stock.passenger[i]=packet(p,true)
    end
    assert(waiting>0 and waiting<=31,"unsupported destination waiting queue size")
    local initial_waiting=waiting
    local elapsed,delivered,credit,arrival,unloaded,paid=0,0,0,nil,nil,nil
    local deliveries,payments=0,0
    local ages={}
    local function tick() return start_tick+elapsed end
    local reply={phase="paused", source_sha256=start.source.sha256}
    local ops={xy=xy,gradual=true,
      accepts=function(s,b) return s==st and b==v end,
      deliver=function(s,b,p)
        delivered=delivered+p.units
        unloaded=tick()
        ages[#ages+1]={packet=p.id,age=p.age,units=p.units}
        local spec=Income.temperate.passenger
        return Income.regular(p.units,Packets.distance(p,s.tile,xy),p.age,unpack(spec))
      end,
      unloaded=function()
        deliveries=deliveries+1
        assert(deliveries==1 and delivered==bs.onboard,"only one gradual unloading pulse is supported")
      end,
      loaded=function(_,_,n) waiting=waiting-n end,
      payment=function(_,_,p)
        assert(delivered>0 and p.delivered==delivered and p.route>0 and not paid,"wrong payment lifecycle")
        credit=credit+p.route
        paid=tick()
        payments=payments+1
      end}
    local binding=hash(canonical({start,q}))
    local side=bs.cursor.side
    local function move()
      local k,x,y,heading,frame=Motion.step(c,side)
      if k=="rotate" then c.direction,c.heading=heading,heading;return true end
      if k=="next_tile" then
        local next_tile=assert(route[c.part+1],"route went past verified destination")
        assert(x==Follow.exit_direction(td),"unexpected road table exit")
        local enter
        enter,c.x,c.y,c.direction,c.frame=Motion.enter(c,next_tile.x,next_tile.z,td,side,Motion.DEFAULT_START)
        assert(enter=="enter","stock motion entry is missing")
        c.heading,c.state,c.part,c.tile=c.direction,td,c.part+1,next_tile.id
        return true
      end
      assert(k=="move","unknown transition for the isolated route")
      if c.part==#route then
        if c.state<32 and c.frame==0 then
          -- TileEnter_Station allocates an available bay on the first
          -- within-tile frame, not while the previous tile is exiting.
          c.state=32+td
        elseif c.state>=32 and c.frame==Motion.bay_stop_frame(c.state,side) then
          c.state=c.state+4 -- RVS_ENTERED_STOP
          c.speed=0
          arrival=tick()
          Loading.begin(st,v,31,{wait=real_order.raw.wait_time,lateness=q.lateness_counter},ops)
          reply.phase="loading"
          return false
        end
      end
      c.x,c.y,c.direction,c.heading,c.frame=x,y,heading,heading,frame
      return true
    end
    local function step()
      assert(elapsed<LIMIT,"isolated continuation exceeded its fixed tick budget")
      elapsed=elapsed+1
      if v.load_state then
        Loading.tick(st,{[v.id]=v},ops)
      else
        assert(not paid,"this fixture stops at first settlement, not the return leg")
        local limit=min(c.heading%2==0 and CAP*3/4 or CAP,real_order.raw.max_speed*2)
        local distance=Speed.update(c,flat_accel(c.speed,v.units),4,limit)
        local needed=Speed.advance_distance(c.heading)
        local blocked=false
        while distance>=needed do
          distance=distance-needed
          if not move() then blocked=true;break end
          needed=Speed.advance_distance(c.heading)
        end
        if c.progress==0 then c.progress=blocked and needed-1 or distance end
      end
      Loading.age_vehicle(v,1,PERIOD)
      if paid then reply.phase="first_trip_settled" end
    end
    local R={}
    function R.state()
      local l=v.load_state
      local state={phase=reply.phase,source_sha256=reply.source_sha256,elapsed=elapsed,tick=tick(),
        tile=c.tile,pixels={x=c.x,z=c.y,y=c.height},native={x=1.5+c.x/8,y=.5+c.height/8,z=1.5+c.y/8},
        trackdir=c.state,frame=c.frame,heading=c.heading,speed=c.speed,subspeed=c.subspeed,progress=c.progress,
        age_counter=v.cargo_age_counter,units=v.units,arrived_tick=arrival,delivery_tick=unloaded,
        settlement_tick=paid,delivered=delivered,payment=credit,opening_cash=raw_cash,scratch_cash=cash+credit,
        reserve_id=start.reserve and start.reserve.id or nil,
        reserve_depot_tile=start.reserve and start.reserve.depot_tile or nil,
        waiting_initial=initial_waiting,waiting=waiting,loaded_at_destination=initial_waiting-waiting,
        unload_pulses=deliveries,payment_pulses=payments,delivered_packets=copy(ages),
        loading_ticks=l and l.ticks or nil,staged_fare=l and l.payment and l.payment.route or nil}
      return state
    end
    function R.resume()
      if reply.phase~="paused" then return false end
      if paid then reply.phase="first_trip_settled"
      elseif arrival then reply.phase="loading"
      else reply.phase="driving" end
      return true
    end
    function R.step(n)
      assert(int(n,0,74) and reply.phase~="paused","resume explicitly before ticking the isolated trip")
      for _=1,n do
        if paid then break end
        step()
      end
      return R.state()
    end
    function R.journal()
      local body=("LTBUS-R1\n%s\n%d\n"):format(binding,elapsed)
      return body..hash(body).."\n"
    end
    if progress_journal~=nil then
      assert(type(progress_journal)=="string" and #progress_journal<=160,"invalid isolated replay journal")
      local identity,n,digest=progress_journal:match("^LTBUS%-R1\n([0-9a-f]+)\n([0-9]+)\n([0-9a-f]+)\n$")
      n=tonumber(n)
      assert(identity==binding and int(n,0,LIMIT)
        and hash(("LTBUS-R1\n%s\n%d\n"):format(identity,n))==digest,"invalid isolated replay journal")
      -- Construct and replay privately: a failed replay never returns an object.
      for _=1,n do assert(not paid,"journal extends past settlement");step() end
      reply.phase="paused"
    end
    return R
  end
  return M
end
