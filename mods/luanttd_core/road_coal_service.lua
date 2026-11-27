-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 manual coal transport on the existing road station loader.
-- Industry tile/production clocks, allocation and settlement are delegated
-- to the source industry kernel. No synthetic stock, route or daily fare.
return function(Sim,Coal,Catchment,Packets,Income,Rating,Station)
  local R={engine_key="coal_tipper",truck=Coal.truck,cargo=Coal.cargo}
  local floor,max=math.floor,math.max

  function R.truck_stop(st)
    return Sim.road_stop_has(st,"truck")
  end
  function R.supported_vehicle(v)
    return v and Sim.road_freight_cargo(v.engine)=="coal" and v.cargo=="coal"
  end

  local function ordered(map,predicate)
    local list={}
    for _,v in pairs(map or {}) do
      if not predicate or predicate(v) then list[#list+1]=v end
    end
    table.sort(list,function(a,b)return a.id<b.id end)
    return list
  end

  -- Bind once before the existing world's 74-tick day. Saved state stays
  -- in actual road stops and the host's industry list; caches and closure
  -- callbacks are never added to the serialized campaign.
  function R.bind(s,ctx)
    ctx=ctx or {}
    local width,height=ctx.width or Sim.W,ctx.height or Sim.H
    local xy=ctx.xy or Sim.xy
    local industries=ordered(ctx.industries or s.stock_coal_industries)
    local station_list,coverage,by_id,tile_map={},{},{},{}
    for _,ind in ipairs(industries) do
      for _,tile in ipairs(ind.tiles) do
        if not ind.removed then
          local key=tile.z*width+tile.x
          assert(tile.x>=0 and tile.x<width and tile.z>=0 and tile.z<height and not tile_map[key],
            "Invalid or overlapping stock industry tiles")
          tile_map[key]={ind,tile}
        end
      end
    end
    local road_stations={}
    for _,st in ipairs(ctx.road_enabled~=false and ordered(s.stations,R.truck_stop) or {}) do
      local x,z=xy(st.tile)
      st.stock=st.stock or {}
      if ctx.separate_queue then st.stock_coal_packets=st.stock_coal_packets or {} end
      Coal.goods(st)
      -- Real host coordinates are 1-based. Every Coal/Catchment footprint
      -- is 0-based. Packet distances still get the original host tile ID.
      local view={id=st.id,tile=st.tile,x=x-1,z=z-1,town=st.town or st.site,
        owner=st.owner,stock=ctx.separate_queue and {coal=st.stock_coal_packets} or st.stock,
        goods=st.goods,tiles=Sim.road_stop_tiles(st)}
      station_list[#station_list+1]=view
      road_stations[#road_stations+1]=view
      by_id[st.id]=view
      coverage[st.id]=Catchment.build(view,width,height,ctx.modified_catchment)
    end
    if ctx.extend then ctx.extend(station_list,coverage) end
    local B={world=s,ctx=ctx,xy=xy,industries=industries,
      stations=station_list,road_stations=road_stations,coverage=coverage,by_id=by_id}
    local function random() return (ctx.random_u32 or Station.random_u32)(s) end
    local function select_goods() return ctx.select_goods~=false end
    local function option(name,tick)
      local value=ctx[name]
      if type(value)=="function" then return value(s,tick) end
      return value
    end

    function B.queue(st)
      local view=assert(by_id[st.id],"Coal can only use a stock truck stop")
      view.stock.coal=view.stock.coal or {}
      return view.stock.coal
    end

    function B.report(st)
      local view=by_id[st.id]
      if not view then return {accepts=false,eighths=0,near={},sources={}} end
      local cover=coverage[st.id]
      local report=Coal.acceptance(view,cover,industries)
      report.sources={}
      for _,ind in ipairs(industries) do
        if ind.produced and not ind.removed then
          for _,tile in ipairs(ind.tiles) do
            if Catchment.contains(cover,tile.x,tile.z) then
              report.sources[#report.sources+1]=ind.id
              break
            end
          end
        end
      end
      return report
    end

    -- Call from the same stock landscape walk as houses, once per tile
    -- visited. The pure kernel drains waiting production only when a
    -- completed, genuinely visited industry tile dispatches it.
    local function visit(item,tick)
      return Coal.tile_loop(item[1],item[2],{
        recession=option("recession",tick),editor=option("editor",tick),
      },function(ind,amount)
        return (ctx.distribute or Coal.distribute)(ind,amount,station_list,coverage,{
          day=s.day,select_goods=select_goods(),town_rights=ctx.town_rights,
          neutral_owner=ctx.neutral_owner,packet_allocatable=ctx.packet_allocatable,
        })
      end)
    end

    function B.tile_visit(x,z,tick)
      if x<0 or x>=width or z<0 or z>=height then return 0,0 end
      local item=tile_map[z*width+x]
      if item then return visit(item,tick) end
      return 0,0
    end
    -- Day-scoped and read-only to the caller. Entries are keyed by the
    -- zero-based source ID; the coordinate dispatcher keeps its bounds.
    function B.landscape(width_,height_)
      if width==width_ and height==height_ then return tile_map,visit end
    end

    -- Call after station loading, vehicles and OnTick_Station of the
    -- *same* stock tick. This fills industry waiting, not station queues.
    function B.after_vehicle_tick(tick)
      local total=0
      local settings={editor=option("editor",tick),scale=option("scale",tick),
        ambient_rng=random,random_u32=random}
      for _,ind in ipairs(industries) do total=total+Coal.production_tick(ind,settings) end
      return total
    end

    -- Call once on the truck stop's existing 185-tick rating event. The
    -- station's shared timers belong to the existing road adapter.
    function B.step_rating(st)
      if not R.truck_stop(st) then return end
      local g=Coal.goods(st)
      local waiting=Coal.waiting(assert(by_id[st.id]))
      local r=Rating.step(g,{waiting=waiting,destinations=waiting>0 and 1 or 0,
        select_goods=select_goods(),random_u32=random,
        statue=Sim.station_has_town_statue and Sim.station_has_town_statue(s,st)})
      for _,name in ipairs({"rating","has_rating","time_since_pickup","last_speed","last_age","max_waiting_cargo"}) do
        g[name]=r[name]
      end
      if r.drop>0 then
        for sid,n in pairs(Station.truncate(B.queue(st),waiting,r.drop,random)) do
          local from=s.stations[sid]
          if R.truck_stop(from) then
            local origin=Coal.goods(from)
            origin.max_waiting_cargo=max(origin.max_waiting_cargo,n)
          end
        end
      end
      return r
    end

    function B.timing(v)
      if R.supported_vehicle(v) then return Coal.truck.load_amount,Coal.truck.cargo_age_ticks end
    end

    function B.display_waiting(st)
      if not R.truck_stop(st) then return 0 end
      local n=Coal.waiting(assert(by_id[st.id]))
      for _,id in ipairs(st.loading_order or {}) do
        local v=s.fleet[id]
        if R.supported_vehicle(v) and v.load_state and v.load_state.station==st.id then
          n=n+v.load_state.reserved_units
        end
      end
      return n
    end

    -- Fits the generic road loader directly or can be dispatched alongside
    -- passenger/mail callbacks from road_station_service.lua.
    -- For a mixed per-station pass, call ops.station_done after *each*
    -- Loading.tick, before the next station can deliver. OpenTTD batches
    -- DeliverGoodsToIndustry through that station before triggering plants.
    function B.ops(tick,emit)
      local pending={}
      local function event(kind,st,v,rec)
        if emit then
          rec.tick,rec.day,rec.tile,rec.station=tick,s.day,st.tile,st.id
          rec.owner,rec.vehicle,rec.cargo=v.owner,v.id,"coal"
          emit(kind,st,v,rec)
        end
      end
      local function payment_base(p,dist)
        return Income.regular(p.units,dist,p.age or 0,option("current_payment",tick) or Coal.cargo.payment,
          Coal.cargo.days1,Coal.cargo.days2)
      end
      return {
        xy=xy,slice=Coal.truck.load_amount,gradual=s.stock_gradual_loading~=false,queue=B.queue,
        feeder_percent=s.stock_feeder_percent,
        accepts=function(st) return B.report(st).accepts end,
        can_load=function(st,v)
          if st.owner~=ctx.neutral_owner then return true end
          local rights=ctx.town_rights and ctx.town_rights(st.town or st.site)
          return not rights or rights.exclusive_counter==0 or rights.exclusivity==v.owner
        end,
        attempt=function(st,v,left)
          local byear=Sim.date(s,v.bought or s.day)
          Coal.observe_loading(st,{mode="road",build_year=byear,max_speed=Sim.vehicles[v.engine].speed},left,Sim.date(s))
        end,
        loaded=function(st,v,n)
          Station.loaded(st)
          st.last_service=st.last_service or {}
          st.last_service.coal=s.day
          event("board",st,v,{units=n})
        end,
        transferred=function(st,v,p)
          local g=Coal.goods(st)
          if not g.has_rating then g.has_rating=true;g.time_since_pickup=0 end
          event("transfer",st,v,{units=p.units,source_industry=p.source})
        end,
        unloaded=function(st) Station.unloaded(st) end,
        transfer_income=function(st,v,p)
          return payment_base(p,Packets.distance(p,Sim.road_loading_tile(s,st,v),xy))
        end,
        deliver=function(st,v,p)
          local distance=Packets.distance(p,Sim.road_loading_tile(s,st,v),xy)
          local result=Coal.delivery(st,B.report(st),p,{
            distance=distance,date=option("economy_date",tick) or s.day,
            current_payment=option("current_payment",tick),refused=ctx.refused,
          })
          if Sim.stock_town_accept then Sim.stock_town_accept(s,st.town or st.site,"coal",result.accepted,0) end
          if result.accepted>0 and Sim.stock_subsidy_active and Sim.stock_subsidy_active(s) then
            result.payment=Sim.stock_subsidy_pay(s,"coal",v.owner,p,result.payment,coverage[st.id].tiles,"coal")
          end
          local l=assert(v.load_state)
          l.coal_accepted=(l.coal_accepted or 0)+result.accepted
          for _,destination in ipairs(result.plants) do
            local ind=destination.industry
            pending[ind.id]=ind
            if destination.amount>0 then
              event("deliver",st,v,{units=destination.amount,source_industry=p.source,
                destination_industry=ind.id,distance=distance,age=p.age or 0})
              if ctx.received then ctx.received(s,ind,destination.amount) end
            end
          end
          return result.payment
        end,
        payment=function(st,v,p)
          local l=assert(v.load_state)
          local accepted=l.coal_accepted or 0
          l.coal_accepted=nil
          -- The shared loader's delivered field counts physical unloading.
          -- Credit only actual industry acceptance, never rejected tons.
          assert(accepted<=p.delivered,"Industry accepted more than was unloaded")
          if accepted>0 then
            local c=Sim.company(s,v.owner)
            if ctx.credit then ctx.credit(c,p.route)
            else c.cash,c.revenue,c.month_rev=c.cash+p.route,c.revenue+p.route,c.month_rev+p.route end
            c.units,c.paid_units=c.units+accepted,c.paid_units+accepted
            if Sim.stock_vehicle_operating then Sim.stock_vehicle_operating(s,v,p.route) end
            if Sim.stock_economy_delivered then Sim.stock_economy_delivered(c,"coal",accepted) end
            v.delivered=(v.delivered or 0)+accepted
            v.revenue=(v.revenue or 0)+p.route
            event("fare",st,v,{units=accepted,amount=p.route})
          end
          v.stock_profit_with_feeders=(v.stock_profit_with_feeders or 0)+p.visual+p.transfer
        end,
        station_done=function()
          local plants={}
          for _,ind in ipairs(ordered(pending)) do plants[#plants+1]={industry=ind} end
          Coal.trigger_delivery({plants=plants})
          pending={}
        end,
      }
    end

    function B.month(year,settings)
      local outcomes={}
      for _,ind in ipairs(industries) do
        local next_={random_u32=random}
        for k,v in pairs(settings or {}) do next_[k]=v end
        local reason,change,percent=Coal.month(ind,year,next_)
        if reason then outcomes[#outcomes+1]={id=ind.id,kind=reason,change=change,percent=percent} end
      end
      return outcomes
    end
    return B
  end
  return R
end
