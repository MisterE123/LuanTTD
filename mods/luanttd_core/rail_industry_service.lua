-- SPDX-License-Identifier: GPL-2.0-only
-- Shared ordinary homogeneous freight actor. Station geometry and
-- clock are physical; the producer, queue competition and unload receipt
-- always come from the one existing industry pipeline.
return function(profile,Sim,Rules,Catchment,Roster,RailStation,Packets,Rating,Station,LoaderFactory,Timing)
  local root=(core and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
  local Ordered=dofile(root.."/openttd/rail_multihead_loading.lua")
  local TownStations=dofile(root.."/town_station_services.lua")(Sim)
  local R={version=1,wagon=profile.wagon}
  local stock=Roster.entry(R.wagon.stock_id)
  if stock then
    for key,value in pairs(R.wagon) do assert(stock[key]==value,"Rail industry wagon catalog mismatch: "..key) end
    R.wagon=stock
  end
  local cargo_name=R.wagon.cargo
  local accepted_wagons={[R.wagon.stock_id]=R.wagon}
  for _,id in ipairs(profile.wagon_variants or {}) do
    local variant=assert(Roster.entry(id))
    assert(variant.kind=="wagon" and variant.cargo==cargo_name and not accepted_wagons[id])
    accepted_wagons[id]=variant
  end
  function R.wagon_spec(id) return accepted_wagons[id] end
  local spec=assert(Rules.cargo[cargo_name])
  local sequence,accepted,route_tag=cargo_name.."_packet_sequence",cargo_name.."_accepted","rail_"..cargo_name
  local function uint(n) return type(n)=="number" and n>=0 and n%1==0 end
  function R.mass(units,freight,id)
    freight=freight or 1
    local wagon=id and assert(R.wagon_spec(id)) or R.wagon
    assert(uint(units) and units<=wagon.capacity and uint(freight) and freight>=1 and freight<=255)
    -- CargoSpec::WeightOfNUnitsInTrain applies the factor before integer
    -- weight conversion. Stock cargo provides its own sixteenths-of-ton weight.
    local cargo=math.floor(units*freight*spec.weight_16/16)
    return wagon.tare+cargo,cargo
  end
  function R.new() return {version=R.version,stations={}} end
  R.index=RailStation.index
  R.loading_pulse=RailStation.loading_pulse

  function R.bind(s,state,ctx)
    assert(state.version==R.version,"Unsupported rail industry carrier state")
    assert(ctx and ctx.pipeline and ctx.roles,"Existing industry producer and explicit station roles required")
    local pipeline
    local rooms,view_ids,views={}, {}, {}
    local tile_xy=ctx.xy or Sim.xy
    local width,height=ctx.width or Sim.W,ctx.height or Sim.H
    local next_id={}
    for id in pairs(ctx.roles) do next_id[#next_id+1]=id end
    table.sort(next_id)
    for _,local_id in ipairs(next_id) do
      local raw=s.stock_rail_stations and s.stock_rail_stations[local_id]
      local role=ctx.roles[local_id]
      if raw and (role=="load" or role=="unload") then
        local tiles,physical={},{}
        for _,pos in ipairs(raw.tiles or {}) do
          if not physical[pos] and RailStation.platform(s,raw,pos) then
            local x,z=tile_xy(pos)
            physical[pos]=true
            tiles[#tiles+1]={x=x-1,y=z-1,kind="rail"}
          end
        end
        if #tiles>0 then
          local first
          for _,pos in ipairs(raw.tiles or {}) do if physical[pos] then first=pos;break end end
          local st_id=R.index(local_id)
          local st=state.stations[st_id] or {
            id=st_id,mode="rail",host_id=local_id,owner=raw.owner,stock={[cargo_name]={}},
            loading_order={},time_since_load=255,time_since_unload=255,
          }
          assert(st.owner==raw.owner,"Rail industry platform owner changed")
          TownStations.resume_service(s,raw,st)
          local x,z=tile_xy(first)
          st.x,st.z,st.tile,st.tiles,st.role=x-1,z-1,first,tiles,role
          st.freight_cargo=cargo_name
          local town=ctx.town and ctx.town(st) or Sim.nearest_town(s,first)
          st.town=type(town)=="table" and town.id or town
          views[#views+1]=st
          rooms[st.id]={raw=raw,tiles=physical}
          view_ids[st.id]=true;state.stations[st.id]=st
          Rules.goods(st,cargo_name)
        end
      end
    end
    for id,st in pairs(state.stations) do
      if not view_ids[id] and #st.loading_order==0 then state.stations[id]=nil end
    end
    local B={views=views}
    local all,covers={},{}
    for _,st in ipairs(ctx.road_stations or {}) do
      assert(not covers[st.id],"Duplicate physical freight station")
      all[#all+1]=st;covers[st.id]=Catchment.build(st,width,height,ctx.modified)
    end
    for _,st in ipairs(views) do
      assert(not covers[st.id],"Rail/road freight StationIDs collided")
      all[#all+1]=st;covers[st.id]=Catchment.build(st,width,height,ctx.modified)
    end
    table.sort(all,function(l,r) return l.id<r.id end)
    -- The host builds its existing industry binding with this combined list.
    -- Neither this module nor the road host may create another producer.
    pipeline=assert(ctx.pipeline(all,covers),"Missing shared industry binding")
    B.pipeline,B.stations,B.coverage=pipeline,all,covers
    function B.station_at(id)
      return rooms[id] and state.stations[id]
    end

    function B.report(local_id)
      local id=R.index(local_id)
      if not rooms[id] then return end
      local st=state.stations[id]
      local source=(pipeline.report_with_sources or pipeline.report)(st.id,cargo_name)
      if not source then return end
      local r={};for k,v in pairs(source) do r[k]=v end
      local available=0
      for _,p in ipairs(st.stock[cargo_name]) do available=available+p.units end
      local loading=state.vehicle and state.vehicle.load_state
      local reserved=loading and loading.station==id and loading.reserved_units or 0
      r.available,r.reserved,r.waiting,r.role=available,reserved,available+reserved,st.role
      r.station=st
      return r
    end
    function B.refresh(local_id)
      local st=state.stations[R.index(local_id)]
      local report=B.report(local_id)
      if not report then return end
      st.last_acceptance=not not report.accepts
      st.acceptance={accepts=report.accepts,eighths=report.eighths,near=report.near,
        always_accepted=report.always_accepted,house_eighths_by_town=report.house_eighths_by_town}
      return report
    end
    for _,st in ipairs(views) do
      local footprint=""
      for _,t in ipairs(st.tiles) do footprint=footprint..':'..t.x..','..t.y end
      if st.footprint~=footprint then
        if #st.loading_order~=0 then rooms[st.id].changed=true
        else st.footprint=footprint;B.refresh(st.host_id) end
      elseif not st.acceptance or cargo_name=="goods" and st.acceptance.always_accepted==nil then B.refresh(st.host_id)
      end
    end
    local function event(kind,st,v,tick,body)
      body=body or {}
      body.kind,body.cargo,body.mode=kind,cargo_name,"rail"
      body.tick,body.station,body.station_local,body.vehicle,body.owner,body.visit=
        tick,st.id,st.host_id,v.id,v.owner,v.visit
      body.tile,body.body_id,body.part=v.cargo_tile,v.body_id,v.part
      if ctx.emit then ctx.emit(body) end
    end
    local timing_frame
    local Load=LoaderFactory({initial=Timing.initial,can_leave=Timing.can_leave,pulse=function(m)
      assert(timing_frame)
      return R.loading_pulse(m,timing_frame.length,timing_frame.load_state.platform_tiles,ctx.platform_penalty)
    end},Packets)
    local compartments=Ordered.create(Load,Timing)
    local function ops(tick)
      local tokens,moved=0,false
      local result={
        slice=(state.vehicle and assert(R.wagon_spec(state.vehicle.wagon)) or R.wagon).load_amount,gradual=s.stock_gradual_loading~=false,feeder_percent=s.stock_feeder_percent,
        consist=compartments,
        queue=function(st) return st.stock[cargo_name] end,
        accepts=function(st) return st.last_acceptance end,
        can_load=function(st,v) return Catchment.may_load(st,v.owner,ctx.town_rights and ctx.town_rights(st.town),ctx.neutral_owner) end,
        pickup=function(st,v,p) Packets.pickup(p,{id=st.id,tile=v.cargo_tile},tile_xy) end,
        drop=function(st,v,p) Packets.drop(p,{id=st.id,tile=v.cargo_tile},tile_xy) end,
        attempt=function(st,v,left)
          Catchment.observe_loading(Rules.goods(st,cargo_name),"rail",v.speed,
            ctx.year and ctx.year(s,tick) or Sim.date(s),v.built,left)
        end,
        loaded=function(st,v,n)
          Catchment.loaded(st,"rail",n)
          event("board",st,v,tick,{units=n,weight=R.mass(v.units,s.stock_freight_trains,v.stock or v.wagon)})
        end,
        unloaded=function(st) Station.unloaded(st) end,
        deliver=function(st,v,packet)
          -- One payment/receipt sequence spans all wagon drops in this
          -- physical station visit. Wagon ordinals never reset it.
          local l=state.vehicle.load_state
          local seq=(l[sequence] or 0)+1
          local token=table.concat({route_tag,v.id,v.visit,seq},":")
          local r,why=pipeline.stage(st.id,tick,token,packet,v.cargo_tile,{owner=v.owner})
          assert(r,why)
          l[sequence]=seq
          l[accepted]=(l[accepted] or 0)+r.units
          event("deliver",st,v,tick,{units=r.units,distance=r.distance,age=r.age,source_industry=packet.source})
          tokens=tokens+1
          return r.payment
        end,
        payment=function(st,v,p)
          local l=v.load_state
          local accepted=l[accepted] or 0;l[accepted]=nil
          assert(accepted<=p.delivered)
          if accepted>0 then
            local c=Sim.company(s,v.owner)
            if ctx.credit then ctx.credit(c,p.route) else c.cash,c.revenue,c.month_rev=c.cash+p.route,c.revenue+p.route,c.month_rev+p.route end
            c.units,c.paid_units=c.units+accepted,c.paid_units+accepted
            if Sim.stock_economy_delivered then Sim.stock_economy_delivered(c,v.cargo,accepted) end
            if Sim.stock_vehicle_operating then
              Sim.stock_vehicle_operating(s,s.stock_rail_fleet and s.stock_rail_fleet.units[v.id],p.route)
            end
            v.delivered,v.revenue=v.delivered+accepted,v.revenue+p.route
            event("fare",st,v,tick,{units=accepted,amount=p.route})
          end
        end,
      }
      function result.finish(st)
        if tokens>0 and not moved then
          moved=true
          local scan,why=pipeline.finish(st.id,tick)
          assert(scan,why)
          if ctx.post_scan then ctx.post_scan(scan) end
        end
      end
      return result
    end

    function B.vehicle(def)
      local parts=def.parts
      local count=parts and #parts or 1
      local wagon=R.wagon_spec(def.wagon)
      if state.vehicle or not wagon or def.length~=(count+1)*wagon.length
          or parts and (count<2 or count>(profile.max_wagons or 1))
          or not uint(def.id) or not def.owner or not uint(def.built) or not uint(def.speed) then
        return nil,profile.single_error
      end
      local v={id=def.id,wagon=def.wagon,length=def.length,owner=def.owner,built=def.built,speed=def.speed,
        cargo=cargo_name,mode="rail",units=0,batches={},cargo_age_counter=1,delivered=0,revenue=0}
      if parts then
        local seen={}
        v.carrying_parts={}
        for i,part in ipairs(parts) do
          if part.stock~=wagon.stock_id or part.index~=i+1 or not uint(part.body_id) or seen[part.body_id] then
            return nil,"INVALID_PHYSICAL_FREIGHT_WAGON"
          end
          seen[part.body_id]=true
          v.carrying_parts[i]={id=v.id,owner=v.owner,built=v.built,speed=v.speed,mode="rail",cargo=cargo_name,
            body_id=part.body_id,part=part.index,stock=part.stock,capacity=wagon.capacity,
            slice=wagon.load_amount,aging=wagon.cargo_age_ticks,cargo_age_counter=1,batches={},units=0}
        end
      end
      state.vehicle=v
      return v
    end
    function B.arrive(local_id,visit,tick,head,cargo,cargo_tiles)
      local v=state.vehicle
      local id=R.index(local_id)
      if not v or not uint(visit) or visit==0 or state.tick~=tick or state.aged_tick==tick then return nil,"WRONG_VEHICLE_PHASE" end
      if v.visit==visit and v.load_state and v.load_state.station==id and v.head_tile==head and v.cargo_tile==cargo then
        if not v.carrying_parts then return v.load_state end
        if cargo_tiles and #cargo_tiles==#v.carrying_parts then
          local same=true
          for i,part in ipairs(v.carrying_parts) do same=same and part.cargo_tile==cargo_tiles[i] end
          if same then return v.load_state end
        end
      end
      if visit<=(v.visit or 0) or v.load_state then return nil,"DUPLICATE_OR_STALE_VISIT" end
      local st,room=state.stations[id],rooms[id]
      if not room or st.owner~=v.owner then return nil,"OWN_STOCK_RAIL_PLATFORM_REQUIRED" end
      local n=RailStation.platform(s,room.raw,head)
      if not n or not room.tiles[cargo] then return nil,"ACTUAL_WAGON_PLATFORM_TILE_REQUIRED" end
      -- All actual bodies must occupy the same directional platform;
      -- adjacent 8-unit bodies may share one physical tile.
      local tiles=cargo_tiles or {cargo}
      if v.carrying_parts and (#tiles~=#v.carrying_parts or tiles[1]~=cargo) then
        return nil,"ACTUAL_FREIGHT_BODY_TILES_REQUIRED"
      end
      local last=head
      for _,tile in ipairs(tiles) do
        if not room.tiles[tile] then return nil,"ACTUAL_WAGON_PLATFORM_TILE_REQUIRED" end
        local x,z=tile_xy(last)
        local u,w=tile_xy(tile)
        if Sim.distance(last,tile)>1 or room.raw.axis==0 and z~=w or room.raw.axis==1 and x~=u then
          return nil,"ACTUAL_COUPLED_WAGON_TILE_REQUIRED"
        end
        last=tile
      end
      v.visit,v.head_tile,v.cargo_tile=visit,head,cargo
      local flags={full=st.role=="load",no_load=st.role=="unload"}
      local o=ops(tick)
      local l=v.carrying_parts and compartments.begin(st,v,tiles,flags,o,visit) or
        Load.begin(st,v,assert(R.wagon_spec(v.wagon)).capacity,flags,o)
      l.arrived_tick,l.platform_tiles=tick,n
      event("arrive",st,v,tick,{head=head,platform_tiles=n})
      return l
    end
    function B.loading_tick(tick,stopped,hold_load)
      if state.tick==tick then return false end
      if state.tick and (tick~=state.tick+1 or state.aged_tick~=state.tick) then return nil,"NONCONTIGUOUS_"..profile.tag.."_RAIL_CLOCK" end
      local v=state.vehicle
      local l=v and v.load_state
      if l and not hold_load then
        local room=rooms[l.station]
        if not room or room.changed or not room.tiles[v.cargo_tile] or
            not RailStation.platform(s,room.raw,v.cargo_tile) or
            RailStation.platform(s,room.raw,v.head_tile)~=l.platform_tiles then
          return nil,profile.tag.."_RAIL_PLATFORM_LOST"
        end
        for _,body in ipairs(v.carrying_parts or {}) do
          if not room.tiles[body.cargo_tile] or not RailStation.platform(s,room.raw,body.cargo_tile) then
            return nil,profile.tag.."_RAIL_PLATFORM_LOST"
          end
        end
      end
      state.tick=tick
      if not v then return true end
      v.stopped=not not stopped
      if not l or hold_load then return true end
      local st=state.stations[l.station]
      local o=ops(tick)
      assert(not timing_frame,"Industry station clock cannot reenter the same rail actor")
      timing_frame=v
      local good,rounds,leaves=pcall(Load.tick,st,{[v.id]=v},o)
      timing_frame=nil
      if not good then error(rounds) end
      for _,r in ipairs(rounds) do
        if r.consist then l.ticks=R.loading_pulse(r,v.length,l.platform_tiles,ctx.platform_penalty) end
      end
      o.finish(st)
      if #leaves>0 then l.ready_tick=tick end
      return true,l.ready_tick==tick
    end
    function B.leave(visit,tick)
      local v=state.vehicle
      local l=v and v.load_state
      if not l or v.visit~=visit or l.ready_tick~=tick or state.tick~=tick or state.aged_tick==tick then return false end
      local st=state.stations[l.station]
      local o=ops(tick)
      if v.carrying_parts then compartments.leave(st,v,o) else Load.leave(st,v,o) end
      o.finish(st)
      event("leave",st,v,tick)
      v.head_tile,v.cargo_tile=nil,nil
      return true
    end
    function B.after_motion(tick)
      if state.tick~=tick then return nil,"WRONG_VEHICLE_PHASE" end
      if state.aged_tick==tick then return false end
      local v=state.vehicle
      if v then
        local aging=assert(R.wagon_spec(v.wagon)).cargo_age_ticks
        if v.carrying_parts then compartments.age(v,aging)
        else Load.age_vehicle(v,1,aging) end
      end
      if ctx.rating then
        for _,st in ipairs(views) do
          local p,n=Rating.advance_clock(st.rating_phase or 0,1)
          st.rating_phase=p
          if n>0 then
            Rating.increment_station_timers(st)
            ctx.rating(st)
          end
        end
      end
      for _,st in ipairs(views) do
        if (tick+st.id)%250==0 then B.refresh(st.host_id);Rules.goods(st,cargo_name).accepted_bigtick=nil end
      end
      state.aged_tick=tick
      return true
    end
    return B
  end
  return R
end
