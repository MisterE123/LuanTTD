local freight_mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local Freight=dofile(freight_mod.."/rail_freight_kinds.lua")
-- A bounded command/snapshot endpoint for a single campaign owner.
-- A host must supply the authenticated player name, never a form field.
-- Ordinary gameplay routes simulation commands and snapshots here.
return function(Sim,R,max_days)
  local s=R.world
  local A={}
  local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
  local order_target=dofile(mod.."/campaign_order_target.lua")
  local styles=dofile(mod.."/bridge_style_assets.lua")
  local place_labels=dofile(mod.."/world_place_labels.lua")
  local Lift=dofile(mod.."/openttd/town_lift.lua")
  local TownFoundation=dofile(mod.."/openttd/town_foundation.lua")
  local front_steps=dofile(mod.."/house_front_steps.lua").make(dofile(mod.."/house_frontage.lua"))
  local function steps_at(id,t,slope,level)
    if not (t and t.house and t.source_house and Sim.road_surface and Sim.road_bits) then return end
    if not slope then
      local x,z=Sim.xy(id)
      slope,level=R.terrain.tile(s.corner_grid,x,z)
    end
    if slope~=nil and level~=nil then return front_steps(Sim,s,id,t,TownFoundation.level(slope,level)) end
  end
  local function lift_snapshot(x,z,w,h)
    return Lift.visible(s.stock_town_lifts,Sim,s.tiles,x,z,w,h)
  end
  local function facility_record(registry,id)
    return id~=nil and s[registry] and s[registry][id]
  end
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
      if id~="ferry" and id~="coal" and id~="oil" then return end
    elseif mode=="road" or mode=="rail" or mode=="air" or mode=="tram" then
      if not index(id) then return end
    else return end
    return R.orders and R.orders[mode]
  end
  local function destination(id)
    return index(id) or type(id)=="string" and #id<24 and (id:match("^buoy:%d+$") or id:match("^waypoint:%d+$"))
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
  local function auto_quote(rail,name,request,gauge)
    local start,last=request.start,request.finish
    if type(start)~="table" or type(last)~="table" or
      not (integer(start.x,16,Sim.W*16+15) and integer(start.z,16,Sim.H*16+15)
        and integer(last.x,16,Sim.W*16+15) and integer(last.z,16,Sim.H*16+15))
      or math.abs(start.x-last.x)+math.abs(start.z-last.z)>=128*16 then
      return nil,"INVALID_RAIL_DRAG"
    end
    return rail.quote_autotrack(name,start,last,gauge)
  end
  local function auto_offer(q,name)
    local draw=R.rail_preview and R.rail_preview(q.pieces,name) or nil
    local stamp={q.price,q.tree_count or 0,q.stopped_at or "-",q.skipped_start or 0}
    for _,p in ipairs(q.pieces) do
      stamp[#stamp+1]=table.concat({p.id,p.tracks,p.result_railtype or 0,p.crossing_quote and 1 or 0},",")
    end
    for _,g in ipairs(draw or {}) do
      stamp[#stamp+1]=g.mesh.."/"..g.pos.y
    end
    return {tiles=q.ids,cost=q.price,pieces=not draw and q.pieces or nil,
      draw=draw,ticket=table.concat(stamp,":"),stopped_at=q.stopped_at,
      skipped_start=q.skipped_start,tree_count=q.tree_count}
  end
  function A.rail_quote(name,request,peek)
    local rail=R.rail and R.rail.build
    if not owner(name) or not rail or type(request)~="table" or not s.companies[name] then
      return reply(false,"RAIL_QUOTE_UNAVAILABLE")
    end
    local gauge=request.railtype
    if gauge~=nil and not integer(gauge,0,3) then return reply(false,"INVALID_RAIL_TYPE") end
    if request.tool=="autotrack" then
      local q,why=auto_quote(rail,name,request,gauge)
      if peek then return reply(q~=nil,why,q and auto_offer(q,name)) end
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
    if request.tool=="wire" and (request.target==0 or request.target==1) and R.rail.wire then
      if (math.abs(x-u)+1)*(math.abs(z-v)+1)>256 then return reply(false,"Select up to 256 tiles at a time.") end
      local ids={}
      for row=math.min(z,v),math.max(z,v) do
        for column=math.min(x,u),math.max(x,u) do ids[#ids+1]=Sim.id(column,row) end
      end
      local plan,error_=R.rail.wire.quote(name,ids,request.target)
      if peek then return reply(plan~=nil,error_,plan and {tiles=plan.ids,cost=plan.cost}) end
      rail_quotes[name]=nil
      if not plan then return reply(false,error_) end
      quote_sequence=quote_sequence+1
      rail_quotes[name]={token=quote_sequence,wire=true,plan=plan}
      return reply(true,nil,{tiles=plan.ids,cost=plan.cost,token=quote_sequence,kind="wire"})
    elseif request.tool=="crossing" then
      local n=R.network
      local c,error_=R.crossing_gesture(Sim,s,first,gauge)
      if c and c.railtype and c.railtype~=0 and not R.rail.railtype_available(name,c.railtype) then
        return reply(false,"This rail type is not available to your company.")
      end
      if not c then return reply(false,error_) end
      local plan,msg=n.crossings.quote(s,name,first,c,n.lab.board(s))
      if peek then return reply(plan~=nil,msg,plan and {tiles={first},cost=plan.price}) end
      rail_quotes[name]=nil
      if not plan then return reply(false,msg) end
      quote_sequence=quote_sequence+1
      rail_quotes[name]={token=quote_sequence,plan=plan,crossing=true}
      return reply(true,nil,{tiles={first},cost=plan.price,token=quote_sequence,kind="crossing"})
    elseif request.tool=="waypoint" then
      q,why=rail.quote_waypoint(name,first,request.remove==true)
    elseif request.tool=="track" and integer(request.track,0,5) then
      q,why=rail.quote_track(name,first,last,request.track,request.remove==true,gauge)
    elseif request.tool=="depot" and integer(request.direction,0,3) then
      q,why=rail.quote_depot(name,first,request.direction,gauge)
    elseif request.tool=="station" and integer(request.axis,0,1) and
      integer(request.length,1,16) and integer(request.tracks,1,16) then
      if (math.abs(x-u)+1)*(math.abs(z-v)+1)>256 then return reply(false,"RAIL_STATION_TOO_LARGE") end
      q,why=rail.quote_station(name,first,last,{axis=request.axis,length=request.length,
        tracks=request.tracks,separate=request.separate==true,drag=request.drag==true,railtype=gauge})
    elseif request.tool=="signal" and integer(request.trackdir,0,13) and
      (request.kind==0 or request.kind==4 or request.kind==5) then
      q,why=rail.quote_signal_track(name,first,request.trackdir,request.kind,request.both==true)
    elseif request.tool=="signal_flip" and integer(request.track,0,5) then
      q,why=rail.quote_flip_signal(name,first,request.track)
    elseif request.tool=="signal_remove" and integer(request.track,0,5) then
      q,why=rail.quote_remove_signal(name,first,request.track)
    else return reply(false,"UNSUPPORTED_RAIL_GESTURE") end
    if peek then return reply(q~=nil,why,q and {tiles=q.ids,cost=q.price,kind=q.kind}) end
    rail_quotes[name]=nil
    if not q then return reply(false,why) end
    quote_sequence=quote_sequence+1
    rail_quotes[name]={token=quote_sequence,plan=q}
    return reply(true,nil,{tiles=q.ids,cost=q.price,token=quote_sequence,kind=q.kind})
  end
  local assembly_quotes={}
  function A.rail_assembly(name,depot)
    if not owner(name) or not s.companies[name] or not tile_id(depot) or not (R.rail and R.rail.assembly) then
      return reply(false,"Rail depot unavailable.")
    end
    assembly_quotes[name]=nil
    local a,why=R.rail.assembly.read(name,depot)
    if not a then return reply(false,why) end
    quote_sequence=quote_sequence+1
    local ticket={token=quote_sequence,data=a,topology=s.topology}
    assembly_quotes[name]=ticket
    local out={token=ticket.token,depot=a.depot,revision=a.revision,
      engines={},wagons={},bodies=a.bodies,destinations=a.destinations,units={}}
    for _,group in ipairs({"engines","wagons"}) do
      for i,u in ipairs(a[group]) do out[group][i]={id=u.id,name=u.name,quote={price=u.quote.price},help=u.help} end
    end
    for id,unit in pairs(a.staged) do
      out.units[id]={id=id,stocks=unit.stock_ids,passenger=R.rail.owned.passenger_consist(unit)}
    end
    return reply(true,nil,out)
  end
  local signal_quotes={}
  function A.signal_panel(name,id,hit,kind,inspect,peek)
    if not owner(name) or not s.companies[name] or not tile_id(id) or not R.rail or
      kind~=0 and kind~=4 and kind~=5 and not inspect then return reply(false,"SIGNAL_UNAVAILABLE") end
    if hit~=nil and (type(hit)~="table" or type(hit.x)~="number" or math.abs(hit.x)>2*Sim.W+5
      or type(hit.z)~="number" or math.abs(hit.z)>2*Sim.H+5 or hit.x~=hit.x or hit.z~=hit.z) then
      return reply(false,"INVALID_TRACK_POINT")
    end
    local B,Track=R.rail.build,R.network.track
    local track=B.signal_track(id,hit)
    local details=(track~=nil or inspect and not hit) and B.signal_details(id,track)
    if inspect and not details then return reply(false,"No signal on that rail piece.") end
    if details then track,kind=details.track,details.kind end
    if track==nil then return reply(false,"Aim at an owned rail piece. Avoid platforms and junctions.") end
    local choices,plans={},{}
    local function set(key,td,both,flip)
      local p,why
      if flip then p,why=B.quote_flip_signal(name,id,track)
      else p,why=B.quote_signal_track(name,id,td,kind,both) end
      choices[key]={price=p and p.price,why=why}
      if p then plans[key]={td=td,both=both,flip=flip,price=p.price} end
    end
    if details then set("flip",nil,nil,true)
    else
      set("td"..track,track)
      local other=Track.reverse_trackdir(track)
      set("td"..other,other)
      if kind==0 then set("both",track,true) end
    end
    local result={track=track,kind=kind,details=details or nil,choices=choices}
    if not peek then
      quote_sequence=quote_sequence+1
      result.token=quote_sequence
      signal_quotes[name]={token=quote_sequence,id=id,track=track,kind=kind,plans=plans,
        topology=s.topology,terrain=s.corner_grid.revision}
    end
    return reply(true,nil,result)
  end
  local transport_quotes={}
  function A.transport_quote(name,request,peek)
    if not owner(name) or not R.transport or not s.companies[name] then return reply(false,"TRANSPORT_QUOTE_UNAVAILABLE") end
    local quote,why=R.transport.quote(name,request)
    if peek then return reply(quote~=nil,why,quote and {cost=quote.price,tiles=quote.tiles,noise=quote.noise}) end
    transport_quotes[name]=nil
    if not quote then return reply(false,why) end
    quote_sequence=quote_sequence+1
    transport_quotes[name]={quote=quote,token=quote_sequence,topology=s.topology}
    return reply(true,nil,{token=quote_sequence,cost=quote.price,tiles=quote.tiles,noise=quote.noise})
  end
  local bridge_quotes={}
  function A.bridge_picker(name,mode,a,b,peek,gauge)
    if not owner(name) or not s.companies[name] or not tile_id(a) or not tile_id(b) or a==b
      or (mode~="rail" and mode~="road") or gauge~=nil and (mode~="rail" or not integer(gauge,0,3)) or not R.transport then return reply(false,"Choose two distinct bridgeheads.") end
    local offers,by_type,ids,minimum,why={},{}
    if not peek then bridge_quotes[name]=nil end
    for _,style in ipairs(styles.list(mode,gauge)) do
      local q,error_=R.transport.quote(name,{mode=mode,operation="bridge",tile=a,last=b,style=style,railtype=gauge})
      if q then
        offers[#offers+1]={style=style,name=styles.names[style],price=q.price,speed=q.speed}
        ids=ids or q.tiles
        minimum=math.min(minimum or q.price,q.price)
        by_type[style]=q
      else why=why or error_ end
    end
    if #offers==0 then return reply(false,why or "No available bridge fits this span.") end
    if peek then return reply(true,nil,{offers=offers,ids=ids,minimum=minimum,railtype=gauge}) end
    quote_sequence=quote_sequence+1
    bridge_quotes[name]={token=quote_sequence,quotes=by_type,topology=s.topology,terrain=s.corner_grid.revision}
    return reply(true,nil,{token=quote_sequence,offers=offers,ids=ids,minimum=minimum,railtype=gauge})
  end
  function A.rail_mail_station(name,id)
    if not owner(name) or not tile_id(id) then return reply(false,"INVALID_REQUEST") end
    local tile=s.tiles[id]
    local st=tile and tile.rail_station_id
    local q=st and Sim.rail_mail_stop_status(s,st)
    if not q then return reply(false,"This is not an ordinary rail platform with Mail service.") end
    return reply(true,nil,{name="Rail station #"..st,cargo={{cargo="mail",name="Mail bags",waiting=q.waiting,
      accepts=q.accepts,collects=q.waiting>0,rating=q.rating,eighths=q.eighths}}})
  end
  function A.truck_stop(name,id)
    if not owner(name) or not s.companies[name] or not tile_id(id) then return reply(false,"Truck stop unavailable.") end
    local st=s.stations[s.tiles[id].station]
    if not Sim.road_stop_has(st,"truck") or Sim.road_stop_tile_kind(st,id,s.tiles[id])~="truck" then return reply(false,"There is no truck stop on this tile.") end
    return reply(true,nil,{name=st.name,cargo=Sim.truck_stop_cargo(s,st)})
  end
  function A.depot(name,mode,id,hangar_tile)
    if not owner(name) or not R.transport then return reply(false,"DEPOT_UNAVAILABLE") end
    local data,why=R.transport.depot(name,mode,id,hangar_tile)
    return reply(data~=nil,why,data)
  end
  function A.depot_order_sources(name,mode,id,depot)
    local handle=adapter(mode,id)
    if not owner(name) or not handle or not handle.copy_sources or not tile_id(depot) then
      return reply(false,"No compatible vehicle in this depot.")
    end
    local data,why=handle.copy_sources(name,id,depot)
    return reply(data~=nil,why,data)
  end
  local terrain_quotes={}
  function A.terrain_quote(name,request,peek)
    if not owner(name) or not R.landscape or not s.companies[name] then return reply(false,"TERRAIN_QUOTE_UNAVAILABLE") end
    local quote,why=R.landscape.quote(name,request)
    if peek then return reply(quote~=nil,why,quote and {cost=quote.cost,tiles=quote.tiles,corners=quote.corners}) end
    terrain_quotes[name]=nil
    if not quote then return reply(false,why) end
    quote_sequence=quote_sequence+1
    terrain_quotes[name]={quote=quote,token=quote_sequence}
    return reply(true,nil,{token=quote_sequence,cost=quote.cost,tiles=quote.tiles,corners=quote.corners})
  end
  local demolition_quotes={}
  function A.demolition(name,id)
    if not owner(name) or not s.companies[name] or not tile_id(id) or not R.demolition then
      return reply(false,"DEMOLITION_UNAVAILABLE")
    end
    demolition_quotes[name]=nil
    local options,accepted={},{}
    for _,o in ipairs(R.demolition(name,id)) do
      options[#options+1]={key=o.key,title=o.title,ok=o.ok,detail=o.detail}
      if o.ok then accepted[o.key]=o.detail end
    end
    quote_sequence=quote_sequence+1
    if next(accepted) then
      demolition_quotes[name]={token=quote_sequence,options=accepted,id=id,
        topology=s.topology,terrain=s.corner_grid.revision}
    end
    return reply(true,nil,{token=quote_sequence,options=options})
  end
  function A.town_authority(name,id)
    if not owner(name) or not index(id) then return reply(false,"INVALID_REQUEST") end
    local company,town=s.companies[name],s.sites[id]
    if not company then return reply(false,"COMPANY_NOT_OPEN") end
    if not town or town.kind~="town" then return reply(false,"UNKNOWN_TOWN") end
    local row=Sim.road_tree_authority().company_view(s,company,town)
    row.funding=Sim.quote_town_buildings(s,name,id)
    row.reconstruction=Sim.quote_road_reconstruction(s,name,id)
    row.statue=Sim.quote_town_statue(s,name,id)
    if R.air and R.air.network and R.air.network.town_noise then
      row.airport_noise=R.air.network.town_noise(s,id)
    end
    return reply(true,nil,row)
  end
  function A.company(name)
    if not owner(name) then return reply(false,"INVALID_REQUEST") end
    local c=s.companies[name]
    if not c then return reply(false,"COMPANY_NOT_OPEN") end
    local year,month,day=Sim.date(s)
    return reply(true,nil,{cash=c.cash,loan=c.loan,revenue=c.revenue,expense=c.expense,
      month_revenue=c.month_rev,month_expense=c.month_exp,paid_units=c.paid_units,hq=Sim.company_hq_status(s,name),
      rail_maglev=R.rail and R.rail.railtype_available and R.rail.railtype_available(name,3) or false,
      rail_mono=R.rail and R.rail.railtype_available and R.rail.railtype_available(name,2) or false,
      news_head=R.news and R.news.head(),
      year=year,month=month,day_of_month=day,world_day=s.day,speed=s.speed,can_speed=s.chair==name})
  end
  function A.news(name,page,after,req)
    if not owner(name) or not s.companies[name] or not R.news then return reply(false,"Newspaper unavailable.") end
    if req and req.action=="last" then
      local function cursor(v) return integer(v,1,9007199254740991) and v or nil end
      return reply(true,nil,R.news.last(name,cursor(req.forced),cursor(req.current),req.shown==true,
        type(req.modes)=="table" and req.modes or nil))
    end
    if integer(page,1,129) and after==nil then return reply(true,nil,R.news.history(name,page,8)) end
    if page==nil and integer(after,0,9007199254740991) then
      return reply(true,nil,R.news.stream(name,after,32))
    end
    return reply(false,"Invalid newspaper request.")
  end
  function A.lesson_progress(name,lesson)
    if not owner(name) or not s.companies[name] or (lesson~="road" and lesson~="rail" and lesson~="boat") then
      return reply(false,"Lesson unavailable.")
    end
    local step,fare,warning=R.lesson(name,lesson)
    return reply(true,nil,{step=step,fare=fare,warning=warning})
  end
  function A.place_labels(name,x,z,range)
    if not owner(name) or not s.companies[name] or not integer(x,-512,2*Sim.W+512)
        or not integer(z,-512,2*Sim.H+512) or not integer(range,1,place_labels.place_radius) then
      return reply(false,"Place names unavailable.")
    end
    local function top(_,u,v)
      local _,_,y=R.terrain.tile(s.corner_grid,u,v)
      return y
    end
    return reply(true,nil,place_labels.describe(Sim,s,x,z,top,range))
  end
  function A.jump_map(name,zoom,here,focus)
    if not owner(name) or not s.companies[name] or here~=nil and not tile_id(here)
        or focus~=nil and not tile_id(focus) then
      return reply(false,"Jump map unavailable.")
    end
    return reply(true,nil,R.jump.snapshot(zoom==true,here,focus))
  end
  function A.jump_tile(name,id,x,z)
    if not owner(name) or not s.companies[name] then return reply(false,"Jump map unavailable.") end
    if not tile_id(id) then
      if not integer(x,1,Sim.W) or not integer(z,1,Sim.H) then return reply(false,"Choose a valid tile.") end
      id=Sim.id(x,z)
    end
    local t=s.tiles[id]
    if not t or t.stock_void then return reply(false,"Choose a playable tile.") end
    x,z=Sim.xy(id)
    local _,h,top=R.terrain.tile(s.corner_grid,x,z)
    h=math.max(t.h or 0,h,top)+.5
    local function height(index,book)
      local value=index and book and book[index[id]]
      if value and value.deck then h=math.max(h,value.deck+1) end
    end
    height(s.bridge_above,s.stock_road_bridges)
    height(s.rail_bridge_above,s.stock_rail_spans)
    height(s.aqueduct_above,s.stock_aqueducts)
    return reply(true,nil,{tile=id,x=2*x+.5,z=2*z+.5,y=h+8})
  end
  function A.company_fleet(name,page,mode)
    if not owner(name) or not s.companies[name] or not integer(page,1,1000000) then
      return reply(false,"COMPANY_FLEET_UNAVAILABLE")
    end
    if mode~=nil and mode~="road" and mode~="rail" and mode~="ship" and mode~="air" and mode~="tram" then
      return reply(false,"UNSUPPORTED_FLEET_FILTER")
    end
    return reply(true,nil,R.company_fleet.page(name,page,mode))
  end
  function A.vehicle(name,mode,id,locate)
    if not owner(name) or not s.companies[name] or not (index(id) or id=="ferry" or id=="coal" or id=="oil") then
      return reply(false,"VEHICLE_UNAVAILABLE")
    end
    local v=R.company_fleet.vehicle(name,mode,id)
    if not v then return reply(false,"VEHICLE_UNAVAILABLE") end
    if locate then v.position=R.company_fleet.locate(name,mode,id) end
    return reply(true,nil,v)
  end
  function A.road_quote(name,request)
    if not owner(name) or not R.road_construction then return reply(false,"ROAD_QUOTE_UNAVAILABLE") end
    if not s.companies[name] then return reply(false,"COMPANY_NOT_OPEN") end
    local quote,why=R.road_construction.quote(name,request)
    return reply(quote~=nil,why,quote)
  end
  function A.road_join_choices(name,request)
    if not owner(name) or not R.road_construction or not s.companies[name] then
      return reply(false,"ROAD_QUOTE_UNAVAILABLE")
    end
    local rows,why=R.road_construction.join_choices(name,request)
    return reply(rows~=nil,why,rows)
  end
  function A.advance(days)
    if not integer(days,0,max_days or 4) then return reply(false,"INVALID_TICK_BATCH") end
    for _=1,days do R.day() end
    return reply(true)
  end
  function A.command(name,c)
    if not owner(name) or type(c)~="table" then return reply(false,"INVALID_REQUEST") end
    if c.kind~="company_open" and c.revision~=authority_revision then return reply(false,"STALE_COMMAND") end
    local ok,note,value
    local previous_topology=s.topology
    if c.kind=="demolition" then
      local q=demolition_quotes[name]
      if not q or q.token~=c.token or type(c.layer)~="string" or not q.options[c.layer]
        or q.topology~=s.topology or q.terrain~=s.corner_grid.revision then
        return reply(false,"The tile or quote changed. Select it again.")
      end
      demolition_quotes[name]=nil
      for _,o in ipairs(R.demolition(name,q.id)) do
        if o.key==c.layer and o.ok and q.options[c.layer]==o.detail then
          local _,ids,detail=o.apply()
          if not ids then return reply(false,detail or "Layer removal canceled.") end
          value,ok,note=ids,true,type(detail)=="string" and detail or "Layer removed."
          break
        end
      end
      if not ok then return reply(false,"The tile or quote changed. Select it again.") end
    elseif c.kind=="terrain_commit" then
      local q=terrain_quotes[name]
      terrain_quotes[name]=nil
      if not q or q.token~=c.token then return reply(false,"TERRAIN_QUOTE_EXPIRED") end
      ok,note,value=R.landscape.commit(name,q.quote)
    elseif c.kind=="rail_assembly" then
      local q=assembly_quotes[name]
      if not q or q.token~=c.token or q.topology~=s.topology then return reply(false,"The depot changed. Open it again.") end
      local d=q.data
      assembly_quotes[name]=nil
      local owned=R.rail.owned
      if c.operation=="engine" or c.operation=="wagon" then
        local offered
        for _,u in ipairs(c.operation=="engine" and d.engines or d.wagons) do
          if u.id==c.stock then offered=u;break end
        end
        if not offered then return reply(false,"Unavailable stock vehicle part.") end
        local bought,why=owned.commit(s,name,offered.quote)
        if not bought then return reply(false,why) end
        ok=true
        note=bought.kind=="wagon" and ("Purchased "..offered.name..(bought.coupled_to and ". Coupled to train." or ". Stored loose."))
          or "Purchased a locomotive."
      elseif c.operation=="move" then
        local from,to
        for _,u in ipairs(d.bodies) do if u.id==c.from then from=u.id;break end end
        for _,u in ipairs(d.destinations) do if u.id==c.to then to=u.id;break end end
        if not from or c.to~=nil and not to then return reply(false,"Select a real wagon and insertion point.") end
        ok,note=owned.move_wagon(s,name,d.depot,from,to,c.tail==true,d.revision)
      else return reply(false,"Unsupported depot command.") end
    elseif c.kind=="signal_panel" then
      local q=signal_quotes[name]
      if not q or q.token~=c.token or q.topology~=s.topology or q.terrain~=s.corner_grid.revision
        or type(c.action)~="string" or not q.plans[c.action] then
        return reply(false,"The railway changed. Select the tile again.")
      end
      signal_quotes[name]=nil
      local cmd=q.plans[c.action]
      local B=R.rail.build
      local p,why
      if cmd.flip then p,why=B.quote_flip_signal(name,q.id,q.track)
      else p,why=B.quote_signal_track(name,q.id,cmd.td,q.kind,cmd.both) end
      if not p or cmd.price~=p.price then return reply(false,why or "The signal price changed.") end
      ok,note=B.build(name,p)
      if ok then value=p.ids end
    elseif c.kind=="bridge_picker" then
      local q=bridge_quotes[name]
      bridge_quotes[name]=nil
      if not q or q.token~=c.token or q.topology~=s.topology or q.terrain~=s.corner_grid.revision
        or not integer(c.style,0,12) or not q.quotes[c.style] then
        return reply(false,"The span changed. Select both bridgeheads again.")
      end
      ok,note,value=R.transport.commit(name,q.quotes[c.style])
    elseif c.kind=="transport_commit" then
      local q=transport_quotes[name]
      transport_quotes[name]=nil
      if not q or q.token~=c.token or q.topology~=s.topology then return reply(false,"TRANSPORT_QUOTE_EXPIRED") end
      ok,note,value=R.transport.commit(name,q.quote)
    elseif c.kind=="transport_start" and R.transport then
      if c.first_tile~=nil or c.second_tile~=nil then
        if c.mode~="rail" and c.mode~="ship" then return reply(false,"INVALID_DESTINATIONS") end
        for _,side in ipairs({"first","second"}) do
          local at=c[side.."_tile"]
          if at~=nil and (not tile_id(at) or
              order_target(c.mode,c.vehicle,name,at,s.tiles[at],facility_record)~=c[side]) then
            return reply(false,"DESTINATION_TILE_CHANGED")
          end
        end
      end
      ok,note=R.transport.start(name,c)
    elseif c.kind=="rail_place" and R.rail and R.rail.build and s.companies[name] then
      local req=c.request
      if type(req)~="table" or req.tool~="autotrack" or req.railtype~=nil and not integer(req.railtype,0,3)
        or c.ticket~=nil and (type(c.ticket)~="string" or #c.ticket>16384) then
        return reply(false,"INVALID_RAIL_DRAG")
      end
      local current,error_=auto_quote(R.rail.build,name,req,req.railtype)
      if not current then return reply(false,error_) end
      if #current.ids>1 and not c.ticket then
        return reply(false,"Hold on the end of the drag until the track and price appear.")
      end
      local offer=auto_offer(current,name)
      if c.ticket and c.ticket~=offer.ticket then
        return reply(false,"The rail preview changed. Check the new track and price before building.")
      end
      ok,note=R.rail.build.build(name,current)
      if ok then value={tiles=current.ids,cost=current.price} end
    elseif c.kind=="rail_commit" then
      local quote=rail_quotes[name]
      rail_quotes[name]=nil
      if not quote or quote.token~=c.token then return reply(false,"RAIL_QUOTE_EXPIRED") end
      if quote.wire then
        local cost
        ok,cost,value=R.rail.wire.commit(name,quote.plan)
        note=ok and ("Converted %d rail tile(s) for $%d."):format(#value,cost) or cost
      elseif quote.crossing then
        local n=R.network
        local cost
        ok,cost,value=n.crossings.commit(s,name,quote.plan,n.lab.board(s))
        note=ok and ("Built level crossing for $%d."):format(cost) or cost
      else
        ok,note=R.rail.build.build(name,quote.plan)
        if ok then value=quote.plan.ids end
      end
    elseif c.kind=="company_open" then
      if s.companies[name] then return A.company(name) end
      Sim.company(s,name)
      ok,note=true,"Company opened."
    elseif c.kind=="rail_freight_stage" and tile_id(c.tile) and (c.role=="load" or c.role=="unload") and
      Freight.known(c.cargo) then
      local t=s.tiles[c.tile]
      local st=s.stock_rail_stations and s.stock_rail_stations[t.rail_station_id]
      if not st or st.owner~=name then return reply(false,"Choose one of your existing rail platforms.") end
      for _,cargo in ipairs(Freight.all) do
        local role=st[cargo.."_role"]
        if role and (cargo~=c.cargo or role~=c.role) then return reply(false,"This platform already serves another freight stage.") end
      end
      if c.cargo=="coal" and st.coal_stage_tile and st.coal_stage_tile~=c.tile then
        return reply(false,"This platform already has its equipment tile.")
      end
      ok,note,value=Sim["rail_"..c.cargo.."_designate"](s,name,st.id,c.role)
      if ok and c.cargo=="coal" then
        st.coal_stage_tile,st.coal_stage_mirror=c.tile,c.mirror==true
      end
    elseif c.kind=="speed" and (c.speed==0 or c.speed==1 or c.speed==2 or c.speed==4) then
      if s.chair~=name and c.admin~=true then return reply(false,"Only the first company or a server admin can change speed.") end
      s.speed=c.speed
      ok,note=true,c.speed==0 and "Simulation paused." or ("Simulation at "..c.speed.."×.")
    elseif c.kind=="town_fund_buildings" and index(c.town) then
      ok,note,value=Sim.fund_town_buildings(s,name,c.town,c.cost)
    elseif c.kind=="town_fund_roads" and index(c.town) then
      ok,note,value=Sim.fund_road_reconstruction(s,name,c.town,c.cost)
      if ok and R.news then R.news.road_reconstruction(c.town) end
    elseif c.kind=="town_build_statue" and index(c.town) and tile_id(c.tile) then
      ok,note,value=Sim.build_town_statue(s,name,c.town,{tile=c.tile,cost=c.cost})
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
    elseif (c.kind=="road_commit" or c.kind=="road_place") and R.road_construction then
      if not s.companies[name] then return reply(false,"COMPANY_NOT_OPEN") end
      ok,note,value=R.road_construction.commit(name,c.request,c.quote,c.kind=="road_place")
    elseif c.kind=="road_build" and tile_id(c.first) and tile_id(c.last) then
      local x,z=Sim.xy(c.first)
      local u,v=Sim.xy(c.last)
      if math.abs(x-u)+math.abs(z-v)>=128 then return reply(false,"ROAD_DRAG_TOO_LONG") end
      local cells=Sim.line(c.first,c.last)
      ok,note,value=Sim.build(s,name,"road",cells)
    elseif c.kind=="depot_copy_orders" then
      local handle=adapter(c.mode,c.vehicle)
      if not handle or not handle.copy or not tile_id(c.depot) or not index(c.source)
          or type(c.source_revision)~="string" or #c.source_revision>8192
          or type(c.target_revision)~="string" or #c.target_revision>8192 then
        return reply(false,"INVALID_ORDER_COPY")
      end
      ok,note=handle.copy(name,c.vehicle,c.depot,c.source,c.source_revision,c.target_revision)
    elseif c.kind=="vehicle_order" and order_verbs[c.operation] then
      local handle=adapter(c.mode,c.vehicle)
      if not handle or not (type(c.order_revision)=="string" and #c.order_revision<=8192
        or integer(c.order_revision,0,2147483647)) then return reply(false,"INVALID_VEHICLE_ORDER") end
      local target=c.destination
      if c.tile~=nil then
        if target~=nil or not tile_id(c.tile) or (c.operation~="append" and c.operation~="replace") then
          return reply(false,"INVALID_ORDER_TILE")
        end
        target=order_target(c.mode,c.vehicle,name,c.tile,s.tiles[c.tile],facility_record)
        if not target then return reply(false,"Choose a compatible stop owned by your company.") end
      end
      if c.operation=="append" or c.operation=="replace" then
        if not destination(target) then return reply(false,"INVALID_DESTINATION") end
      elseif c.operation=="load" or c.operation=="unload" then
        if not integer(target,0,15) then return reply(false,"INVALID_CARGO_RULE") end
      end
      if c.operation~="append" and not integer(c.row,1,254) then return reply(false,"INVALID_ORDER_ROW") end
      ok,note=handle.edit(name,c.vehicle,c.order_revision,c.operation,c.row,target)
      if ok and c.tile~=nil then
        local orders=handle.read(name,c.vehicle)
        if orders then value={order_revision=orders.revision,count=#(orders.items or {})} end
      end
    elseif c.kind=="road_order_add" and index(c.vehicle) and index(c.station) then
      local v=s.fleet[c.vehicle]
      if not v or v.owner~=name or not Sim.vehicles[v.engine] or Sim.vehicles[v.engine].mode~="road" then
        return reply(false,"NOT_YOUR_ROAD_VEHICLE")
      end
      ok,note=Sim.add_order(s,name,c.vehicle,c.station)
    elseif c.kind=="ship_toggle" and R.water then
      local water=R.water
      if c.vehicle=="oil" and water.tanker then
        ok,note=water.tanker.toggle(s,name)
      elseif c.vehicle=="coal" and water.coal then
        local v=water.coal.status(s)
        if not v or v.owner~=name then return reply(false,"Choose your cargo ship.") end
        ok,note=water.coal.set_stopped(s,name,not v.stopped)
      elseif c.vehicle=="ferry" then
        local v=water.run.current(s)
        if not v or v.owner~=name then return reply(false,"Choose your active passenger vessel.") end
        ok,note=water.depot.stop(s,name,not v.stopped)
      else return reply(false,"Choose an active vessel.") end
    elseif c.kind=="road_toggle" and index(c.vehicle) then
      local v=s.fleet[c.vehicle]
      if not v or v.owner~=name or not Sim.vehicles[v.engine] or Sim.vehicles[v.engine].mode~="road" then
        return reply(false,"NOT_YOUR_ROAD_VEHICLE")
      end
      ok,note=Sim.toggle(s,name,c.vehicle)
    else return reply(false,"UNKNOWN_OR_INVALID_COMMAND") end
    if ok then
      if R.guide then R.guide.changed(c.kind=="rail_place" and value.tiles or value) end
      if R.news and previous_topology~=s.topology then R.news.topology_changed() end
      authority_revision=authority_revision+1
      s.authority_revision=authority_revision
    end
    return reply(ok,note,value)
  end
  -- Keep the validation and mutation under the same owner turn.
  function A.road_place(name,request,quote)
    return A.command(name,{kind="road_place",request=request,quote=quote,revision=authority_revision})
  end
  function A.rail_place(name,request,ticket)
    return A.command(name,{kind="rail_place",request=request,ticket=ticket,revision=authority_revision})
  end
  -- Keep an exact, bounded scene cache in the worker. Topology alone
  -- misses houses, fields, wet corners and signal changes.
  local scenes,scene_count,scene_clock={},0,0
  local function scene_key(x,z,w,h) return table.concat({x,z,w,h},":") end
  local function snapshot(x,z,w,h,fraction,frame,known)
    if not integer(x,1,Sim.W) or not integer(z,1,Sim.H)
      or not integer(w,1,32) or not integer(h,1,32) or x+w-1>Sim.W or z+h-1>Sim.H then
      return reply(false,"INVALID_INTEREST_WINDOW")
    end
    local projection=R.terrain_projection
    local corners=projection and projection.corners(R.terrain,s.corner_grid,x,z,w,h)
    local old=known and scenes[scene_key(x,z,w,h)]
    local dikes=R.canal_dikes and R.canal_dikes.mask or function() end
    local wires=R.rail_wire_mask or function() end
    local pylons=R.rail_pylon or function() end
    local unchanged=old and old.key==known and old.corners==corners and projection and projection.matches_tile
    if unchanged then
      for _,row in ipairs(old.tiles) do
        local t=s.tiles[row.id]
        local rail_diagonal,rail_canopy
        if R.rail_scene_context then rail_diagonal,rail_canopy=R.rail_scene_context(s,row.id,t) end
        if not projection.matches_tile(t,row.surface)
          or rail_diagonal~=row.rail_diagonal or rail_canopy~=row.rail_canopy or wires(s,row.id,t)~=row.rail_wire or pylons(s,row.id,t)~=row.rail_pylon
          or steps_at(row.id,t,row.slope,row.level)~=row.front_steps
          or dikes(row.id)~=row.surface.canal_dikes
          or (t.water_class=="river" and R.river_direction and R.river_direction(row.id) or nil)~=row.river_direction then
          unchanged=false
          break
        end
      end
    end

    local tiles,signals={},{}
    local signals_at=R.rail and R.rail.signals_at
    if unchanged then
      -- The acknowledged geometry produces no terrain payload unless an
      -- independently projected registry record changed. Motion, aspects,
      -- passenger counts and always-current registry observations continue.
      tiles=old.tiles
      if signals_at then for _,row in ipairs(tiles) do signals_at(row.id,signals) end end
    else
      for dz=0,h-1 do
        for dx=0,w-1 do
          local id=Sim.id(x+dx,z+dz)
          local t=s.tiles[id]
          if signals_at then signals_at(id,signals) end
          local slope,level,top=R.terrain.tile(s.corner_grid,x+dx,z+dz)
          local surface=projection and projection.tile(t) or nil
          if surface then surface.canal_dikes=dikes(id) end
          local rail_diagonal,rail_canopy
          if R.rail_scene_context then rail_diagonal,rail_canopy=R.rail_scene_context(s,id,t) end
          tiles[#tiles+1]={id=id,rail_diagonal=rail_diagonal,rail_canopy=rail_canopy,rail_wire=wires(s,id,t),rail_pylon=pylons(s,id,t),level=level,slope=slope,top=top,ground=t.terrain,build=t.build,
            rail=t.rail_tracks,road=t.road_bits,water=t.water_class,house=not not t.house,station=t.station,
            surface=surface,front_steps=steps_at(id,t,slope,level),
            river_direction=t.water_class=="river" and R.river_direction and R.river_direction(id) or nil}
        end
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
      signals=signals,passengers=R.passengers and R.passengers.counts(tiles),
      corners=corners,town_lifts=lift_snapshot(x,z,w,h),
      industry_machinery=Sim.visible_machinery and Sim.visible_machinery(s,x,z,w,h) or nil,
      registries=projection and projection.registries(s,tiles) or nil,
      actors=R.actors and R.actors(x,z,w,h,fraction,frame) or nil})
  end
  function A.snapshot(x,z,w,h,fraction,frame)
    return snapshot(x,z,w,h,fraction,frame)
  end
  local function equal(a,b)
    if a==b then return true end
    if type(a)~="table" or type(b)~="table" then return false end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
  end
  local function scene(packet,known)
    local key=scene_key(packet.x,packet.z,packet.width,packet.height)
    local old=scenes[key]
    scene_clock=scene_clock+1
    if not old or packet.corners~=old.corners
      or not equal(packet.tiles,old.tiles) or not equal(packet.registries,old.registries) then
      if not old then
        if scene_count==32 then
          local evict
          for id,entry in pairs(scenes) do
            if not evict or entry.access<scenes[evict].access then evict=id end
          end
          scenes[evict]=nil
        else
          scene_count=scene_count+1
        end
      end
      old={key=scene_clock,tiles=packet.tiles,corners=packet.corners,registries=packet.registries}
      scenes[key]=old
    end
    old.access=scene_clock
    packet.scene=old.key
    if known==old.key then
      packet.tiles,packet.corners,packet.registries=nil,nil,nil
    end
  end
  function A.snapshots(windows,fraction,players)
    if type(windows)~="table" or #windows<1 or #windows>9 then
      return reply(false,"INVALID_INTEREST_BATCH")
    end
    local packets,frame={},{road={},rail={},whole_trains=true}
    for _,w in ipairs(windows) do
      if type(w)~="table" then return reply(false,"INVALID_INTEREST_WINDOW") end
      local r=snapshot(w.x,w.z,w.w,w.h,fraction,frame,w.scene)
      if not r.ok then return r end
      scene(r.value,w.scene)
      if R.passengers then
        r.value.boardings,r.value.boarding_cursor,r.value.fares=R.passengers.events({w},w.after_boarding)
      end
      packets[#packets+1]=r.value
    end
    if #packets~=#windows then return reply(false,"INVALID_INTEREST_BATCH") end
    local r=reply(true,nil,packets)
    r.companies={}
    if type(players)=="table" and #players<=32 then
      for _,name in ipairs(players) do
        local company=A.company(name)
        if company.ok then
          local v=company.value
          v.guide=R.guide and R.guide.phase(name)
          r.companies[name]=v
        end
      end
    end
    return r
  end
  -- Cheap pose-only observations. A static 32² sector still needs its
  -- complete terrain comparison eventually, but not at the vehicle rate.
  function A.actor_frames(windows,fraction)
    if type(windows)~="table" or #windows<1 or #windows>9 then
      return reply(false,"INVALID_INTEREST_BATCH")
    end
    fraction=type(fraction)=="number" and fraction>=0 and fraction<=1 and fraction or 1
    local packets,frame={},{road={},rail={},whole_trains=true}
    for i,w in ipairs(windows) do
      if type(w)~="table" or not integer(w.x,1,Sim.W) or not integer(w.z,1,Sim.H)
        or not integer(w.w,1,32) or not integer(w.h,1,32) or w.x+w.w-1>Sim.W or w.z+w.h-1>Sim.H then
        return reply(false,"INVALID_INTEREST_WINDOW")
      end
      packets[i]={x=w.x,z=w.z,width=w.w,height=w.h,town_lifts=lift_snapshot(w.x,w.z,w.w,w.h),
        industry_machinery=Sim.visible_machinery and Sim.visible_machinery(s,w.x,w.z,w.w,w.h) or nil,
        actors=R.actors and R.actors(w.x,w.z,w.w,w.h,fraction,frame) or {}}
    end
    return reply(true,nil,packets)
  end
  return A
end
