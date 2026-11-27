-- Worker-facing transactions call the regular railway, water and airfield
-- models. Their quotes are retained on the owner, not trusted from forms.
local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local Guide=dofile(mod.."/rail_guideway_profiles.lua")
local Roster=dofile(mod.."/openttd/rail_roster.lua")
local Help=dofile(mod.."/depot_vehicle_help.lua")
local Freight=dofile(mod.."/rail_freight_kinds.lua")
local BridgeAssets=dofile(mod.."/bridge_style_assets.lua")
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
      if op=="bridge" and not BridgeAssets.mounts("road",cmd.style) then return false,"INVALID_BRIDGE_STYLE" end
      if op=="bridge" then return Sim.road_bridge(s,owner,cmd.tile,cmd.last,cmd.style,quote) end
      return Sim.road_tunnel(s,owner,cmd.tile,quote)
    elseif mode=="rail" and R.rail then
      local n=R.network.spans
      local p,e
      if op=="bridge" and cmd.style~=nil and not BridgeAssets.mounts("rail",cmd.style,cmd.railtype) then
        return false,"INVALID_BRIDGE_STYLE"
      end
      if op=="bridge" then p,e=n.quote_bridge(s,owner,cmd.tile,cmd.last,cmd.railtype,R.rail.span_available,cmd.style)
      else p,e=n.quote_tunnel(s,owner,cmd.tile,cmd.railtype,R.rail.span_available) end
      if not p then return false,e end
      if quote then return true,p.price,p end
      return n.commit(s,owner,p,R.rail.span_available)
    end
    return false,"UNSUPPORTED_SPAN_MODE"
  end
  function T.quote(owner,cmd)
    if type(cmd)~="table" then return nil,"INVALID_TRANSPORT_COMMAND" end
    local mode,op=cmd.mode,cmd.operation
    if op=="bridge" or op=="tunnel" then
      local ok,price,p=spans(owner,cmd,true)
      if not ok then return nil,price end
      return {request={mode=mode,operation=op,tile=cmd.tile,last=cmd.last,style=cmd.style,railtype=mode=="rail" and p.railtype or nil},
        price=price,tiles=span_tiles(p),speed=p.spec and p.spec.speed}
    elseif op=="build" and mode=="air" and R.air and tile(cmd.tile) then
      local q,why,town=R.air.network.quote(s,owner,cmd.tile,cmd.layout)
      if not q then
        if why=="TOWN_REFUSES_AIRPORT_NOISE" then
          return nil,("%s will not allow this much airport noise. Try a quieter airport or build farther from town."):format(s.sites[town].name)
        elseif why=="AIRPORT_AUTHORITY_RATING" then
          return nil,"The local authority refuses new stations at your company’s current rating."
        elseif why=="TOWN_REFUSES_THIRD_AIRPORT" then
          return nil,"The town will not permit a third airport."
        end
        return nil,why
      end
      return {request={mode=mode,operation=op,tile=cmd.tile,layout=q.layout},price=q.price,tiles=collect_tiles(q),noise=q.noise}
    elseif op=="build" and mode=="tram" and R.tram and type(cmd.cells)=="table" and
      #cmd.cells>=1 and #cmd.cells<=128 then
      local cells={}
      for i,id_ in ipairs(cmd.cells) do
        if not tile(id_) then return nil,"Invalid tram tile." end
        cells[i]=id_
      end
      local plans,cost=R.tram.net.plan(s,owner,cmd.kind,cells,cmd.direction,R.tram.busy_probe and R.tram.busy_probe() or R.tram.busy)
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
      local dock
      if cmd.kind=="dock" then
        if cmd.join~=nil and (not integer(cmd.join,1,0x3fff) or cmd.adjacent~=true) then
          return nil,"INVALID_STATION_TO_JOIN"
        end
        dock={adjacent=cmd.adjacent==true,join=cmd.join}
      end
      local q,why=R.water.network.quote(s,owner,cmd.kind,cmd.tile,cmd.axis,dock)
      if not q then return nil,why end
      if cmd.picker_cost~=nil and cmd.picker_cost~=q.cost then return nil,"TRANSPORT_QUOTE_CHANGED" end
      local tiles=collect_tiles(q)
      if #tiles==0 then tiles[1]=cmd.tile end
      return {request={mode=mode,operation=op,tile=cmd.tile,kind=cmd.kind,axis=cmd.axis,
        join=dock and dock.join,adjacent=dock and dock.adjacent},price=q.cost,tiles=tiles,join=q.join}
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
    elseif mode=="ship" and R.water and R.water.coal and id(cmd.depot) and
      (op=="buy" and (cmd.engine==211 or cmd.engine==212) or op=="refit" and type(cmd.cargo)=="string") then
      local service=R.water.coal
      local q,why
      if op=="buy" then q,why=service.quote(s,owner,cmd.depot,cmd.engine)
      else q,why=service.refit_quote(s,owner,cmd.depot,cmd.cargo) end
      if not q then return nil,why end
      return {request={mode=mode,operation=op,depot=cmd.depot,engine=cmd.engine,cargo=cmd.cargo},
        price=op=="buy" and q.purchase or q.refit,tiles={}}
    elseif op=="buy" and mode=="ship" and R.water and R.water.tanker and id(cmd.depot) and (cmd.engine==204 or cmd.engine==205) then
      local q,why=R.water.tanker.quote(s,owner,cmd.depot,cmd.engine)
      if not q then return nil,why end
      return {request={mode=mode,operation=op,depot=cmd.depot,engine=cmd.engine},price=q.price,tiles={}}
    elseif op=="buy" and mode=="ship" and R.water and id(cmd.depot) and (cmd.engine==206 or cmd.engine==207 or cmd.engine==208) then
      local q,why=R.water.depot.quote(s,owner,cmd.depot,cmd.engine)
      if not q then return nil,why end
      return {request={mode=mode,operation=op,depot=cmd.depot,engine=cmd.engine},price=q.price,tiles={}}
    elseif op=="buy" and mode=="air" and R.air and id(cmd.depot) and integer(cmd.engine,215,255) then
      if cmd.hangar_tile~=nil and not tile(cmd.hangar_tile) then return nil,"SELECT_PHYSICAL_HANGAR" end
      local q,why=R.air.owned.quote(s,owner,cmd.depot,cmd.engine,cmd.hangar_tile)
      if not q then return nil,why end
      return {request={mode=mode,operation=op,depot=cmd.depot,engine=cmd.engine,hangar_tile=q.hangar_tile},price=q.price,tiles={}}
    end
    return nil,"UNSUPPORTED_TRANSPORT_COMMAND"
  end
  function T.commit(owner,quote)
    local req=quote.request
    local current,why=T.quote(owner,req)
    if not current then return false,why end
    if current.price~=quote.price or current.join~=quote.join or #current.tiles~=#quote.tiles then return false,"TRANSPORT_QUOTE_CHANGED" end
    for i,t in ipairs(current.tiles) do if t~=quote.tiles[i] then return false,"TRANSPORT_QUOTE_CHANGED" end end
    if req.operation=="bridge" or req.operation=="tunnel" then
      local ok,msg,tiles,deck=spans(owner,req,false)
      return ok,msg,ok and {tiles=tiles,deck=deck} or nil
    end
    if req.mode=="tram" and req.operation=="build" then
      local ids,cost=R.tram.net.construct(s,owner,req.kind,req.cells,req.direction,R.tram.busy_probe and R.tram.busy_probe() or R.tram.busy)
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
      unit,msg=R.air.network.build(s,owner,req.tile,req.layout)
    elseif req.operation=="build" and req.mode=="ship" then
      unit,msg=R.water.network.build(s,owner,req.kind,req.tile,req.axis,req.kind=="dock" and req or nil)
    elseif req.mode=="rail" then
      local q,e=R.rail.owned.quote(s,owner,req.depot,req.parts)
      if not q then return false,e end
      unit,msg=R.rail.owned.commit(s,owner,q)
    elseif req.mode=="ship" then
      if req.operation=="refit" then
        unit,msg=R.water.coal.refit(s,owner,req.depot,req.cargo)
      elseif req.engine==211 or req.engine==212 then
        unit,msg=R.water.coal.buy(s,owner,req.depot,req.engine)
      else
        local depot_model=(req.engine==204 or req.engine==205) and R.water.tanker or R.water.depot
        unit,msg=depot_model.buy(s,owner,req.depot,req.engine)
      end
    else
      local q,e=R.air.owned.quote(s,owner,req.depot,req.engine,req.hangar_tile)
      if not q then return false,e end
      unit,msg=R.air.owned.commit(s,owner,q)
    end
    if not unit then return false,msg end
    return true,type(msg)=="string" and msg or nil,{id=unit.id or req.mode=="ship" and "ferry",tiles=current.tiles}
  end
  function T.dock_join_choices(owner,cmd)
    if not R.water or type(cmd)~="table" or not tile(cmd.tile) then return nil,"INVALID_TILE" end
    return R.water.network.join_choices(s,owner,cmd.tile)
  end
  function T.depot(owner,mode,key,hangar_tile)
    local offers,vehicles,targets={},{},{}
    local airframe,hangar_label
    local function add(name,cmd,help)
      local q=T.quote(owner,cmd)
      if q then offers[#offers+1]={name=name,price=q.price,request=q.request,help=help} end
    end
    local function road_help(engine,cargo,q)
      q=q or Sim.vehicle_offer(s,engine) or Sim.vehicles[engine] or {}
      return Help.describe("road",cargo,q.name,{capacity=q.capacity,speed=q.display_speed or
        (q.source_speed and math.floor(q.source_speed/2))})
    end
    local function ship_help(model,cargo,refit,needs_refit)
      model=model or {}
      return Help.describe("ship",cargo,model.name,{capacity=model.capacity,
        capacity_unit=cargo=="oil" and "kL" or cargo=="coal" and "t of coal" or cargo=="goods" and "crates" or cargo=="grain" and "t of grain" or cargo=="livestock" and "animals",
        speed=model.max_speed and model.max_speed/2},nil,refit,needs_refit)
    end
    local function air_help(entry)
      entry=entry or {}
      return Help.describe("air",entry.mail and entry.mail>0 and "mixed" or nil,entry.name,{capacity=entry.passengers,
        capacity_unit="seats",mail_capacity=entry.mail,speed=entry.max_speed,
        runway=entry.helicopter and "Can serve Heliports and Oil Rigs; buy at your airport" or entry.jet and "Requires a long runway"})
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
                offers[#offers+1]={name=q.name.." · "..Sim.cargo[cargo].name,price=q.cost,help=road_help(engine,cargo,q),
                  request={kind="road_buy",engine=engine,cargo=cargo,depot=key,cost=q.cost}}
              end
            end
          end
        end
      end
      for _,v in pairs(s.fleet) do if v.owner==owner and (v.home_depot or v.depot)==key then
        vehicles[#vehicles+1]={id=v.id,label=v.name,help=road_help(v.engine,v.cargo)}
      end end
    elseif mode=="rail" and R.rail and R.rail.owned and tile(key) then
      local t=s.tiles[key]
      if t.rail_depot_dir==nil or t.owner~=owner then return nil,"Choose a rail depot you own." end
      local catalogue={}
      for _,row in ipairs(R.rail.owned.catalog(s)) do
        catalogue[row.stock_id]=row
        if row.passenger_model_ready then
          local id=row.stock_id
          local dmu=Roster.passenger_dmu(id)
          local capacity=dmu and row.capacity*2 or 40
          local parcel=id==22 and s.rail_mail_service and 2*row.capacity or nil
          add(row.name or tostring(id),{mode=mode,operation="buy",depot=key,parts=dmu and {id} or {id,27}},
            Help.describe("rail","passenger",row.name,{speed=row.speed,capacity=capacity,mail_capacity=parcel},dmu and "dmu" or nil))
          if dmu then
            add(row.name.." + Passenger Carriage",{mode=mode,operation="buy",depot=key,parts={id,27}},
              Help.describe("rail","passenger",row.name.." + Passenger Carriage",{speed=row.speed,capacity=capacity+40},"dmu"))
          end
        end
      end
      local profile=Guide.by_gauge[t.rail_type]
      if profile then
        local engine,coach,mail=catalogue[profile.engine],catalogue[profile.passenger],catalogue[profile.mail]
        if engine and coach and mail then
          local title=engine.name:gsub("^'(.*)'$","%1")
          local combo=title.." + Passenger Carriage + Mail Van"
          add(title.." · Coach and Mail",{mode=mode,operation="buy",depot=key,parts=profile.stocks},
            Help.describe("rail","mixed",combo,{speed=engine.speed,capacity=coach.capacity,mail_capacity=mail.capacity}))
        end
        local oil=catalogue[profile.oil]
        if engine and oil and s.rail_oil_service then
          local title=engine.name:gsub("^'(.*)'$","%1")
          add(title.." · Oil Tanker",{mode=mode,operation="buy",depot=key,parts={engine.stock_id,oil.stock_id}},
            Help.describe("rail","oil",oil.name,{speed=engine.speed,capacity=oil.capacity}))
        end
      end
      local depot_cargos={"mail"}
      for _,cargo in ipairs(Freight.profile_order) do depot_cargos[#depot_cargos+1]=cargo end
      for _,cargo in ipairs(depot_cargos) do
        local wagon=cargo=="mail" and 28 or Freight.profiles[cargo].wagon
        local car=catalogue[wagon]
        if car then
          for _,stock in ipairs({0,8,9,10,13,14,15,23,24}) do
            local engine=catalogue[stock]
            if engine and engine.passenger_model_ready then
              local cmd={mode=mode,operation="buy",depot=key,parts={stock,wagon}}
              local q=T.quote(owner,cmd)
              if q then
                offers[#offers+1]={name=engine.name.." + "..car.name,price=q.price,request=q.request,
                  help=Help.describe(mode,cargo,car.name,{capacity=car.capacity,speed=engine.speed})}
                local f=Freight.profiles[cargo]
                if f and f.max_wagons==2 then
                  local pair={mode=mode,operation="buy",depot=key,parts={stock,wagon,wagon}}
                  local together=T.quote(owner,pair)
                  if together then
                    offers[#offers+1]={name=engine.name.." + 2 "..car.name.."s",price=together.price,request=together.request,
                      help=Help.describe(mode,cargo,"2 "..car.name.."s",{capacity=2*car.capacity,speed=engine.speed})}
                  end
                end
                break
              end
            end
          end
        end
      end
      if s.rail_mixed_town_service then
        local cmd={mode=mode,operation="buy",depot=key,parts={0,27,28}}
        local q=T.quote(owner,cmd)
        if q then
          offers[#offers+1]={name="Kirby + Passenger Carriage + Mail Van",price=q.price,request=q.request,
            help=Help.describe(mode,"mixed","Coach and Mail train")}
        end
      end
      for _,unit in ipairs(R.rail.owned.list(s,owner,key)) do
        local mixed=R.rail.owned.mixed_consist and R.rail.owned.mixed_consist(s,unit)
        local cargo=mixed and "mixed" or unit.stock_ids[2]==28 and "mail" or Freight.wagons[unit.stock_ids[2]]
        local engine=catalogue[unit.stock_ids[1]] or {}
        local profile=Freight.profiles[cargo]
        local unsupported=profile and R.rail.owned.profile_consist and not R.rail.owned.profile_consist(s,unit,cargo)
        local car=cargo and catalogue[unit.stock_ids[2]]
        local wagon_count=not unsupported and #unit.stock_ids-1 or nil
        local dmu=Roster.passenger_dmu(unit.stock_ids[1])
        local part=dmu and "dmu" or #unit.stock_ids==1 and "engine" or nil
        local seats=dmu and (2*Roster.entry(unit.stock_ids[1]).capacity+(unit.stock_ids[2]==27 and 40 or 0)) or nil
        vehicles[#vehicles+1]={id=unit.id,unit_number=unit.unit_number,parked=unit.status=="depot",
          wagon_count=wagon_count,label="Train "..unit.unit_number..
          (cargo and " · "..(cargo=="mixed" and "Coach and Mail" or Sim.cargo[cargo].name) or "")..
          (wagon_count and wagon_count>0 and (" · "..wagon_count..(wagon_count==1 and " wagon" or " wagons")) or ""),cargo=cargo,unsupported=unsupported or nil,
          order_copy=unit.status=="depot" and (not cargo and R.rail.owned.passenger_consist(unit) or cargo=="mixed" or cargo=="mail") or nil,
          draft_orders=R.rail.owned.can_edit_draft and R.rail.owned.can_edit_draft(s,owner,unit.id,key) or nil,
          copied=unit.order_draft and #unit.order_draft.orders,
          draft_revision=unit.order_draft and "rail-parked:"..unit.order_draft.revision,
          help=Help.describe("rail",cargo or Help.rail_cargo(unit.stock_ids[2]),engine.name,
            {speed=engine.speed,capacity=car and wagon_count and not mixed and car.capacity*wagon_count or seats,
              mail_capacity=unit.stock_ids[1]==22 and #unit.stock_ids==2 and unit.stock_ids[2]==27 and s.rail_mail_service and 8 or nil},part)}
      end
    elseif mode=="ship" and R.water and id(key) then
      local t=s.stock_ship_depots and s.stock_ship_depots[key]
      if not t or t.owner~=owner then return nil,"Choose a ship depot you own." end
      for _,engine in ipairs(R.water.roster.order or {206,207}) do
        local model=R.water.roster.model(engine)
        add(model.name,{mode=mode,operation="buy",depot=key,engine=engine},ship_help(model))
      end
      if R.water.coal then
        local C=R.water.coal
        for _,engine in ipairs(C.catalog) do
          local model=C.model(engine)
          add(model.name,{mode=mode,operation="buy",depot=key,engine=engine},ship_help(model,"goods",false,not C.goods(s)))
        end
        local c=C.status(s)
        if c and c.depot==key and c.owner==owner then
          local model=C.model(c.engine) or {name=c.name}
          local cargo=C.cargo_key(s)
          vehicles[#vehicles+1]={id="coal",label=c.name,cargo=cargo,parked=c.phase=="purchased",
            help=ship_help(model,cargo,false,cargo=="goods" and not C.goods(s))}
          for _,choice in ipairs(C.refit_choices(s)) do
            if c.cargo~=choice.id then
              add("Refit "..c.name.." to "..choice.name,{mode=mode,operation="refit",depot=key,cargo=choice.cargo},
                ship_help(model,choice.cargo,choice.cargo=="coal"))
            end
          end
        end
      end
      if R.water.tanker then
        local stock=R.water.tanker
        for _,engine in ipairs(stock.catalog) do
          local model=stock.model(engine)
          add(model.name,{mode=mode,operation="buy",depot=key,engine=engine},ship_help(model,"oil"))
        end
        local t=R.water.tanker.status(s)
        if t and t.depot==key and t.owner==owner then
          vehicles[#vehicles+1]={id=t.id,label=t.name,cargo="oil",
            help=ship_help(stock.model(t.engine) or {name=t.name},"oil")}
        end
      end
      local ferry=s.stock_owned_ferry
      if ferry and ferry.depot==key then
        local model=R.water.roster.model(ferry.engine_id) or {name="Passenger ferry"}
        vehicles[#vehicles+1]={id="ferry",label=model.name,help=ship_help(model)}
      end
    elseif mode=="air" and R.air and id(key) then
      local t=s.stock_small_airports and s.stock_small_airports[key]
      if not t or t.owner~=owner then return nil,"Choose an airfield you own." end
      if t.layout=="heliport" then return nil,"This Heliport does not have a hangar." end
      if hangar_tile~=nil and not tile(hangar_tile) then return nil,"Aim at one of the airport’s hangar buildings." end
      local index,why=R.air.owned.hangar(s,owner,key,hangar_tile)
      if index==nil then return nil,why=="SELECT_PHYSICAL_HANGAR" and "Aim at one of the airport’s hangar buildings." or why end
      if t.layout=="international" or t.layout=="intercontinental" then
        hangar_label=("Airport #%d · Hangar %d"):format(key,index+1)
      end
      for _,engine in ipairs(R.air.roster.catalog(true)) do
        add(engine.name,{mode=mode,operation="buy",depot=key,engine=engine.stock_id,hangar_tile=hangar_tile},air_help(engine))
      end
      local unit=R.air.owned.status(s,key,index)
      if unit then
        airframe=unit.stock_id
        local d=R.air.roster.entry(unit.stock_id)
        vehicles[1]={id=unit.id,label=d and d.name or "Aircraft",help=air_help(d)}
      end
    else return nil,"DEPOT_UNAVAILABLE" end
    local listing=mode=="rail" and s.stock_rail_stations or mode=="air" and s.stock_small_airports
      or mode=="ship" and s.stock_ship_stations
    for key_,r in pairs(listing or {}) do
      local rig=(mode=="ship" or mode=="air" and airframe) and r.oil_rig and r.neutral and r.owner==nil and
        (s.stock_neutral_stations or {})[key_]
      if (r.owner==owner or rig) and (not airframe or not R.air.run.fits or R.air.run.fits(r,airframe)) then
        local cell=r.origin or r.land or r.tiles and r.tiles[1]
        local x,z
        if cell then x,z=Sim.xy(cell) end
        local cargo=Freight.role(r)
        targets[#targets+1]={id=key_,cargo=cargo,role=cargo and r[cargo.."_role"],label=(rig and rig.name or mode=="rail" and "Station" or mode=="air" and (r.layout=="city" and "City Airport" or r.layout=="international" and "International Airport" or r.layout=="intercontinental" and "Intercontinental Airport" or r.layout=="commuter" and "Commuter Airport" or r.layout=="metropolitan" and "Metropolitan Airport" or r.layout=="heliport" and "Heliport" or r.layout=="helidepot" and "Helidepot" or r.layout=="helistation" and "Helistation" or "Airfield") or "Dock")
          .." "..key_..(x and (" (%d, %d)"):format(x,z) or "")}
        if mode=="ship" and R.water.coal then
          local C=R.water.coal
          local report=C.order_report(s,key_,"coal")
          if report then
            if #report.sources>0 then targets[#targets+1]={id=key_,cargo="coal",role="load",label="Coal mine dock "..key_} end
            if report.accepts then targets[#targets+1]={id=key_,cargo="coal",role="unload",label="Power plant dock "..key_} end
          end
          local cargo=C.cargo_key(s)
          local profile=cargo~="coal" and C.cargo_profile(s,cargo)
          if profile then
            local dry=C.order_report(s,key_,cargo)
            if dry then
              if #dry.sources>0 then targets[#targets+1]={id=key_,cargo=cargo,role="load",label=profile.load.." dock "..key_} end
              if dry.accepts then targets[#targets+1]={id=key_,cargo=cargo,role="unload",label=profile.unload.." dock "..key_} end
            end
          end
        end
        if mode=="ship" and R.water.tanker then
          local report=R.water.tanker.report(s,key_)
          if report then
            if #report.sources>0 then targets[#targets+1]={id=key_,cargo="oil",role="load",label=rig and rig.name or "Oil source dock "..key_} end
            if report.accepts then targets[#targets+1]={id=key_,cargo="oil",role="unload",label="Refinery dock "..key_} end
          end
        end
      end
    end
    table.sort(targets,function(a,b) return a.id<b.id end)
    while #targets>96 do targets[#targets]=nil end
    table.sort(offers,function(a,b) return a.name<b.name end)
    table.sort(vehicles,function(a,b) return a.id<b.id end)
    return {offers=offers,vehicles=vehicles,targets=targets,hangar_label=hangar_label,railtype=mode=="rail" and s.tiles[key].rail_type or nil}
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
      local run=R.tram.run
      local active,serial
      if req.vehicle~=nil then
        if not id(req.vehicle) or type(req.retirement)~="string" or #req.retirement>32 then
          return false,"Choose a streetcar from your fleet."
        end
        active=run.by_ui(s,req.vehicle)
        if not active or active.owner~=owner or run.retirement_key(active)~=req.retirement then
          return false,"This streetcar changed. Review your roster again."
        end
        serial=run.serial(active)
      else
        local all=run.all(s)
        if #all~=1 then return false,"Choose a streetcar from your fleet." end
        active=all[1];serial=run.serial(active)
      end
      local ok,why=run.clear(s,owner,serial)
      local note=active and active.carrier and "Streetcar retired. Your tramway and stops remain."
        or "Test streetcar removed. Your tramway and stops remain."
      return ok,ok and note or why
    end
    if req.mode=="rail" and (req.copied==true or req.start_draft==true) and R.rail and R.rail.owned and id(req.vehicle) and tile(req.depot) then
      if type(req.draft_revision)~="string" or #req.draft_revision>32 then return false,"Invalid order list." end
      return R.rail.owned.start_copied_orders(s,owner,req.vehicle,req.depot,req.draft_revision)
    end
    if not (id(req.first) and id(req.second)) or req.first==req.second then return false,"INVALID_DESTINATIONS" end
    if req.mode=="tram" and R.tram and tile(req.depot) and tile(req.first) and tile(req.second) then
      if req.paid==true then
        local run,why=R.tram.run.start_paid(s,owner,req.depot,req.first,req.second,req.cost,
          R.tram.run.current(s)~=nil)
        return run~=nil,run and "Streetcar bought and dispatched to both platforms." or why
      end
      local run,why=R.tram.run.start(s,owner,req.depot,req.first,req.second)
      return run~=nil,run and "Test streetcar dispatched between the two stops. It does not carry passengers." or why
    elseif req.mode=="rail" and R.rail and R.rail.owned and id(req.vehicle) then
      local start=R.rail.owned.start
      if req.cargo=="mixed" or req.cargo=="mail" or Freight.known(req.cargo) then
        start=R.rail.owned["start_"..req.cargo]
      elseif req.cargo~=nil then return false,"Unsupported train cargo." end
      return start(s,owner,req.vehicle,req.first,req.second)
    elseif req.mode=="ship" and R.water and id(req.depot) and (req.via==nil or tile(req.via)) then
      if req.cargo=="oil" and req.vehicle=="oil" and R.water.tanker then
        local run,why=R.water.tanker.start(s,owner,req.depot,req.first,req.second)
        return run~=nil,why
      end
      if type(req.cargo)=="string" and req.vehicle=="coal" and R.water.coal then
        local c=R.water.coal.status(s)
        if not c or c.depot~=req.depot then return false,"Choose the depot that owns this cargo ship." end
        if R.water.coal.cargo_key(s)~=req.cargo then return false,"The ship's cargo changed. Refresh its depot." end
        local run,why=R.water.coal.start(s,owner,req.first,req.second)
        return run~=nil,why
      end
      if req.cargo~=nil then return false,"UNSUPPORTED_SHIP_CARGO" end
      local run,why=R.water.depot.start(s,owner,req.depot,req.first,req.second,req.via)
      return run~=nil,why
    elseif req.mode=="air" and R.air then
      if req.vehicle~=nil and not id(req.vehicle) then return false,"Choose an aircraft you own." end
      local run,why=R.air.owned.start(s,owner,req.first,req.second,req.vehicle)
      return run~=nil,why
    end
    return false,"UNSUPPORTED_ROUTE"
  end
  return T
end
