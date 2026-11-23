-- Produce compact, engine-free actor pose samples for one visible region.
-- No route, vehicle controller, ObjectRef or mutable state leaves the owner.
return function(Sim,R,x,z,w,h,fraction)
  local s=R.world
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
    data.mode,data.id,data.key=mode,id,id_for(mode,id)
    out[#out+1]=data
  end
  for id,v in pairs(s.fleet) do
    local at=Sim.position(s,v)
    local pos,yaw,pitch
    if R.road_pose then pos,yaw,pitch=R.road_pose(v,fraction) end
    if point(pos) or not pos and tile(at) then
      local f=Sim.road_motion_frame(s,v)
      local pose=f and {f[1],f[2],f[3],f[4],f[5]} or nil
      add("road",id,{tile=at,frame=pose,engine=v.engine,running=not not v.running,
        pos=pos and xyz(pos),yaw=yaw,pitch=pitch,hidden=not pos,loaded=(v.units or 0),
        owner=v.owner,home_depot=v.home_depot or v.depot,label=v.name,order_count=#(v.orders or {})})
    end
  end
  if R.rail then
    local dispatch=R.rail.run.current(s)
    for _,r in ipairs(dispatch and dispatch.runs or {}) do
      local parts={}
      for _,body in ipairs(R.rail.poses(r,fraction)) do
        if point(body.pos) then parts[#parts+1]=body end
      end
      if #parts>0 then
        local unit=R.rail.owned and r.fleet_id and R.rail.owned.get(s,r.owner,r.fleet_id)
        add("rail",r.fleet_id or r.id,{owner=r.owner,engine=r.stock_engine,wagon=r.stock_wagon,
          parts=parts,part_count=#r.consist.parts,collectors=not not r.bridge_collectors,
          depot=unit and unit.depot,label=unit and "Train "..unit.unit_number})
      end
    end
  end
  if R.water then
    local ferry=R.water.run.current(s)
    if ferry then
      local p,dir
      if ferry.paid_clock then p,dir=Sim.ferry_paid_pose(s,fraction)
      else p,dir=R.water.run.pose(ferry) end
      if point(p) then add("ship","ferry",{owner=ferry.owner,engine=ferry.engine_id,pos=xyz(p),dir=dir,
        depot=ferry.depot,label=ferry.engine_id==207 and "FFP Passenger Ferry" or "MPS Passenger Ferry"}) end
    end
    if R.water.freight and R.water.coal then
      local ship=R.water.freight.current(s)
      if ship then
        local p,dir=R.water.coal.pose(s,fraction)
        if point(p) then add("ship","coal",{owner=ship.owner,pos=xyz(p),dir=dir,depot=ship.depot,label="Yate Cargo Ship"}) end
      end
    end
  end
  if R.air then
    for _,run in ipairs(R.air.run.all(s)) do
      local p,dir,airborne
      if run.paid_clock then p,dir,airborne=Sim.air_paid_pose(s,fraction,run.paid_clock)
      else p,dir=R.air.run.pose(run) end
      if point(p) then
        if airborne==nil then airborne=run.vehicle.airborne end
        add("air",run.paid_clock or 1,{owner=run.owner,engine=run.engine_id,pos=xyz(p),dir=dir,
          airborne=not not airborne,label="Aircraft #"..(run.paid_clock or 1)})
      end
    end
  end
  if R.tram then
    local run=R.tram.run.current(s)
    local f=run and R.tram.run.frame(run)
    if f then
      local pos,yaw=R.tram.pose(f)
      if point(pos) then
        add("tram",1,{owner=run.owner,tile=f[4],frame={f[1],f[2],f[3],f[4],f[5]},pos=pos,yaw=yaw})
      end
    end
  end
  table.sort(out,function(a,b) return a.key<b.key end)
  return out
end
