-- SPDX-License-Identifier: GPL-2.0-only
-- Stock one-processor road chains on one common station unload pass.
-- The default Farm profile keeps its public fields and saves unchanged.
return function(Sim,Rules,Adapter,Packets,Income,Rating,Station,profile)
  local R={}
  profile=profile or {
    tag="farm",label="Farm",storage="stock_farm_industries",conflicts={"stock_timber_industries","stock_oil_industries"},
    vehicles={livestock="livestock_van",goods="goods_truck",grain="grain_truck"},
    cargo={"livestock","goods","grain"}, -- Original CargoIDs 4,5,6.
  }
  local pairs_by_cargo,ordered=profile.vehicles,profile.cargo
  local queue_key,cache_key,ledger_key="stock_"..profile.tag,profile.tag.."_acceptance",profile.tag.."_transactions"
  local seq_key,accepted_key=profile.tag.."_packet_sequence",profile.tag.."_accepted"
  local floor,max=math.floor,math.max
  function R.supported_vehicle(v)
    return v and pairs_by_cargo[v.cargo]~=nil and (pairs_by_cargo[v.cargo]==v.engine or
      Sim.road_freight_cargo(v.engine)==v.cargo) or false
  end
  function R.truck_stop(st) return st and st.mode=="road" and st.stop_type=="truck" end
  function R.bind(s,options)
    options=options or {}
    local xy=options.xy or Sim.xy
    local industry_at=options.industries or s[profile.storage] or {}
    for _,other in ipairs(profile.conflicts or {}) do
      assert(not next(s[other] or {}),"Freight chains need a single Goods authority")
    end
    local width,height=options.width or Sim.W,options.height or Sim.H
    local stations,by_id={},{}
    for _,st in pairs(s.stations) do
      if R.truck_stop(st) then
        local x,z=xy(st.tile)
        st[queue_key]=st[queue_key] or {}
        st.goods=st.goods or {}
        local point={id=st.id,st=st,tile=st.tile,x=x-1,z=z-1,town=st.town or st.site,owner=st.owner,serve_neutral=s.stock_serve_neutral_industries~=false,
          stock=st[queue_key],goods=st.goods,tiles=Sim.road_stop_tiles(st)}
        stations[#stations+1]=point;by_id[st.id]=point
      end
    end
    -- Ship stations are bound into the same physical allocator as trucks
    -- and trains. Filter their capacity to their actual carried cargo.
    for _,st in ipairs(options.ship_stations or {}) do
      assert(not by_id[st.id] and st.mode=="ship" and st.freight_cargo=="oil")
      st[queue_key]=st[queue_key] or {}
      st.goods=st.goods or {}
      local x,z=xy(st.tile)
      local point={id=st.id,st=st,tile=st.tile,x=x-1,z=z-1,town=st.town,owner=st.owner,
        stock=st[queue_key],goods=st.goods,tiles=st.tiles,freight_cargo=st.freight_cargo,
        neutral_rig=st.neutral_rig,serve_neutral=st.serve_neutral}
      stations[#stations+1]=point;by_id[st.id]=point
    end
    table.sort(stations,function(a,b)return a.id<b.id end)
    local function house_at(x,z)
      local id=Sim.id(x+1,z+1)
      local t=id and s.tiles[id]
      return t and t.house and t.source_house or nil
    end
    local function random() return (options.random_u32 or Station.random_u32)(s) end
    local B,raw={},nil
    local function source_report(id,cargo)
      local p=by_id[id]
      if p and p.freight_cargo and p.freight_cargo~=cargo then return {accepts=false,eighths=0,sources={}} end
      local r=raw.report(id,cargo)
      if not r then return end
      local station=p or assert(raw.station(id),"Accepted freight report has no station")
      r.sources={}
      for _,ind in ipairs(raw.industries) do
        if not ind.removed and Rules.output(ind,cargo) and (not Rules.allowed_source or Rules.allowed_source(station,ind)) then
          for _,t in ipairs(ind.tiles) do
            if raw.covered(id,t.x,t.z) then r.sources[#r.sources+1]=ind.id;break end
          end
        end
      end
      return r
    end
    local function refresh(st,tick,big_tick)
      -- Source UpdateStationAcceptance at construction and the spread
      -- big tick (TimerGameTick::counter + StationID) % 250 == 0.
      local saved=st[cache_key]
      if not saved or saved.topology~=s.topology or
          big_tick and (tick+st.id)%250==0 and saved.tick~=tick then
        saved={topology=s.topology,tick=tick,reports={}}
        for _,cargo in ipairs(ordered) do saved.reports[cargo]=source_report(st.id,cargo) end
        st[cache_key]=saved
      end
      return saved.reports
    end
    s[ledger_key]=s[ledger_key] or Adapter.new()
    local function open(scan_stations,coverage)
      assert(not raw,"The freight chain must have one shared station scan")
      raw=Adapter.bind(s,s[ledger_key],{width=width,height=height,xy=xy,
        stations=scan_stations,coverage=coverage,industries=industry_at,house_at=options.house_at or house_at,
        field_board=options.field_board,field_attempt=options.field_attempt,forestry_changed=options.forestry_changed,
        random_u32=random,acceptance=function(st,cargo,tick)
          if by_id[st.id] then return refresh(st.st,tick)[cargo] end
          if cargo==st.freight_cargo then return st.acceptance end
        end,
        select_goods=s.stock_select_goods~=false,neutral_owner=options.neutral_owner,
        serve_neutral=s.stock_serve_neutral_industries~=false,
        town_rights=options.town_rights,modified=options.modified_catchment,refuses=options.refuses,
        packet_allocatable=options.packet_allocatable,ambient=options.ambient,animated=options.animated,
        complete_rig=options.complete_rig,
        opts={current_payment=options.current_payment,scale=options.scale,recession=options.recession,
          economy_date=options.economy_date or function(world)return world.day end}})
      raw.report_with_sources=source_report
      return raw
    end
    if options.station_union then
      B.rail=options.station_union(stations,open,function(scan) return B.post_scan(scan) end,
        function(st) return B.step_rail_rating(st) end)
      assert(raw,"The station union did not bind freight")
    else open(stations) end
    B.stations,B.industries=stations,raw.industries
    function B.report(st,cargo,tick)
      if not (st and by_id[st.id] and pairs_by_cargo[cargo]) then return {accepts=false,eighths=0,sources={}} end
      return refresh(st,tick)[cargo]
    end
    function B.tile_visit(x,z,tick,offer_rig_passengers)
      if options.field_board and options.field_board.visit then options.field_board.visit(x,z,tick,options.editor and options.editor(s,tick)) end
      return raw.tile_visit(x,z,tick,offer_rig_passengers)
    end
    function B.after_vehicle_tick(tick)
      for _,p in ipairs(stations) do refresh(p.st,tick,true) end
      for _,i in ipairs(raw.industries) do raw.produce(i.id,tick) end
      if options.each_tick then options.each_tick(tick) end
    end
    function B.month(ordinal,year,opts)
      local out={}
      for _,i in ipairs(raw.industries) do
        local kind,details=raw.month(i.id,ordinal,year,opts)
        if kind then out[#out+1]={id=i.id,kind=kind,changes=details} end
      end
      return out
    end
    local function queue(st,cargo)
      local p=assert(by_id[st.id],profile.label.." cargo requires a real truck stop")
      return Rules.queue(p,cargo)
    end
    local function waiting(st,cargo)
      local n=0
      for _,p in ipairs(queue(st,cargo)) do n=n+p.units end
      return n
    end
    function B.display_waiting(st,cargo)
      if not by_id[st.id] then return 0 end
      local n=waiting(st,cargo)
      for _,id in ipairs(st.loading_order or {}) do
        local v=s.fleet[id]
        if v and R.supported_vehicle(v) and v.cargo==cargo and v.load_state and v.load_state.station==st.id then
          n=n+v.load_state.reserved_units
        end
      end
      return n
    end
    local function step_rating(cargo,g,stock,dirty,rail_at)
      local n=0
      for _,p in ipairs(stock) do n=n+p.units end
      local next_rating=Rating.step(g,{waiting=n,destinations=n>0 and 1 or 0,select_goods=s.stock_select_goods~=false,
        random_u32=random,waiting_changed=dirty})
      for _,k in ipairs({"rating","has_rating","time_since_pickup","last_speed","last_age","max_waiting_cargo"}) do
        g[k]=next_rating[k]
      end
      if next_rating.drop>0 then
        for id,count in pairs(Station.truncate(stock,n,next_rating.drop,random)) do
          local point=by_id[id]
          local src=point and point.st or (rail_at and rail_at(id))
          if src then
            local g0=Rules.goods(src,cargo)
            g0.max_waiting_cargo=max(g0.max_waiting_cargo,count)
          end
        end
      end
      return next_rating.waiting_changed
    end
    local function rail_at(id) return B.rail and B.rail.station_at(id) end
    function B.step_rating(st,dirty)
      if not by_id[st.id] then return dirty end
      dirty=not not dirty
      for _,cargo in ipairs(ordered) do
        dirty=step_rating(cargo,Rules.goods(st,cargo),queue(st,cargo),dirty,rail_at)
      end
      return dirty
    end
    function B.step_rail_rating(st)
      local cargo=assert(st.freight_cargo)
      return step_rating(cargo,Rules.goods(st,cargo),Rules.queue(st,cargo),false,rail_at)
    end
    function B.timing(v)
      local q=assert(Rules.trucks[v.cargo]);return q.load_amount,q.age_ticks
    end
    function B.post_scan(scan)
      for _,r in ipairs(scan.deliveries) do
        if r.cargo=="goods" and r.units>0 then
          local site=s.sites[r.town]
          if site then
            site.received=site.received or {}
            site.received.goods=(site.received.goods or 0)+r.units
          end
        end
        if r.cargo~="goods" then
          for _,d in ipairs(r.industries) do
            local ind=industry_at[d.id]
            if ind and d.units>0 then
              ind.received=ind.received or {}
              ind.received[r.cargo]=(ind.received[r.cargo] or 0)+d.units
              local site=s.sites[ind.site]
              if site then
                site.received=site.received or {}
                site.received[r.cargo]=(site.received[r.cargo] or 0)+d.units
              end
            end
          end
        end
      end
      return scan
    end
    function B.ops(tick,emit)
      local function event(kind,st,v,p)
        if emit then emit(kind,st,v,p) end
      end
      local function carrier(v,st)
        local id=options.cargo_tile and options.cargo_tile(s,v,st) or
          (v.mode=="ship" and v.cargo_tile) or v.road_stop_pose and v.road_stop_pose[4]
        assert(id and s.tiles[id],profile.label.." cargo requires the real occupied station tile")
        return {id=st.id,tile=id}
      end
      return {
        pickup=function(st,v,p) Packets.pickup(p,carrier(v,st),xy) end,
        drop=function(st,v,p) Packets.drop(p,carrier(v,st),xy) end,
        accepts=function(st,v)return B.report(st,v.cargo,tick).accepts end,
        queue=function(st,v)return queue(st,v.cargo) end,
        can_load=function(st,v)
          if st.owner~=options.neutral_owner then return true end
          local r=options.town_rights and options.town_rights(st.town or st.site)
          return not r or (r.exclusive_counter or 0)==0 or r.exclusivity==v.owner
        end,
        attempt=function(st,v,capacity)
          local q=Rules.trucks[v.cargo]
          local speed,age
          if v.mode=="ship" then
            speed,age=v.cached_max_speed,Sim.date(s)-assert(v.built)
          else
            speed,age=Sim.vehicles[v.engine].display_speed or floor(q.speed/2),Sim.date(s)-Sim.date(s,v.bought or s.day)
          end
          Rating.observe_loading(Rules.goods(st,v.cargo),speed,age,capacity)
        end,
        loaded=function(st,v,n)
          if v.mode=="ship" then st.time_since_load=0;st.last_vehicle_type="ship"
          else Station.loaded(st) end
          st.last_service=st.last_service or {};st.last_service[v.cargo]=s.day
          event("board",st,v,{units=n})
        end,
        transferred=function(st,v)
          local g=Rules.goods(st,v.cargo)
          if not g.has_rating then g.has_rating=true;g.time_since_pickup=0 end
        end,
        unloaded=function(st) Station.unloaded(st) end,
        transfer_income=function(st,v,p)
          local q=Rules.cargo[v.cargo]
          local price=options.current_payment and options.current_payment(s,tick,v.cargo) or q.payment
          return Income.regular(p.units,Packets.distance(p,carrier(v,st).tile,xy),p.age or 0,price,q.days1,q.days2)
        end,
        deliver=function(st,v,p)
          local l=assert(v.load_state)
          local seq=(l[seq_key] or 0)+1
          local token=table.concat({v.id,assert(l.arrived_tick),seq},":")
          local receipt,why=raw.stage(st.id,tick,token,p,carrier(v,st).tile)
          assert(receipt,why)
          l[seq_key]=seq
          l[accepted_key]=(l[accepted_key] or 0)+receipt.units
          return receipt.payment
        end,
        payment=function(st,v,p)
          local l=assert(v.load_state)
          local n=l[accepted_key] or 0
          l[accepted_key]=nil
          assert(n<=p.delivered)
          if n>0 then
            local c=Sim.company(s,v.owner)
            if options.credit then options.credit(c,p.route)
            else c.cash,c.revenue,c.month_rev=c.cash+p.route,c.revenue+p.route,c.month_rev+p.route end
            c.units,c.paid_units=c.units+n,c.paid_units+n
            v.delivered,v.revenue=v.delivered+n,v.revenue+p.route
            event("fare",st,v,{units=n,amount=p.route})
          end
          v.stock_profit_with_feeders=(v.stock_profit_with_feeders or 0)+p.visual+p.transfer
        end,
        station_done=function(st)
          local scan,why=raw.finish(st.id,tick)
          if not scan then assert(why=="NO_PENDING_STATION_SCAN",why);return end
          return B.post_scan(scan)
        end,
      }
    end
    return B
  end
  return R
end
