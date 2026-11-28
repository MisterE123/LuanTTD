-- Produce compact, engine-free actor pose samples for one visible region.
-- No route, vehicle controller, ObjectRef or mutable state leaves the owner.
local floor=math.floor
local empty_runs={}
local function rail_candidates(runs,frame,poses,x,z,w,h)
  local mask=frame.actor_interest
  if not frame.whole_trains or not frame.multi_view or not mask or #runs<16 then return runs end
  local indexed=frame.rail_buckets
  if not indexed then
    -- Sample the full consist once. A tail in the visible union is
    -- enough even when the locomotive's bucket is outside it.
    indexed={};frame.rail_buckets=indexed
    for _,r in ipairs(runs) do
      for _,body in ipairs(poses(r)) do
        local p=body.pos
        if p then
          local zz,xx=floor((floor((p.z+.5)/2)-1)/32),floor((floor((p.x+.5)/2)-1)/32)
          if mask[zz] and mask[zz][xx] then
            local row=indexed[zz]
            if not row then row={};indexed[zz]=row end
            local group=row[xx]
            if not group then group={};row[xx]=group end
            if group[#group]~=r then group[#group+1]=r end
          end
        end
      end
    end
  end
  local x0,x1=floor((x-1)/32),floor((x+w-2)/32)
  local z0,z1=floor((z-1)/32),floor((z+h-2)/32)
  if x0==x1 and z0==z1 then return indexed[z0] and indexed[z0][x0] or empty_runs end
  local nearby,seen
  for zz=z0,z1 do
    local row=indexed[zz]
    if row then
      for xx=x0,x1 do
        local group=row[xx]
        if group then
          if not nearby then nearby,seen={},{} end
          for _,r in ipairs(group) do
            if not seen[r] then seen[r]=true;nearby[#nearby+1]=r end
          end
        end
      end
    end
  end
  return nearby or empty_runs
end
return function(Sim,R,x,z,w,h,fraction,frame)
  local s=R.world
  frame=frame or {road={},rail={}}
  local function road(v)
    local p=frame.road[v]
    if not p then
      local pos,yaw,pitch,bore
      if R.road_pose then pos,yaw,pitch,bore=R.road_pose(v,fraction,frame.live_tick) end
      p={at=Sim.position(s,v),pos=pos,yaw=yaw,pitch=pitch,bore=bore}
      frame.road[v]=p
    end
    return p.at,p.pos,p.yaw,p.pitch,p.bore
  end
  local function train(r)
    local parts=frame.rail[r]
    if not parts then parts=R.rail.poses(r,fraction,frame.live_tick);frame.rail[r]=parts end
    return parts
  end
  local out={}
  local function inside(a,b) return a>=x and a<x+w and b>=z and b<z+h end
  local function tile(id)
    if not id then return false end
    return inside(Sim.xy(id))
  end
  local function point(p)
    return p and inside(math.floor((p.x+.5)/2),math.floor((p.z+.5)/2))
  end
  local function xyz(p) return {x=p.x,y=p.y,z=p.z} end
  local function id_for(mode,id) return mode..":"..id end
  local function add(mode,id,data)
    data.sound_paused=s.speed==0 or nil
    data.mode,data.id,data.key=mode,id,id_for(mode,id)
    out[#out+1]=data
  end
  local function road_actor(id,v,at,pos,yaw,pitch,bore)
    local f=Sim.road_motion_frame(s,v)
    local pose=f and {f[1],f[2],f[3],f[4],f[5]} or nil
    local fault=v.road_fault
    -- The worker is the only owner of the RC1 countdown. Export only the
    -- visible smoke flag (never the timer, route or RNG).
    local smoke=pos and not bore and s.speed~=0 and not (v.crashed or v.depot or
      v.road_speed_state and v.road_speed_state.depot_wait) and
      fault and fault.breakdown_ctr==1 and fault.breakdown_delay>0
    local offer=Sim.vehicle_offer and Sim.vehicle_offer(s,v.engine)
    return {mode="road",id=id,key=id_for("road",id),sound_paused=s.speed==0 or nil,
      tile=at,frame=pose,engine=v.engine,passenger=v.cargo=="passenger",running=not not v.running,
      sound_engine=offer and (offer.stock_id or offer.stock_engine_id),
      breakdown_smoke=smoke and true or nil,
      sound_idle=not v.running or not not (v.depot or v.load_state or
        v.road_speed_state and v.road_speed_state.depot_wait),
      sound_tick=fault and fault.tick_counter,sound_crashed=v.crashed or nil,
      pos=pos and xyz(pos),yaw=yaw,pitch=pitch,hidden=not pos,loaded=(v.units or 0),
      owner=v.owner,home_depot=v.home_depot or v.depot,label=v.name,order_count=#(v.orders or {})}
  end
  if R.road_coordinates and R.road_finish then
    -- The sampling fraction and world state are shared by the entire
    -- viewport reply, including overlapping and nonaligned sectors.
    local size,floor=32,math.floor
    local want=frame.actor_interest
    local buckets=frame.road_buckets
    if not buckets then
      buckets={}
      frame.road_buckets=buckets
      for id,v in pairs(s.fleet) do
        local px,pz,yaw,bridge,bore_height=R.road_coordinates(v,fraction,frame.live_tick)
        local at,u,b
        if px~=nil then
          u,b=floor((px+.5)/2),floor((pz+.5)/2)
        else
          at=Sim.position(s,v)
          if at then u,b=Sim.xy(at) end
        end
        if u and u>=1 and u<=Sim.W and b>=1 and b<=Sim.H then
          local bu,bb=floor((u-1)/size),floor((b-1)/size)
          local interest=want and want[bb]
          if not want or interest and interest[bu] then
            local row=buckets[bb]
            if not row then row={};buckets[bb]=row end
            local bucket=row[bu]
            if not bucket then bucket={};row[bu]=bucket end
            -- Never allocate a pose record for a bucket outside this
            -- packet's entire interest union. Finish actual poses on
            -- demand after testing the exact rectangle as before.
            bucket[#bucket+1]={u,b,id,v,at,px,pz,yaw,bridge,bore_height}
          end
        end
      end
    end
    for bb=floor((z-1)/size),floor((z+h-2)/size) do
      local row=buckets[bb]
      if row then
        for bu=floor((x-1)/size),floor((x+w-2)/size) do
          local bucket=row[bu]
          if bucket then
            for _,p in ipairs(bucket) do
              if inside(p[1],p[2]) then
                local actor=p.actor
                if not actor then
                  local id,vehicle,at=p[3],p[4],p[5]
                  actor=road_actor(id,vehicle,at or Sim.position(s,vehicle),
                    R.road_finish(p[6],p[7],p[8],p[9],p[10]))
                  p.actor=actor
                end
                out[#out+1]=actor
              end
            end
          end
        end
      end
    end
  else
    for id,v in pairs(s.fleet) do
      local at,pos,yaw,pitch,bore=road(v)
      if point(pos) or not pos and tile(at) then out[#out+1]=road_actor(id,v,at,pos,yaw,pitch,bore) end
    end
  end
  if R.rail then
    local platform=R.rail.platforms and R.rail.platforms.current(s)
    if platform then
      local p,yaw,id=R.rail.platform_pose(platform)
      if point(p) then add("rail_pilot",1,{owner=platform.owner,pos=p,yaw=yaw,model=platform.visual,tile=id}) end
    end
    local dispatch=R.rail.run.current(s)
    local runs=dispatch and dispatch.runs or empty_runs
    for _,r in ipairs(rail_candidates(runs,frame,train,x,z,w,h)) do
      local parts
      local consist=train(r)
      for _,body in ipairs(consist) do
        if point(body.pos) then
          -- A fast sighting carries every exposed body from one sample,
          -- even when the first body seen is the last car in the train.
          if frame.whole_trains then parts=consist;break end
          parts=parts or {}
          parts[#parts+1]=body
        end
      end
      if parts then
        local unit=R.rail.owned and r.fleet_id and R.rail.owned.get(s,r.owner,r.fleet_id)
        local lead=consist[1] and consist[1].pos
        local index=lead and Sim.id(math.floor((lead.x+.5)/2),math.floor((lead.z+.5)/2))
        local crossing=index and s.tiles[index] and s.tiles[index].level_crossing
        add("rail",r.fleet_id or r.id,{owner=r.owner,engine=r.stock_engine,wagon=r.stock_wagon,
          parts=parts,running=not (r.stopped or r.failure or r.crashed),complete_parts=frame.whole_trains,part_count=#r.consist.parts,collectors=not not r.bridge_collectors,
          sound_idle=r.stopped or r.phase=="depot" or r.phase=="dwell" or r.phase=="arrived",
          sound_crashed=r.crashed or nil,sound_breakdown=r.breakdown or nil,
          sound_crossing=crossing and crossing.barred and index or nil,
          depot=unit and unit.depot,label=unit and "Train "..unit.unit_number})
      end
    end
  end
  if R.water then
    local ferry=R.water.run.current(s)
    if ferry then
      local p,dir
      if ferry.paid_clock and not frame.live_tick then p,dir=Sim.ferry_paid_pose(s,fraction)
      else p,dir=R.water.run.pose(ferry) end
      if point(p) then add("ship","ferry",{owner=ferry.owner,engine=ferry.engine_id,pos=xyz(p),dir=dir,
        passenger=true,running=not (ferry.stopped or ferry.crashed or ferry.phase=="blocked"),
        sound_idle=ferry.stopped or ferry.phase~="sailing",sound_crashed=ferry.crashed or nil,
        depot=ferry.depot,label=ferry.engine_id==208 and "Bakewell 300 Hovercraft" or ferry.engine_id==207 and "FFP Passenger Ferry" or "MPS Passenger Ferry"}) end
    end
    if R.water.tanker then
      local p,dir=R.water.tanker.pose(s,fraction,frame.live_tick)
      if point(p) then
        local hull=R.water.tanker.status(s)
        add("ship","oil",{owner=hull.owner,engine=hull.engine,pos=xyz(p),dir=dir,depot=hull.depot,
          sound_idle=hull.phase~="sailing",label=hull.name})
      end
    end
    if R.water.freight and R.water.coal then
      local ship=R.water.freight.current(s)
      if ship then
        local p,dir=R.water.coal.pose(s,fraction,frame.live_tick)
        if point(p) then
          local hull=R.water.coal.status(s)
          add("ship","coal",{owner=ship.owner,engine=hull and hull.engine,pos=xyz(p),dir=dir,depot=ship.depot,
            sound_idle=ship.stopped or ship.phase~="sailing",sound_crashed=ship.crashed or nil,
          label=hull and hull.name or "Yate Cargo Ship"})
        end
      end
    end
  end
  if R.air then
    for _,run in ipairs(R.air.run.all(s)) do
      local p,dir,airborne
      if run.paid_clock and not frame.live_tick then p,dir,airborne=Sim.air_paid_pose(s,fraction,run.paid_clock)
      else p,dir=R.air.run.pose(run) end
      if point(p) then
        if airborne==nil then airborne=run.vehicle.airborne end
        local v=run.vehicle
        local engine=R.air.run.engine_for and R.air.run.engine_for(run)
        add("air",run.paid_clock or 1,{owner=run.owner,engine=run.engine_id,pos=xyz(p),dir=dir,
          passenger=not v.helicopter and not (engine and engine.passengers==0),
          running=not (v.stopped or v.crashed or v.hidden or run.phase=="blocked"),
          airborne=not not airborne,sound_crashed=v.crashed or nil,
          breakdown_smoke=(v.broken or v.crashed and (v.crashed_counter or 0)<650) and true or nil,
          sound_helicopter=run.vehicle.helicopter or nil,rotor_period=run.vehicle.helicopter and math.floor((run.vehicle.rotor_speed or 0)/16),
          label=engine and engine.name or "Aircraft #"..(run.paid_clock or 1)})
      end
    end
  end
  if R.tram then
    local service=R.tram.run
    local runs=service.all and service.all(s) or {service.current(s)}
    for _,run in ipairs(runs) do
      local f,pos,yaw,pitch
      if R.tram.pose_at and not frame.live_tick then f,pos,yaw,pitch=R.tram.pose_at(fraction,service.serial and service.serial(run))
      else
        f=service.frame(run)
        if f then pos,yaw,pitch=R.tram.pose(f) end
      end
      if f and point(pos) then
        local id=service.ui_id and service.ui_id(s,run) or 1
        add("tram",id,{owner=run.owner,tile=f[4],frame={f[1],f[2],f[3],f[4],f[5]},pos=pos,yaw=yaw,pitch=pitch})
      end
    end
  end
  table.sort(out,function(a,b) return a.key<b.key end)
  return out
end
