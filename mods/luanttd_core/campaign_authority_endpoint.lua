-- A bounded command/snapshot endpoint for a single campaign owner.
-- A host must supply the authenticated player name, never a form field.
-- Ordinary gameplay is not switched to this endpoint yet.
return function(Sim,R,max_days)
  local s=R.world
  local A={}
  local authority_revision=s.authority_revision or 0
  local function integer(x,lo,hi)
    return type(x)=="number" and x>=lo and x<=hi and x%1==0
  end
  local function tile_id(id) return integer(id,1,Sim.W*Sim.H) end
  local function index(id) return integer(id,1,2147483647) end
  local function owner(n) return type(n)=="string" and #n>0 and #n<=32 end
  local function reply(ok,why,extra)
    return {ok=not not ok,why=why,revision=authority_revision,day=s.day,
      tick=s.passenger_house_clock and s.passenger_house_clock.counter or 0,value=extra}
  end
  function A.advance(days)
    if not integer(days,0,max_days or 4) then return reply(false,"INVALID_TICK_BATCH") end
    for _=1,days do R.day() end
    return reply(true)
  end
  function A.command(name,c)
    if not owner(name) or type(c)~="table" then return reply(false,"INVALID_REQUEST") end
    if c.revision~=authority_revision then return reply(false,"STALE_COMMAND") end
    local ok,note
    if c.kind=="road_build" and tile_id(c.first) and tile_id(c.last) then
      local x,z=Sim.xy(c.first)
      local u,v=Sim.xy(c.last)
      if math.abs(x-u)+math.abs(z-v)>=128 then return reply(false,"ROAD_DRAG_TOO_LONG") end
      local cells=Sim.line(c.first,c.last)
      ok,note=Sim.build(s,name,"road",cells)
    elseif c.kind=="road_order_add" and index(c.vehicle) and index(c.station) then
      local v=s.fleet[c.vehicle]
      if not v or v.owner~=name or not Sim.vehicles[v.engine] or Sim.vehicles[v.engine].mode~="road" then
        return reply(false,"NOT_YOUR_ROAD_VEHICLE")
      end
      ok,note=Sim.add_order(s,name,c.vehicle,c.station)
    elseif c.kind=="road_toggle" and index(c.vehicle) then
      local v=s.fleet[c.vehicle]
      if not v or v.owner~=name or not Sim.vehicles[v.engine] or Sim.vehicles[v.engine].mode~="road" then
        return reply(false,"NOT_YOUR_ROAD_VEHICLE")
      end
      ok,note=Sim.toggle(s,name,c.vehicle)
    else return reply(false,"UNKNOWN_OR_INVALID_COMMAND") end
    if ok then
      authority_revision=authority_revision+1
      s.authority_revision=authority_revision
    end
    return reply(ok,note)
  end
  function A.snapshot(x,z,w,h)
    if not integer(x,1,Sim.W) or not integer(z,1,Sim.H)
      or not integer(w,1,32) or not integer(h,1,32) or x+w-1>Sim.W or z+h-1>Sim.H then
      return reply(false,"INVALID_INTEREST_WINDOW")
    end
    local tiles={}
    for dz=0,h-1 do
      for dx=0,w-1 do
        local id=Sim.id(x+dx,z+dz)
        local t=s.tiles[id]
        local slope,level=R.terrain.tile(s.corner_grid,x+dx,z+dz)
        tiles[#tiles+1]={id=id,level=level,slope=slope,ground=t.terrain,build=t.build,
          rail=t.rail_tracks,road=t.road_bits,water=t.water_class,house=not not t.house}
      end
    end
    local vehicles={}
    for id,v in pairs(s.fleet) do
      local at=Sim.position(s,v)
      if at then
        local a,b=Sim.xy(at)
        if a>=x and a<x+w and b>=z and b<z+h then
          vehicles[#vehicles+1]={id=id,tile=at,engine=v.engine,running=not not v.running}
        end
      end
    end
    table.sort(vehicles,function(a,b) return a.id<b.id end)
    return reply(true,nil,{x=x,z=z,width=w,height=h,tiles=tiles,vehicles=vehicles})
  end
  return A
end
