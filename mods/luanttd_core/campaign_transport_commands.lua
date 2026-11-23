-- Worker-facing transactions call the regular railway, water and airfield
-- models. Their quotes are retained on the owner, not trusted from forms.
return function(Sim,R)
  local s=R.world
  local T={}
  local function integer(x,min,max)
    return type(x)=="number" and x>=min and x<=max and x%1==0
  end
  local function tile(x) return integer(x,1,Sim.W*Sim.H) end
  local function id(x) return integer(x,1,2147483647) end
  local function collect_tiles(q)
    local out={}
    for _,x in ipairs(q.tiles or {}) do out[#out+1]=type(x)=="table" and x.id or x end
    if #out==0 then
      if q.land then out[#out+1]=q.land end
      if q.water then out[#out+1]=q.water end
      if q.origin then out[#out+1]=q.origin end
    end
    return out
  end
  local function span_tiles(plan)
    local cells={plan.start,plan["end"]}
    for _,v in ipairs(plan.middle or {}) do cells[#cells+1]=v end
    return cells
  end
  local function spans(owner,cmd,quote)
    local op,mode=cmd.operation,cmd.mode
    if not tile(cmd.tile) or op=="bridge" and not tile(cmd.last) then return false,"INVALID_SPAN" end
    if mode=="road" then
      if op=="bridge" and not integer(cmd.style,0,2) then return false,"INVALID_BRIDGE_STYLE" end
      if op=="bridge" then return Sim.road_bridge(s,owner,cmd.tile,cmd.last,cmd.style,quote) end
      return Sim.road_tunnel(s,owner,cmd.tile,quote)
    elseif mode=="rail" and R.rail then
      local n=R.network.spans
      local p,e
      if op=="bridge" then p,e=n.quote_bridge(s,owner,cmd.tile,cmd.last)
      else p,e=n.quote_tunnel(s,owner,cmd.tile) end
      if not p then return false,e end
      if quote then return true,p.price,p end
      return n.commit(s,owner,p)
    end
    return false,"UNSUPPORTED_SPAN_MODE"
  end
  function T.quote(owner,cmd)
    if type(cmd)~="table" then return nil,"INVALID_TRANSPORT_COMMAND" end
    local mode,op=cmd.mode,cmd.operation
    if op=="bridge" or op=="tunnel" then
      local ok,price,p=spans(owner,cmd,true)
      if not ok then return nil,price end
      return {request={mode=mode,operation=op,tile=cmd.tile,last=cmd.last,style=cmd.style},
        price=price,tiles=span_tiles(p),speed=p.spec and p.spec.speed}
    elseif op=="build" and mode=="air" and R.air and tile(cmd.tile) then
      local q,why=R.air.network.quote(s,owner,cmd.tile)
      if not q then return nil,why end
      return {request={mode=mode,operation=op,tile=cmd.tile},price=q.price,tiles=collect_tiles(q)}
    elseif op=="build" and mode=="tram" and R.tram and type(cmd.cells)=="table" and
      #cmd.cells>=1 and #cmd.cells<=128 then
      local cells={}
      for i,id_ in ipairs(cmd.cells) do
        if not tile(id_) then return nil,"Invalid tram tile." end
        cells[i]=id_
      end
      local plans,cost=R.tram.net.plan(s,owner,cmd.kind,cells,cmd.direction,R.tram.busy)
      if not plans then return nil,cost end
      local ids={}
      for i,p in ipairs(plans) do ids[i]=p.id end
      return {request={mode=mode,operation=op,kind=cmd.kind,cells=cells,direction=cmd.direction},price=cost,tiles=ids}
    elseif op=="waterwork" and mode=="ship" and R.water and tile(cmd.tile) then
      local w=R.water
      if w.busy() then return nil,"An active vessel protects these waterways." end
      local q,why,ids
      if cmd.kind=="lock" then q,why=w.works.quote_lock(s,owner,cmd.tile)
      elseif cmd.kind=="canal" and tile(cmd.last) then
        local x,z=Sim.xy(cmd.tile)
        local u,v=Sim.xy(cmd.last)
        if (math.abs(x-u)+1)*(math.abs(z-v)+1)>256 then return nil,"Canal selection is too large." end
        q,why=w.works.quote(s,owner,cmd.tile,cmd.last,cmd.diagonal==true)
      elseif cmd.kind=="aqueduct" and tile(cmd.last) then
        q,why=w.aqueduct.quote(s,owner,cmd.tile,cmd.last)
        if q then ids=span_tiles(q) end
      end
      if not q then return nil,why or "Choose a valid waterway." end
      return {request={mode="ship",operation=op,kind=cmd.kind,tile=cmd.tile,last=cmd.last,diagonal=cmd.diagonal==true},
        tiles=ids or collect_tiles(q),price=q.price or q.cost}
    elseif op=="build" and mode=="ship" and R.water and tile(cmd.tile) and
      (cmd.kind=="dock" or cmd.kind=="buoy" or cmd.kind=="depot" and integer(cmd.axis,0,1)) then
      if cmd.kind~="buoy" and R.water.busy() then return nil,"An active vessel protects these waterways." end
      local q,why=R.water.network.quote(s,owner,cmd.kind,cmd.tile,cmd.axis)
      if not q then return nil,why end
      local tiles=collect_tiles(q)
      if #tiles==0 then tiles[1]=cmd.tile end
      return {request={mode=mode,operation=op,tile=cmd.tile,kind=cmd.kind,axis=cmd.axis},price=q.cost,tiles=tiles}
    elseif op=="buy" and mode=="rail" and R.rail and R.rail.owned and tile(cmd.depot)
      and type(cmd.parts)=="table" and #cmd.parts>=1 and #cmd.parts<=16 then
      local parts={}
      for i=1,#cmd.parts do
        if not integer(cmd.parts[i],0,255) then return nil,"INVALID_CONSIST" end
        parts[i]=cmd.parts[i]
      end
      local q,why=R.rail.owned.quote(s,owner,cmd.depot,parts)
      if not q then return nil,why end
      return {request={mode=mode,operation=op,depot=cmd.depot,parts=parts},price=q.price,tiles={cmd.depot}}
    elseif op=="buy" and mode=="ship" and R.water and id(cmd.depot) and (cmd.engine==206 or cmd.engine==207) then
      local q,why=R.water.depot.quote(s,owner,cmd.depot,cmd.engine)
      if not q then return nil,why end
      return {request={mode=mode,operation=op,depot=cmd.depot,engine=cmd.engine},price=q.price,tiles={}}
    elseif op=="buy" and mode=="air" and R.air and id(cmd.depot) and integer(cmd.engine,215,255) then
      local q,why=R.air.owned.quote(s,owner,cmd.depot,cmd.engine)
      if not q then return nil,why end
      return {request={mode=mode,operation=op,depot=cmd.depot,engine=cmd.engine},price=q.price,tiles={}}
    end
    return nil,"UNSUPPORTED_TRANSPORT_COMMAND"
  end
  function T.commit(owner,quote)
    local req=quote.request
    local current,why=T.quote(owner,req)
    if not current then return false,why end
    if current.price~=quote.price or #current.tiles~=#quote.tiles then return false,"TRANSPORT_QUOTE_CHANGED" end
    for i,t in ipairs(current.tiles) do if t~=quote.tiles[i] then return false,"TRANSPORT_QUOTE_CHANGED" end end
    if req.operation=="bridge" or req.operation=="tunnel" then
      local ok,msg,tiles,deck=spans(owner,req,false)
      return ok,msg,ok and {tiles=tiles,deck=deck} or nil
    end
    if req.mode=="tram" and req.operation=="build" then
      local ids,cost=R.tram.net.construct(s,owner,req.kind,req.cells,req.direction,R.tram.busy)
      if not ids then return false,cost end
      return true,("Tram construction: %d tiles for $%d."):format(#ids,cost),{tiles=ids}
    end
    if req.operation=="waterwork" then
      local w=R.water
      local p,why
      if req.kind=="lock" then p,why=w.works.build_lock(s,owner,req.tile)
      elseif req.kind=="canal" then p,why=w.works.build(s,owner,req.tile,req.last,req.diagonal)
      else p,why=w.aqueduct.build(s,owner,req.tile,req.last) end
      if not p then return false,why end
      return true,("Waterway built for $%d."):format(current.price),
        {tiles=p.dirty or current.tiles,deck=p.deck}
    end
    local unit,msg
    if req.operation=="build" and req.mode=="air" then
      unit,msg=R.air.network.build(s,owner,req.tile)
    elseif req.operation=="build" and req.mode=="ship" then
      unit,msg=R.water.network.build(s,owner,req.kind,req.tile,req.axis)
    elseif req.mode=="rail" then
      local q,e=R.rail.owned.quote(s,owner,req.depot,req.parts)
      if not q then return false,e end
      unit,msg=R.rail.owned.commit(s,owner,q)
    elseif req.mode=="ship" then
      unit,msg=R.water.depot.buy(s,owner,req.depot,req.engine)
    else
      local q,e=R.air.owned.quote(s,owner,req.depot,req.engine)
      if not q then return false,e end
      unit,msg=R.air.owned.commit(s,owner,q)
    end
    if not unit then return false,msg end
    return true,type(msg)=="string" and msg or nil,{id=unit.id or req.mode=="ship" and "ferry",tiles=current.tiles}
  end
  function T.depot(owner,mode,key)
    local offers,vehicles,targets={},{},{}
    local function add(name,cmd)
      local q=T.quote(owner,cmd)
      if q then offers[#offers+1]={name=name,price=q.price,request=q.request} end
    end
    if mode=="road" and tile(key) then
      local t=s.tiles[key]
      if t.build~="road_depot" or t.owner~=owner then return nil,"Choose a road depot you own." end
      for engine,e in pairs(Sim.vehicles) do
        if e.mode=="road" and Sim.vehicle_available(s,engine) then
          local q=Sim.vehicle_offer(s,engine)
          if q then
            for _,cargo in ipairs(Sim.cargo_order) do
              if Sim.allowed(engine,cargo) and (not q.stock_id or cargo=="passenger") then
                offers[#offers+1]={name=q.name.." · "..Sim.cargo[cargo].name,price=q.cost,
                  request={kind="road_buy",engine=engine,cargo=cargo,depot=key,cost=q.cost}}
              end
            end
          end
        end
      end
      for _,v in pairs(s.fleet) do if v.owner==owner and (v.home_depot or v.depot)==key then
        vehicles[#vehicles+1]={id=v.id,label=v.name}
      end end
    elseif mode=="rail" and R.rail and R.rail.owned and tile(key) then
      local t=s.tiles[key]
      if t.rail_depot_dir==nil or t.owner~=owner then return nil,"Choose a rail depot you own." end
      for _,row in ipairs(R.rail.owned.catalog(s)) do
        if row.passenger_model_ready then
          local id=row.stock_id
          add(row.name or tostring(id),{mode=mode,operation="buy",depot=key,parts=id==11 and {id} or {id,27}})
        end
      end
      for _,unit in ipairs(R.rail.owned.list(s,owner,key)) do
        local cargo=({[29]="coal",[30]="oil",[32]="goods"})[unit.stock_ids[2]]
        vehicles[#vehicles+1]={id=unit.id,label="Train "..unit.unit_number..
          (cargo and " · "..Sim.cargo[cargo].name or ""),cargo=cargo}
      end
    elseif mode=="ship" and R.water and id(key) then
      local t=s.stock_ship_depots and s.stock_ship_depots[key]
      if not t or t.owner~=owner then return nil,"Choose a ship depot you own." end
      for _,engine in ipairs({206,207}) do
        local model=R.water.roster.model(engine)
        add(model.name,{mode=mode,operation="buy",depot=key,engine=engine})
      end
      local ferry=s.stock_owned_ferry
      if ferry and ferry.depot==key then vehicles[1]={id="ferry",label="Passenger ferry"} end
    elseif mode=="air" and R.air and id(key) then
      local t=s.stock_small_airports and s.stock_small_airports[key]
      if not t or t.owner~=owner then return nil,"Choose an airfield you own." end
      for _,engine in ipairs(R.air.roster.catalog()) do
        add(engine.name,{mode=mode,operation="buy",depot=key,engine=engine.stock_id})
      end
      local unit=R.air.owned.status(s,key)
      if unit then vehicles[1]={id=unit.id,label=unit.name or "Aircraft"} end
    else return nil,"DEPOT_UNAVAILABLE" end
    local listing=mode=="rail" and s.stock_rail_stations or mode=="air" and s.stock_small_airports
      or mode=="ship" and s.stock_ship_stations
    for key_,r in pairs(listing or {}) do
      if r.owner==owner then
        local cell=r.origin or r.land or r.tiles and r.tiles[1]
        local x,z
        if cell then x,z=Sim.xy(cell) end
        local cargo=r.coal_role and "coal" or r.oil_role and "oil" or r.goods_role and "goods"
        targets[#targets+1]={id=key_,cargo=cargo,role=cargo and r[cargo.."_role"],label=(mode=="rail" and "Station" or mode=="air" and "Airfield" or "Dock")
          .." "..key_..(x and (" (%d, %d)"):format(x,z) or "")}
      end
    end
    table.sort(targets,function(a,b) return a.id<b.id end)
    while #targets>96 do targets[#targets]=nil end
    table.sort(offers,function(a,b) return a.name<b.name end)
    table.sort(vehicles,function(a,b) return a.id<b.id end)
    return {offers=offers,vehicles=vehicles,targets=targets}
  end
  function T.start(owner,req)
    if req.mode=="rail_pilot" and R.rail then
      local r=R.rail
      if req.clear==true then return r.build.clear_order(owner) end
      if not tile(req.depot) or not id(req.first) then return false,"Select your depot and rail destinations." end
      if req.operation=="block" then return r.build.order_block(owner,req.depot,req.first)
      elseif req.operation=="span" then return r.run.start_span(s,owner,req.depot,req.first)
      elseif req.operation=="shuttle" and id(req.second) and req.first~=req.second then
        return r.build.order(owner,req.depot,req.first,req.second)
      elseif req.operation=="station" then return r.build.order(owner,req.depot,req.first) end
      return false,"Select valid rail destinations."
    end
    if req.clear==true and req.mode=="ship" and R.water then
      local ok,why=R.water.run.clear(s,owner)
      return ok,ok and "Ferry pilot cleared." or why
    elseif req.clear==true and req.mode=="air" and R.air then
      local ok,why=R.air.run.clear(s,owner)
      return ok,ok and "Flight pilot cleared." or why
    end
    if req.mode=="tram" and R.tram and req.clear==true then
      local ok,why=R.tram.run.clear(s,owner)
      return ok,ok and "Test streetcar removed. Your tramway and stops remain." or why
    end
    if not (id(req.first) and id(req.second)) or req.first==req.second then return false,"INVALID_DESTINATIONS" end
    if req.mode=="tram" and R.tram and tile(req.depot) and tile(req.first) and tile(req.second) then
      local run,why=R.tram.run.start(s,owner,req.depot,req.first,req.second)
      return run~=nil,run and "Test streetcar dispatched between the two stops. It does not carry passengers." or why
    elseif req.mode=="rail" and R.rail and R.rail.owned and id(req.vehicle) then
      local start=R.rail.owned.start
      if req.cargo=="coal" or req.cargo=="oil" or req.cargo=="goods" then
        start=R.rail.owned["start_"..req.cargo]
      elseif req.cargo~=nil then return false,"Unsupported train cargo." end
      return start(s,owner,req.vehicle,req.first,req.second)
    elseif req.mode=="ship" and R.water and id(req.depot) and (req.via==nil or tile(req.via)) then
      local run,why=R.water.depot.start(s,owner,req.depot,req.first,req.second,req.via)
      return run~=nil,why
    elseif req.mode=="air" and R.air then
      local run,why=R.air.owned.start(s,owner,req.first,req.second)
      return run~=nil,why
    end
    return false,"UNSUPPORTED_ROUTE"
  end
  return T
end
