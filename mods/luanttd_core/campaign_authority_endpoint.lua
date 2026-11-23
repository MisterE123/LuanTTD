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
  local rail_quotes,quote_sequence={},0
  function A.rail_quote(name,request)
    local rail=R.rail and R.rail.build
    if not owner(name) or not rail or type(request)~="table" or not s.companies[name] then
      return reply(false,"RAIL_QUOTE_UNAVAILABLE")
    end
    if request.tool=="autotrack" then
      local start,last=request.start,request.finish
      if type(start)~="table" or type(last)~="table" or
        not (integer(start.x,16,Sim.W*16+15) and integer(start.z,16,Sim.H*16+15)
          and integer(last.x,16,Sim.W*16+15) and integer(last.z,16,Sim.H*16+15))
        or math.abs(start.x-last.x)+math.abs(start.z-last.z)>=128*16 then
        return reply(false,"INVALID_RAIL_DRAG")
      end
      local q,why=rail.quote_autotrack(name,start,last)
      rail_quotes[name]=nil
      if not q then return reply(false,why) end
      quote_sequence=quote_sequence+1
      rail_quotes[name]={token=quote_sequence,plan=q}
      return reply(true,nil,{tiles=q.ids,cost=q.price,token=quote_sequence,kind=q.kind})
    end
    local first,last=request.first,request.last or request.first
    if not tile_id(first) or not tile_id(last) then return reply(false,"INVALID_TILE") end
    local x,z=Sim.xy(first)
    local u,v=Sim.xy(last)
    if math.abs(x-u)+math.abs(z-v)>=128 then return reply(false,"RAIL_DRAG_TOO_LONG") end
    local q,why
    if request.tool=="track" and integer(request.track,0,5) then
      q,why=rail.quote_track(name,first,last,request.track,request.remove==true)
    elseif request.tool=="depot" and integer(request.direction,0,3) then
      q,why=rail.quote_depot(name,first,request.direction)
    elseif request.tool=="station" and integer(request.axis,0,1) and
      integer(request.length,1,16) and integer(request.tracks,1,16) then
      if (math.abs(x-u)+1)*(math.abs(z-v)+1)>256 then return reply(false,"RAIL_STATION_TOO_LARGE") end
      q,why=rail.quote_station(name,first,last,{axis=request.axis,length=request.length,
        tracks=request.tracks,separate=request.separate==true,drag=request.drag==true})
    elseif request.tool=="signal" and integer(request.trackdir,0,13) and
      (request.kind==0 or request.kind==4 or request.kind==5) then
      q,why=rail.quote_signal_track(name,first,request.trackdir,request.kind,request.both==true)
    elseif request.tool=="signal_flip" and integer(request.track,0,5) then
      q,why=rail.quote_flip_signal(name,first,request.track)
    elseif request.tool=="signal_remove" and integer(request.track,0,5) then
      q,why=rail.quote_remove_signal(name,first,request.track)
    else return reply(false,"UNSUPPORTED_RAIL_GESTURE") end
    rail_quotes[name]=nil
    if not q then return reply(false,why) end
    quote_sequence=quote_sequence+1
    rail_quotes[name]={token=quote_sequence,plan=q}
    return reply(true,nil,{tiles=q.ids,cost=q.price,token=quote_sequence,kind=q.kind})
  end
  local transport_quotes={}
  function A.transport_quote(name,request)
    if not owner(name) or not R.transport or not s.companies[name] then return reply(false,"TRANSPORT_QUOTE_UNAVAILABLE") end
    local quote,why=R.transport.quote(name,request)
    transport_quotes[name]=nil
    if not quote then return reply(false,why) end
    quote_sequence=quote_sequence+1
    transport_quotes[name]={quote=quote,token=quote_sequence,topology=s.topology}
    return reply(true,nil,{token=quote_sequence,cost=quote.price,tiles=quote.tiles})
  end
  local terrain_quotes={}
  function A.terrain_quote(name,request)
    if not owner(name) or not R.landscape or not s.companies[name] then return reply(false,"TERRAIN_QUOTE_UNAVAILABLE") end
    local quote,why=R.landscape.quote(name,request)
    terrain_quotes[name]=nil
    if not quote then return reply(false,why) end
    quote_sequence=quote_sequence+1
    terrain_quotes[name]={quote=quote,token=quote_sequence}
    return reply(true,nil,{token=quote_sequence,cost=quote.cost,tiles=quote.tiles,corners=quote.corners})
  end
  function A.company(name)
    if not owner(name) then return reply(false,"INVALID_REQUEST") end
    local c=s.companies[name]
    if not c then return reply(false,"COMPANY_NOT_OPEN") end
    local year,month,day=Sim.date(s)
    return reply(true,nil,{cash=c.cash,loan=c.loan,revenue=c.revenue,expense=c.expense,
      month_revenue=c.month_rev,month_expense=c.month_exp,paid_units=c.paid_units,
      year=year,month=month,day_of_month=day,world_day=s.day,speed=s.speed})
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
    if c.kind=="terrain_commit" then
      local q=terrain_quotes[name]
      terrain_quotes[name]=nil
      if not q or q.token~=c.token then return reply(false,"TERRAIN_QUOTE_EXPIRED") end
      ok,note,value=R.landscape.commit(name,q.quote)
    elseif c.kind=="transport_commit" then
      local q=transport_quotes[name]
      transport_quotes[name]=nil
      if not q or q.token~=c.token or q.topology~=s.topology then return reply(false,"TRANSPORT_QUOTE_EXPIRED") end
      ok,note,value=R.transport.commit(name,q.quote)
    elseif c.kind=="transport_start" and R.transport then
      ok,note=R.transport.start(name,c)
    elseif c.kind=="rail_commit" then
      local quote=rail_quotes[name]
      rail_quotes[name]=nil
      if not quote or quote.token~=c.token then return reply(false,"RAIL_QUOTE_EXPIRED") end
      ok,note=R.rail.build.build(name,quote.plan)
      if ok then value=quote.plan.ids end
    elseif c.kind=="company_open" then
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
        local slope,level,top=R.terrain.tile(s.corner_grid,x+dx,z+dz)
        tiles[#tiles+1]={id=id,level=level,slope=slope,top=top,ground=t.terrain,build=t.build,
          rail=t.rail_tracks,road=t.road_bits,water=t.water_class,house=not not t.house,station=t.station,
          surface=R.terrain_projection and R.terrain_projection.tile(t) or nil,
          river_direction=t.water_class=="river" and R.river_direction and R.river_direction(id) or nil}
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
      corners=R.terrain_projection and R.terrain_projection.corners(R.terrain,s.corner_grid,x,z,w,h) or nil,
      registries=R.terrain_projection and R.terrain_projection.registries(s,tiles) or nil,
      actors=R.actors and R.actors(x,z,w,h,fraction) or nil})
  end
  function A.snapshots(windows,fraction,players)
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
    local r=reply(true,nil,packets)
    r.companies={}
    if type(players)=="table" and #players<=32 then
      for _,name in ipairs(players) do
        local company=A.company(name)
        if company.ok then r.companies[name]=company.value end
      end
    end
    return r
  end
  return A
end
