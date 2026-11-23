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
  local order_verbs={append=true,up=true,down=true,remove=true,skip=true,replace=true,load=true,unload=true}
  local function adapter(mode,id)
    if mode=="ship" then
      if id~="ferry" and id~="coal" then return end
    elseif mode=="road" or mode=="rail" or mode=="air" or mode=="tram" then
      if not index(id) then return end
    else return end
    return R.orders and R.orders[mode]
  end
  local function destination(id)
    return index(id) or type(id)=="string" and #id<24 and id:match("^buoy:%d+$")
  end
  function A.orders(name,mode,id,page)
    if not owner(name) then return reply(false,"INVALID_REQUEST") end
    page=page or 1
    if not integer(page,1,32768) then return reply(false,"INVALID_DESTINATION_PAGE") end
    local handle=adapter(mode,id)
    if not handle then return reply(false,"UNSUPPORTED_ORDER_MODE") end
    local data,why=handle.read(name,id)
    if not data then return reply(false,why or "ORDERS_UNAVAILABLE") end
    local targets=data.targets or {}
    local visible={}
    local first=(page-1)*96+1
    for i=first,math.min(first+95,#targets) do visible[#visible+1]=targets[i] end
    data.targets,data.target_page,data.target_count=visible,page,#targets
    return reply(true,nil,data)
  end
  function A.company(name)
    if not owner(name) then return reply(false,"INVALID_REQUEST") end
    local c=s.companies[name]
    if not c then return reply(false,"COMPANY_NOT_OPEN") end
    return reply(true,nil,{cash=c.cash,loan=c.loan,revenue=c.revenue,expense=c.expense,
      month_revenue=c.month_rev,month_expense=c.month_exp,paid_units=c.paid_units,
      date=Sim.date(s),speed=s.speed})
  end
  function A.road_quote(name,request)
    if not owner(name) or not R.road_construction then return reply(false,"ROAD_QUOTE_UNAVAILABLE") end
    if not s.companies[name] then return reply(false,"COMPANY_NOT_OPEN") end
    local quote,why=R.road_construction.quote(name,request)
    return reply(quote~=nil,why,quote)
  end
  function A.advance(days)
    if not integer(days,0,max_days or 4) then return reply(false,"INVALID_TICK_BATCH") end
    for _=1,days do R.day() end
    return reply(true)
  end
  function A.command(name,c)
    if not owner(name) or type(c)~="table" then return reply(false,"INVALID_REQUEST") end
    if c.revision~=authority_revision then return reply(false,"STALE_COMMAND") end
    local ok,note,value
    if c.kind=="company_open" then
      if s.companies[name] then return A.company(name) end
      Sim.company(s,name)
      ok,note=true,"Company opened."
    elseif c.kind=="company_loan" and (c.amount==10000 or c.amount==-10000) then
      if not s.companies[name] then return reply(false,"COMPANY_NOT_OPEN") end
      ok,note=Sim.loan(s,name,c.amount)
    elseif c.kind=="road_buy" and type(c.engine)=="string" and type(c.cargo)=="string" and tile_id(c.depot) then
      if not s.companies[name] then return reply(false,"COMPANY_NOT_OPEN") end
      local e=Sim.vehicle_offer(s,c.engine)
      if not (e and e.mode=="road" and Sim.vehicle_available(s,c.engine)) then return reply(false,"UNAVAILABLE_VEHICLE") end
      if c.cost~=e.cost then return reply(false,"VEHICLE_PRICE_CHANGED") end
      value,note=Sim.purchase(s,name,c.engine,c.cargo,nil,c.depot)
      ok=value~=nil
    elseif c.kind=="road_commit" and R.road_construction then
      ok,note,value=R.road_construction.commit(name,c.request,c.quote)
    elseif c.kind=="road_build" and tile_id(c.first) and tile_id(c.last) then
      local x,z=Sim.xy(c.first)
      local u,v=Sim.xy(c.last)
      if math.abs(x-u)+math.abs(z-v)>=128 then return reply(false,"ROAD_DRAG_TOO_LONG") end
      local cells=Sim.line(c.first,c.last)
      ok,note=Sim.build(s,name,"road",cells)
    elseif c.kind=="vehicle_order" and order_verbs[c.operation] then
      local handle=adapter(c.mode,c.vehicle)
      if not handle or not (type(c.order_revision)=="string" and #c.order_revision<=8192
        or integer(c.order_revision,0,2147483647)) then return reply(false,"INVALID_VEHICLE_ORDER") end
      if c.operation=="append" or c.operation=="replace" then
        if not destination(c.destination) then return reply(false,"INVALID_DESTINATION") end
      elseif c.operation=="load" or c.operation=="unload" then
        if not integer(c.destination,0,15) then return reply(false,"INVALID_CARGO_RULE") end
      end
      if c.operation~="append" and not integer(c.row,1,254) then return reply(false,"INVALID_ORDER_ROW") end
      ok,note=handle.edit(name,c.vehicle,c.order_revision,c.operation,c.row,c.destination)
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
    return reply(ok,note,value)
  end
  function A.snapshot(x,z,w,h,fraction)
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
          rail=t.rail_tracks,road=t.road_bits,water=t.water_class,house=not not t.house,station=t.station}
      end
    end
    local vehicles={}
    for id,v in pairs(s.fleet) do
      local at=Sim.position(s,v)
      if at then
        local a,b=Sim.xy(at)
        if a>=x and a<x+w and b>=z and b<z+h then
          vehicles[#vehicles+1]={id=id,tile=at,engine=v.engine,running=not not v.running,order_count=#(v.orders or {})}
        end
      end
    end
    table.sort(vehicles,function(a,b) return a.id<b.id end)
    fraction=type(fraction)=="number" and fraction>=0 and fraction<=1 and fraction or 1
    return reply(true,nil,{x=x,z=z,width=w,height=h,tiles=tiles,vehicles=vehicles,
      actors=R.actors and R.actors(x,z,w,h,fraction) or nil})
  end
  function A.snapshots(windows,fraction)
    if type(windows)~="table" or #windows<1 or #windows>9 then
      return reply(false,"INVALID_INTEREST_BATCH")
    end
    local packets={}
    for _,w in ipairs(windows) do
      if type(w)~="table" then return reply(false,"INVALID_INTEREST_WINDOW") end
      local r=A.snapshot(w.x,w.z,w.w,w.h,fraction)
      if not r.ok then return r end
      packets[#packets+1]=r.value
    end
    if #packets~=#windows then return reply(false,"INVALID_INTEREST_BATCH") end
    return reply(true,nil,packets)
  end
  return A
end
