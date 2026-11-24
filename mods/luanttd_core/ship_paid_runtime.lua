-- SPDX-License-Identifier: GPL-2.0-only
-- Paid stock water/rail/air controllers share the house event mux and one
-- station clock. The original paid-ferry save key remains stable.
return function(Sim,Service,Mux,credit,news,RailActors,Mail,Catchment,MailRandom)
  local F={}
  local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
  local Roster=dofile(mod.."/openttd/rail_roster.lua")
  local Freight=dofile(mod.."/rail_freight_kinds.lua")
  local Rig=dofile(mod.."/openttd/oil_rig.lua")
  local CargoOrder=dofile(mod.."/openttd/rail_order_cargo.lua")
  local views=setmetatable({},{__mode="k"})
  local floor=math.floor
  local function commercial(s)
    local c=s.stock_ship_commercial
    if not c then
      c={version=1,service=Service.new(s.seed)}
      s.stock_ship_commercial=c
    end
    assert(c.version==1 and c.service.version==Service.version,"Unsupported commercial transport save")
    return c
  end

  local function enabled(s,m)
    return s.road_stock_house_supply and s.corner_grid~=nil and s[m.."_paid_service"]
  end
  local function air_gather(Air,s)
    if not Air then return {} end
    local found=Air.gather and Air.gather(s) or {Air.current(s)}
    local out={}
    for _,p in ipairs(found) do
      if p.paid_clock~=nil then
        assert(type(p.paid_clock)=="number" and p.paid_clock%1==0 and p.paid_clock>=0 and p.paid_clock<0x3FFE,
          "Airport vehicle ID has exhausted its paid range")
        out[#out+1]=p
      end
    end
    table.sort(out,function(a,b) return a.paid_clock<b.paid_clock end)
    for i=2,#out do assert(out[i-1].paid_clock~=out[i].paid_clock,"Duplicate paid air actor") end
    return out
  end
  local function air_current(Air,s,serial)
    if not Air then return end
    if serial==nil then return Air.current(s) end
    for _,p in ipairs(air_gather(Air,s)) do if p.paid_clock==serial then return p end end
  end
  function F.active(s,Ship,Rail,Air)
    local c=s.stock_ship_commercial
    local p=Ship and Ship.current(s)
    return not not (
      Ship and enabled(s,"ship") and (
        (p and p.paid_clock~=nil) or (c and c.active_serial~=nil)
        or (s.stock_ship_stations and next(s.stock_ship_stations))) or
      Rail and enabled(s,"rail") and (
        Rail.current_paid(s) or (c and c.rail_serial~=nil)
        or (s.stock_rail_stations and next(s.stock_rail_stations))) or
      Air and enabled(s,"air") and (
        #air_gather(Air,s)>0 or (c and (c.air_serial~=nil or next(c.air_serials or {})))
        or (s.stock_small_airports and next(s.stock_small_airports))))
  end

  local function view(s)
    local f=views[s]
    if not f then f={events={},rail_motion={},air_motion={}};views[s]=f end
    return f
  end
  local function rail_key(id)
    assert(id<0x4000,"Rail station or vehicle ID has exhausted its pilot range")
    return 0x4000+id
  end
  local Actors=RailActors(Service,rail_key)
  local function ship_index(id)
    assert(id<0x4000,"Dock station ID has exhausted its pilot range")
    return 0x8000+id
  end
  local function air_key(id)
    assert(id<0x3FFE,"Airport station or vehicle ID has exhausted its pilot range")
    return 0xC000+id
  end
  local function mode(st) return st.host_mode or "ship" end
  local function at(mode_,tile)
    local x,z=Sim.xy(tile)
    return {x=x-1,y=z-1,kind=mode_}
  end
  local function context(s,active)
    local function house_at(x,z)
      local id=Sim.id(x+1,z+1)
      local tile=id and s.tiles[id]
      if tile and tile.house then return tile.source_house end
      local hq=id and Sim.hq_cargo_at and Sim.hq_cargo_at(s,id)
      if hq then return {hq_acceptance={passenger=Sim.hq_acceptance(hq,"passenger"),mail=Sim.hq_acceptance(hq,"mail")}} end
    end
    local ctx={width=Sim.W,height=Sim.H,xy=Sim.xy,house_at=house_at,
      gradual=s.stock_gradual_loading~=false,feeder_percent=s.stock_feeder_percent,
      select_goods=s.stock_select_goods,
      statue=Sim.station_has_town_statue and function(st) return Sim.station_has_town_statue(s,st) end,
      modified=s.stock_modified_catchment,
      neutral_owner=false,serve_neutral=s.stock_serve_neutral_industries~=false,
      mail_random_u32=MailRandom and function() return MailRandom(s) end,
      year=function() return Sim.date(s) end,
      station_active=function(st) return active[mode(st)] end,
      vehicle_active=function(v) return active[v.mode] end,
      -- The transport pilot catalogs historically had private IDs. Give
      -- each a noncolliding stable global order for fixed-point tie breaks
      -- and acceptance scheduling while retaining the raw ferry save ID.
      station_id=function(kind,st)
        if kind=="road" or mode(st)~="ship" then return st.id end
        return ship_index(st.id)
      end}
    ctx.industry_acceptance=function(st,cargo,c)
      if not Catchment then return 0 end
      local out=0
      for _,ind in pairs(s.stock_oil_industries or {}) do
        if ind.kind=="oil_rig" and not ind.removed and
            (ctx.serve_neutral or st.neutral_rig==ind.id or ind.neutral_station==nil and st.neutral_rig==nil) then
          for _,tile in ipairs(ind.tiles) do
            if tile.completed and not tile.neutral_platform and Catchment.contains(c,tile.x,tile.z) then
              out=out+Rig.acceptance(tile.gfx,cargo)
            end
          end
        end
      end
      return out
    end
    ctx.production=function(service,tick) Mux.consume(s,service,tick,ctx) end
    return ctx
  end

  local function flash(s,c,events,withdrawn_owner)
    if #events==0 then return end
    local frame=view(s)
    for _,e in ipairs(events) do
      e.day=s.day
      local v=c.service.vehicles[e.vehicle]
      local owner=withdrawn_owner or assert(v and v.owner,"Missing owner for commercial event")
      e.owner=owner
      if e.mode=="air" then e.paid_clock=e.vehicle-0xC000 end
      local sink=c.service.stations[e.station]
      e.station_local=sink and (sink.host_id or sink.id)
      if e.kind=="fare" then
        if Sim.stock_vehicle_operating and v then
          local asset
          if e.mode=="rail" and v.finance_asset_id then
            asset=s.stock_rail_fleet and s.stock_rail_fleet.units[v.finance_asset_id]
          elseif e.mode=="ship" then asset=s.stock_owned_ferry
          elseif e.mode=="air" then asset=s.stock_owned_air_fleet and s.stock_owned_air_fleet[e.paid_clock] or s.stock_owned_aircraft end
          Sim.stock_vehicle_operating(s,asset,e.amount)
        end
        local company=Sim.company(s,owner)
        credit(company,e.amount)
        if company.paid_units==0 and news then
          local line=e.mode=="rail" and "rail" or e.mode=="air" and "air" or "ferry"
          local cargo=e.cargo=="mixed" and " passengers and mail bags" or e.cargo=="mail" and " mail bags" or " passengers"
          news(s,owner.." made their first paid delivery: "..e.units..
            " "..line..cargo.." for $"..e.amount..".")
        end
        company.units=company.units+e.units
        company.paid_units=company.paid_units+e.units
      elseif e.kind=="deliver" then
        if Sim.stock_economy_delivered then Sim.stock_economy_delivered(Sim.company(s,owner),e.cargo or "passenger",e.units) end
        local town=sink and s.sites[sink.town]
        if town then
          local cargo=e.cargo or "passenger"
          town.received[cargo]=(town.received[cargo] or 0)+e.units
          if cargo=="passenger" then town.service=(town.service or 0)+e.units end
        end
      end
      frame.events[#frame.events+1]=e
    end
    while #frame.events>4096 do table.remove(frame.events,1) end
  end

  local function reconcile_air(s,c,Air,aircraft,ctx,tick)
    local service=c.service
    local saved=c.air_serials
    if not saved then saved=c.air_serial and {[c.air_serial]=true} or {} end
    local live={}
    for _,p in ipairs(aircraft) do live[air_key(p.paid_clock)]=p end
    local stale={}
    for id in pairs(saved) do if not live[id] then stale[#stale+1]=id end end
    table.sort(stale)
    for _,id in ipairs(stale) do
      local old=assert(service.vehicles[id],"Missing saved commercial aircraft")
      local events={}
      assert(Service.withdraw_vehicle(service,id,tick,ctx,events))
      flash(s,c,events,old.owner)
    end
    local serials={}
    for _,p in ipairs(aircraft) do
      local id=air_key(p.paid_clock)
      local model=Air.engine_for and Air.engine_for(p) or Air.engine
      local mail=p.engine_id and model and model.mail and model.mail>0 and
        (not Air.paid_art_ready or Air.paid_art_ready(p))
      if not saved[id] then
        Service.vehicle(service,{id=id,mode="air",owner=p.owner,engine=p.engine_id,
          speed=assert(model,"Unknown stock aircraft").max_speed,built=p.paid_build_year or Sim.date(s,p.paid_built_day or s.day),
          air_mail=mail})
      else
        local v=service.vehicles[id]
        assert(v and v.mode=="air" and v.owner==p.owner and (v.engine or 215)==(p.engine_id or 215),
          "Saved aircraft and its commercial cargo row disagree")
        if mail then Service.mount_air_mail(v) end
      end
      serials[id]=true
    end
    c.air_serials=serials
    local primary=Air.current(s)
    c.air_serial=primary and primary.paid_clock and air_key(primary.paid_clock) or nil
  end

  local function sync_stations(s,c,ctx,active)
    local ships=s.stock_ship_stations or {}
    local rails=s.stock_rail_stations or {}
    local airports=s.stock_small_airports or {}
    local service=c.service
    -- Both sets use physical footprints. Ships contribute exactly their
    -- two dock tiles; trains contribute every true platform tile, never a
    -- depot, a sign outside the platform or the occupied carriage tile.
    local function sync(id,local_id,actual,tiles,mode_,ref,base,id_for_tick)
      local st=service.stations[id]
      local neutral=Rig.neutral_ref(s,actual)
      local owner=actual.owner
      if neutral then owner=false end
      local mail=mode_=="air" or mode_=="rail" and s.rail_mail_service==true and not Freight.role(actual)
      local fresh=not st or not not st.mail_enabled~=mail
      if st then
        assert(st.owner==owner and mode(st)==mode_,"Commercial station ownership changed")
        st.tick_index=id_for_tick
        if st.footprint_rev~=ref then Service.footprint(service,id,tiles,ctx) end
      else
        local town=Sim.nearest_town(s,base)
        st=Service.station(service,{id=id,owner=owner,town=town and town.id,neutral_rig=neutral and neutral.industry,
          tick_index=id_for_tick,tiles=tiles},ctx)
      end
      st.host_mode,st.host_id,st.footprint_rev=mode_,local_id,ref
      st.mail_enabled=mail or nil
      if mail and fresh then Service.refresh_mail_acceptance(service,id,ctx) end
      if not st.sign then local x,y=Sim.xy(base);st.sign={x=x,y=y} end
      if mode_=="ship" then st.land,st.water=actual.land,actual.water end
    end
    if active.ship then
      for id,p in pairs(ships) do
        if not p.neutral then sync(id,id,p,{at("dock",p.land),at("dock",p.water)},"ship",p.land..":"..p.water,p.land,ship_index(id)) end
      end
    end
    if active.rail then
      for id,p in pairs(rails) do
        local valid,tiles={},{}
        for _,tile in ipairs(p.tiles) do
          local map_tile=s.tiles[tile]
          if map_tile and map_tile.rail_station_id==id and map_tile.owner==p.owner then
            tiles[#tiles+1]=at("rail",tile);valid[#valid+1]=tile
          end
        end
        if #valid>0 then
          sync(rail_key(id),id,p,tiles,"rail",table.concat(valid,":"),valid[1],rail_key(id))
        end
      end
    end
    if active.air then
      for id,p in pairs(airports) do
        local valid,tiles={},{}
        for _,part in ipairs(p.tiles) do
          local ref=s.tiles[part.id] and s.tiles[part.id].airfield
          if ref and ref.airport==id then
            local kind=p.layout=="city" and "airport_city" or p.layout=="metropolitan" and "airport_metropolitan" or "airport"
            tiles[#tiles+1]=at(kind,part.id)
            valid[#valid+1]=part.id
          end
        end
        if #valid>0 and (not p.neutral or Rig.neutral_ref(s,p)) then
          if p.layout=="oilrig" then tiles[2]=at("dock",p.origin) end -- max of stock Airport 4 / Dock 5
          sync(air_key(id),id,p,tiles,"air",table.concat(valid,":"),p.origin,air_key(id))
        end
      end
    end
    for id,st in pairs(service.stations) do
      local exists=mode(st)=="rail" and rails[st.host_id] or mode(st)=="ship" and ships[id]
        or mode(st)=="air" and airports[st.host_id]
      if not exists then
        assert(#st.loading_order==0,"Cleared station still has active loading")
        service.stations[id]=nil
      end
    end
  end

  local function ship_sample(Run,p)
    local pos,yaw=Run.pose(p)
    return pos and {pos=pos,yaw=yaw,airborne=not not p.vehicle.airborne} or false
  end
  local function rail_sample(s,Run,p)
    local a={}
    if p then
      local count=p.consist.parts and #p.consist.parts or 2
      for i=1,count do
        local id,td,f,wormhole,subsurface
        if Run.presentation_sample then id,td,f,wormhole,subsurface=Run.presentation_sample(s,p,i)
        else id,td,f,wormhole=Run.sample(p,i) end
        if id then a[i]={tile=id,td=td,progress=f,reversed=not not p.consist.reversed,wormhole=wormhole,subsurface=subsurface} end
      end
    end
    return a
  end

  function F.day(s,Ship,Rail,Air,first_tick)
    local c=commercial(s)
    local service=c.service
    local active={ship=Ship and enabled(s,"ship"),rail=Rail and enabled(s,"rail"),air=Air and enabled(s,"air")}
    if active.rail and Rail.paid_art_ready and not Rail.paid_art_ready(s) then active.rail=false end
    local ctx=context(s,active)
    local p=Ship and Ship.current(s)
    local rails=Actors.gather(Rail,s) -- owned coal keeps its own cargo lifecycle
    if active.rail and Rail.settle_passenger_running_day then
      for _,r in ipairs(rails) do
        if r.fleet_id then Rail.settle_passenger_running_day(s,r.fleet_id) end
      end
    end
    local aircraft=air_gather(Air,s)
    local air_ready={}
    for _,a in ipairs(aircraft) do
      local id=air_key(a.paid_clock)
      air_ready[id]=active.air and (not Air.paid_art_ready or Air.paid_art_ready(a))
      if air_ready[id] and Air.settle_owned_day then Air.settle_owned_day(s,a) end
    end
    local base_vehicle_active=ctx.vehicle_active
    ctx.vehicle_active=function(v)
      if v.mode=="air" then return air_ready[v.id] end
      return base_vehicle_active(v)
    end
    local ship_ready=active.ship and p and (not Ship.paid_art_ready or Ship.paid_art_ready(s,p))
    if ship_ready and Ship.settle_owned_day then Ship.settle_owned_day(s,p) end
    local run=p and p.paid_clock
    local frame=view(s)
    frame.ship_samples={Ship and ship_sample(Ship,run and p or nil) or false}
    frame.rail_samples={}
    for _,r in ipairs(rails) do
      frame.rail_samples[rail_key(r.paid_clock)]={rail_sample(s,Rail,r)}
    end
    frame.air_samples={}
    for _,a in ipairs(aircraft) do frame.air_samples[air_key(a.paid_clock)]={ship_sample(Air,a)} end
    local function reconcile(key,id,def)
      if c[key]==id then return end
      if c[key] then
        local events={}
        local old=assert(service.vehicles[c[key]],"Missing saved commercial vehicle")
        Service.withdraw_vehicle(service,c[key],first_tick,ctx,events)
        flash(s,c,events,old.owner)
      end
      c[key]=id
      if id then Service.vehicle(service,def) end
    end
    if Ship then
      reconcile("active_serial",run,run and {id=run,mode="ship",owner=p.owner,
        engine=p.engine_id,speed=(Ship.engine_for and Ship.engine_for(p) or Ship.engine).max_speed,
        built=p.paid_build_year or Sim.date(s,p.paid_built_day or s.day)})
    end
    if Rail then
      Actors.reconcile(c,rails,ctx,first_tick,function(r)
        return r.paid_build_year or Sim.date(s,r.paid_built_day or s.day)
      end,function(events,owner) flash(s,c,events,owner) end)
    end
    if Air then reconcile_air(s,c,Air,aircraft,ctx,first_tick) end
    sync_stations(s,c,ctx,active)
    local hooks=Mux.town_hooks
    if (s.rail_mail_service and active.rail or active.air and next(s.stock_small_airports or {})) and Mail and Catchment then
      local physical={}
      for _,st in pairs(service.stations) do
        if st.mail_enabled and active[mode(st)] then physical[#physical+1]=st end
      end
      if s.road_mail then
        for _,st in ipairs(Mail.stops(s)) do physical[#physical+1]=st end
      end
      local function rights(id)
        local growth=s.stock_town_growth
        return growth and growth.towns[id]
      end
      local allocator=Mail.shared_allocator(Catchment,ctx.width,ctx.height,physical,{
        select_goods=ctx.select_goods,neutral_owner=ctx.neutral_owner,town_rights=rights,
        station_town=function(st) return st.town or st.site end,
        modified=s.stock_modified_catchment,tiles=function(st)
          if Mail.truck_stop(st) then return Sim.road_stop_tiles(st) end
          return st.tiles
        end})
      hooks={passenger=hooks.passenger,mail=function(_,units,x,z,house)
        return allocator.offer(units,x,z,house)
      end}
    end
    if service.tick and service.tick<first_tick-1 then
      -- All services may have been suspended. Rebase their shared clock
      -- without aging or moving paused vehicles behind the player's back.
      service.tick,service.post_tick=first_tick-1,first_tick-1
    end
    local function before(tick)
      if run then
        local ship=assert(service.vehicles[run])
        ship.stopped=not ship_ready or p.stopped or p.phase=="blocked" or p.vehicle.stopped or nil
        ship.broken=p.vehicle.breakdown or nil
      end
      Actors.controls(c,rails)
      local held
      for _,a in ipairs(aircraft) do
        local n=air_key(a.paid_clock)
        local plane=assert(service.vehicles[n])
        plane.stopped=not air_ready[n] or a.phase=="blocked" or a.stopped or a.vehicle.stopped or nil
        plane.broken=a.vehicle.broken or nil
        plane.crashed=a.vehicle.crashed or nil
        if air_ready[n] and plane.load_state and (a.transport_cancel_full or a.transport_live_load~=nil) then
          local full,no_load,full_any=CargoOrder.load_flags(a.transport_cancel_full and 0 or a.transport_live_load)
          Service.update_load_type(plane,full,no_load,full_any)
          a.transport_cancel_full,a.transport_live_load=nil,nil
        end
        if not air_ready[n] and plane.load_state then
          held=held or {}
          held[plane.load_state]=plane.load_state.elapsed
        end
      end
      local ids,events=Service.pre_motion_tick(service,tick,ctx)
      -- The common kernel intentionally advances order elapsed for stopped
      -- vehicles. An absent model/disabled preview freezes its exact visit.
      if held then for visit,elapsed in pairs(held) do visit.elapsed=elapsed end end
      local ready={}
      for _,id in ipairs(ids) do ready[id]=true end
      return ready,events
    end
    local function after(tick,ready,events,advance_rail)
      local function leave(id,force)
        local vehicle=service.vehicles[id]
        return (force or ready[id]) and Service.leave(service,id,vehicle.visit,tick,ctx,events,force) or false
      end
      if run and ship_ready then
        if Ship.count_owned_tick then Ship.count_owned_tick(s,p) end
        Ship.advance_paid(s,{
          leave=function(_,force) return leave(run,force) end,
          arrive=function(q)
            return Service.begin(service,run,q.last_dock,q.arrivals,q.last_berth,{},tick,ctx,events)
          end,
        })
      end
      local callbacks=active.rail and #rails>0 and Actors.callbacks(c,ready,ctx,tick,events) or nil
      local moved=advance_rail and advance_rail(callbacks) or callbacks and Rail.advance_paid(s,callbacks)
      if moved then
        for _,e in ipairs(moved) do
          if e.kind=="rail_collision" then
            local x,y=Sim.xy(e.tile)
            Service.accident_rating(service,e.owner,x,y)
            Sim.rail_accident_ratings(s,e.owner,x,y)
            local news=s.stock_rail_accidents or {}
            s.stock_rail_accidents=news
            news[#news+1]={tile=e.tile,owner=e.owner,victims=e.victims,tick=tick}
            if #news>16 then table.remove(news,1) end
          end
          e.world_tick=tick
          frame.rail_motion[#frame.rail_motion+1]=e
        end
        while #frame.rail_motion>4096 do table.remove(frame.rail_motion,1) end
      end
      for _,a in ipairs(aircraft) do
        local id=air_key(a.paid_clock)
        if air_ready[id] then
          Air.advance_paid(s,{
            leave=function(_,force) return leave(id,force) end,
            arrive=function(q,tile)
              assert(q.paid_clock==a.paid_clock,"Paid air movement selected another actor")
              local order=q.vehicle.order
              return Service.begin(service,id,air_key(q.last_airfield),q.arrivals,tile,
                order and order.kind=="station" and order.id==q.last_airfield and CargoOrder.arrival(order,{}) or {},tick,ctx,events)
            end,
          },function(name,q,airport)
            assert(q.paid_clock==a.paid_clock,"Paid air motion event selected another actor")
            frame.air_motion[#frame.air_motion+1]={kind=name,phase=q.phase,airport=airport.id,
              owner=a.owner,paid_clock=a.paid_clock,world_tick=tick,
              cargo_tile=name=="terminal" and q.last_terminal_tile or nil}
          end,a)
        end
      end
      while #frame.air_motion>4096 do table.remove(frame.air_motion,1) end
      Service.post_motion_tick(service,tick,ctx)
      flash(s,c,events)
      frame.ship_samples[#frame.ship_samples+1]=Ship and ship_sample(Ship,run and p or nil) or false
      for _,r in ipairs(rails) do
        local row=frame.rail_samples[rail_key(r.paid_clock)]
        row[#row+1]=rail_sample(s,Rail,r)
      end
      for _,a in ipairs(aircraft) do
        local row=frame.air_samples[air_key(a.paid_clock)]
        row[#row+1]=ship_sample(Air,a)
      end
      frame.ship_serial=run
    end
    return {before=before,after=after,hooks=hooks,offer_rig_passengers=function(ind,amount)
      return Service.offer_industry_passengers(service,ind,amount,ctx)
    end}
  end

  function F.take_effects(s,mode_)
    local frame=view(s)
    local selected,rest={},{}
    for _,event in ipairs(frame.events) do
      local dest=event.mode==mode_ and selected or rest
      dest[#dest+1]=event
    end
    frame.events=rest
    return selected
  end
  function F.take_rail_motion(s)
    local frame=view(s)
    local events=frame.rail_motion
    frame.rail_motion={}
    return events
  end

  function F.take_air_motion(s)
    local frame=view(s)
    local events=frame.air_motion
    frame.air_motion={}
    return events
  end

  local function interval(list,fraction)
    fraction=math.max(0,math.min(1,fraction or 1))
    local t=1+fraction*(#list-1)
    local i=floor(t)
    return list[i],list[i+1] or list[i],t-i
  end
  function F.pose(s,Run,fraction,mode_,paid_clock)
    local p
    if mode_=="air" then p=air_current(Run,s,paid_clock)
    else p=Run and Run.current(s) end
    if not p or not p.paid_clock then return end
    mode_=mode_ or "ship"
    if not enabled(s,mode_) then return Run.pose(p) end
    local frame=views[s]
    local list
    if mode_=="air" then list=frame and frame.air_samples and frame.air_samples[air_key(p.paid_clock)]
    else list=frame and frame.ship_serial==p.paid_clock and frame.ship_samples end
    if not list or #list<2 then return Run.pose(p) end
    local a,b,f=interval(list,fraction)
    if not a or not b then
      if a then return a.pos,a.yaw,a.airborne end
      return
    end
    local u,v=a.pos,b.pos
    local delta=(b.yaw-a.yaw+math.pi)%(2*math.pi)-math.pi
    return {x=u.x+(v.x-u.x)*f,y=u.y+(v.y-u.y)*f,z=u.z+(v.z-u.z)*f},a.yaw+f*delta,a.airborne
  end
  function F.rail_pose(s,Run,part,fraction,fleet_id,native)
    local p=Actors.current(Actors.gather(Run,s),fleet_id)
    if not p then return end
    local frame=views[s]
    local list=enabled(s,"rail") and frame and frame.rail_samples and frame.rail_samples[rail_key(p.paid_clock)]
    if not list or #list<2 then
      local tile,td,step,wormhole
      if native and Run.presentation_sample then tile,td,step,wormhole=Run.presentation_sample(s,p,part)
      else tile,td,step,wormhole=Run.sample(p,part) end
      return tile,td,step,p.consist.reversed,wormhole
    end
    local a,b,f=interval(list,fraction)
    a,b=a[part],b[part]
    if not a or a.subsurface and not native then return end
    local progress=a.progress
    if b and a.tile==b.tile and a.td==b.td and a.reversed==b.reversed and a.wormhole==b.wormhole and (native or not b.subsurface) then
      progress=progress+(b.progress-progress)*f
    end
    return a.tile,a.td,progress,a.reversed,a.wormhole
  end

  function F.status(s,Run,mode_,fleet_id)
    local p
    if mode_=="rail" then p=Actors.current(Actors.gather(Run,s),fleet_id)
    elseif mode_=="air" then p=air_current(Run,s,fleet_id)
    else p=Run and Run.current(s) end
    if not p or not p.paid_clock then return end
    local c=s.stock_ship_commercial
    local service=c and c.service
    local rail=mode_=="rail"
    local index=rail and rail_key or mode_=="air" and air_key or function(k)return k end
    local vehicle=service and service.vehicles[index(p.paid_clock)]
    local waiting={}
    local cargo=vehicle and vehicle.cargo or rail and p.town_parts and "mixed"
      or rail and p.stock_wagon==28 and "mail" or "passenger"
    local orders=rail and (p.paired or p.shuttle) or p
    local stops={orders.first,orders.second}
    local list=rail and p.orders or p.transport_orders
    if list then
      stops={}
      for _,order in ipairs(list) do
        if order.kind=="station" then stops[#stops+1]=order.station or order.id end
      end
    end
    for _,id in ipairs(stops) do
      local sid=index(id)
      local st=service and service.stations[sid]
      local visible,available=0,0
      local primary=cargo=="mixed" and "passenger" or cargo
      if st then visible,available=Service.waiting(service,sid,primary) end
      local accepted=st and (primary=="mail" and (st.mail_acceptance or 0) or st.passenger_acceptance)
      local row={waiting=visible,available=available,accepts=(accepted or 0)>=8}
      if cargo=="mixed" and st then
        local mail,mail_available=Service.waiting(service,sid,"mail")
        row.mail={waiting=mail,available=mail_available,accepts=(st.mail_acceptance or 0)>=8}
      end
      waiting[id]=row
    end
    local load=vehicle and vehicle.load_state
    local finance=rail and p.passenger_finance or mode_=="air" and p.finance or mode_=="ship" and p.owned and s.stock_owned_ferry
    local bodies
    local capacities,onboard
    if cargo=="mixed" then
      capacities,onboard={passenger=0,mail=0},{passenger=0,mail=0}
      if vehicle then
        for _,part in ipairs(vehicle.carrying_parts) do
          capacities[part.cargo]=capacities[part.cargo]+part.capacity
          onboard[part.cargo]=onboard[part.cargo]+part.units
        end
      else
        for _,part in ipairs(p.town_parts) do
          local stock=assert(Roster.entry(part.stock))
          capacities[stock.cargo]=capacities[stock.cargo]+stock.capacity
        end
      end
    end
    if vehicle and vehicle.carrying_parts then
      bodies={}
      for i,v in ipairs(vehicle.carrying_parts) do bodies[i]={tile=v.cargo_tile,onboard=v.units,role=v.role,cargo=v.cargo,capacity=v.capacity,body_id=v.body_id,stock_id=v.stock} end
    end
    local engine=rail and Roster.passenger_dmu(p.stock_engine) and p.stock_engine or p.engine_id
    return {onboard=vehicle and vehicle.units or 0,
      capacity=capacities and capacities.passenger+capacities.mail or rail and p.passenger_coaches and p.passenger_coaches*Service.stock.rail.cap
        or Service.stock_for(mode_,engine,rail and p.stock_wagon==27,cargo).cap,
      cargo=cargo,cargo_capacity=capacities,
      cargo_onboard=onboard,
      cargo_totals=vehicle and vehicle.cargo_totals,
      carrying_parts=bodies,
      paid_clock=p.paid_clock,engine=p.engine_id,owner=p.owner,
      orders=rail and p.orders or nil,order_number=rail and p.order_cursor and p.order_cursor.real+1 or nil,
      finished=rail and p.paired and p.paired.complete or nil,
      running_expense=finance and finance.expense or nil,charged_running_ticks=finance and finance.charged_ticks or nil,
      boarded=vehicle and vehicle.boarded or 0,delivered=vehicle and vehicle.delivered or 0,
      fare=vehicle and vehicle.route_profit or 0,last_fare=vehicle and vehicle.last_fare or nil,
      loading=load~=nil,waiting=waiting,last_dock=p.last_dock,berth=p.last_berth,
      last_platform=p.last_paid_platform,last_airfield=p.last_airfield,terminal_tile=p.last_terminal_tile,
      cargo_tile=vehicle and vehicle.cargo_tile,
      platform_tiles=load and load.platform_tiles,tick=service and service.tick,
      paused=not enabled(s,mode_) or rail and Run.paid_art_ready and not Run.paid_art_ready(s) or mode_=="air" and Run.paid_art_ready and not Run.paid_art_ready(p) or false}
  end
  function F.mail_station(s,id)
    local c=s.stock_ship_commercial
    local service=c and c.service
    local st=service and service.stations[rail_key(id)]
    local physical=s.stock_rail_stations and s.stock_rail_stations[id]
    if not physical or Freight.role(physical) then return end
    -- A newly built/extended platform is inspectable while the clock
    -- is paused. Recompute on a footprint edit, not for every steady read.
    local valid,tiles={},{}
    for _,tile in ipairs(physical.tiles or {}) do
      local row=s.tiles[tile]
      if row and row.rail_station_id==id and row.owner==physical.owner then
        valid[#valid+1]=tile
        tiles[#tiles+1]=at("rail",tile)
      end
    end
    if #tiles==0 then return end
    local waiting,available,rating=0,0,nil
    if st and st.mail_enabled then
      waiting,available=Service.waiting(service,st.id,"mail")
      local g=st.mail_rating_state
      rating=g and g.has_rating and g.rating
      if st.footprint_rev==table.concat(valid,":") then
        return {waiting=waiting,available=available,eighths=st.mail_acceptance or 0,
          accepts=(st.mail_acceptance or 0)>=8,rating=rating or nil}
      end
    end
    local catchment=Catchment.build({id=rail_key(id),tiles=tiles},
      Sim.W,Sim.H,s.stock_modified_catchment)
    local accept=Catchment.acceptance(catchment,"mail",context(s,{}).house_at)
    return {waiting=waiting,available=available,eighths=accept.eighths,accepts=accept.accepts,rating=rating or nil}
  end
  -- A stop can already have a real waiting queue before a vehicle is
  -- dispatched (or after the last one was withdrawn). Do not use the
  -- vehicle's two-order status as the station presentation data source.
  function F.terminal_waiting(s,mode_,id)
    if not enabled(s,mode_) then return 0 end
    local c=s.stock_ship_commercial
    local service=c and c.service
    local key=mode_=="rail" and rail_key(id) or mode_=="air" and air_key(id) or id
    local st=service and service.stations[key]
    if not st or mode(st)~=mode_ then return 0 end
    return (Service.waiting(service,key))
  end
  return F
end
