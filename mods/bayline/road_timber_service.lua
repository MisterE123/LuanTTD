-- SPDX-License-Identifier: GPL-2.0-only
-- Pinned 14.1 Forest -> Sawmill -> Town Goods on the ordinary road
-- station loader. Stock timing/economy remains in the shared kernels.
return function(Sim,Rules,Adapter,Packets,Income,Rating,Station)
  local R={}
  local pairs_by_cargo={wood="wood_truck",goods="goods_truck"}
  local ordered={"goods","wood"} -- CargoID 5 then 7.
  local floor,max=math.floor,math.max
  function R.supported_vehicle(v)
    return v and pairs_by_cargo[v.cargo]~=nil and pairs_by_cargo[v.cargo]==v.engine or false
  end
  function R.truck_stop(st) return st and st.mode=="road" and st.stop_type=="truck" end
  function R.bind(s,options)
    options=options or {}
    local xy=options.xy or Sim.xy
    local industry_at=s.stock_timber_industries or {}
    local harvest_cells={}
    for _,i in pairs(industry_at) do
      if i.kind=="forest" and not i.removed then
        for _,p in ipairs(i.tiles) do harvest_cells[p.z*Sim.W+p.x]=p end
      end
    end
    local stations,by_id={},{}
    for _,st in pairs(s.stations) do
      if R.truck_stop(st) then
        local x,z=xy(st.tile)
        st.stock_timber=st.stock_timber or {}
        st.goods=st.goods or {}
        local point={id=st.id,st=st,tile=st.tile,x=x-1,z=z-1,town=st.town or st.site,owner=st.owner,
          stock=st.stock_timber,goods=st.goods,tiles={{x=x-1,y=z-1,kind="truck"}}}
        stations[#stations+1]=point;by_id[st.id]=point
      end
    end
    table.sort(stations,function(a,b)return a.id<b.id end)
    local function house_at(x,z)
      local id=Sim.id(x+1,z+1)
      local t=id and s.tiles[id]
      return t and t.house and t.source_house or nil
    end
    local function random() return (options.random_u32 or Station.random_u32)(s) end
    local B,raw={},nil
    local function refresh(st,tick,big_tick)
      -- Source UpdateStationAcceptance at construction and the spread
      -- big tick (TimerGameTick::counter + StationID) % 250 == 0.
      local saved=st.timber_acceptance
      if not saved or saved.topology~=s.topology or
          big_tick and (tick+st.id)%250==0 and saved.tick~=tick then
        saved={topology=s.topology,tick=tick,reports={}}
        for _,cargo in ipairs(ordered) do saved.reports[cargo]=raw.report(st.id,cargo) end
        st.timber_acceptance=saved
      end
      return saved.reports
    end
    s.timber_transactions=s.timber_transactions or Adapter.new()
    local function open(scan_stations,coverage)
      assert(not raw,"The timber chain must have one shared station scan")
      raw=Adapter.bind(s,s.timber_transactions,{width=Sim.W,height=Sim.H,xy=xy,coverage=coverage,
        stations=scan_stations,industries=industry_at,house_at=options.house_at or house_at,
        random_u32=random,acceptance=function(st,cargo,tick)
          if by_id[st.id] then return refresh(st.st,tick)[cargo] end
          if cargo==st.freight_cargo then return st.acceptance end
        end,
        select_goods=s.stock_select_goods~=false,neutral_owner=options.neutral_owner,
        town_rights=options.town_rights,modified=options.modified_catchment,refuses=options.refuses,
        opts={current_payment=options.current_payment,scale=options.scale,economy_date=function(world)return world.day end}})
      function raw.report_with_sources(id,cargo)
        local r=raw.report(id,cargo)
        if not r then return end
        r.sources={}
        for _,ind in ipairs(raw.industries) do
          if not ind.removed and ind.produced.cargo==cargo then
            for _,tile in ipairs(ind.tiles) do
              if raw.covered(id,tile.x,tile.z) then r.sources[#r.sources+1]=ind.id;break end
            end
          end
        end
        return r
      end
      return raw
    end
    if options.station_union then
      B.rail=options.station_union(stations,open,function(scan) return B.post_scan(scan) end,
        function(st) return B.step_rail_rating(st) end)
      assert(raw,"The timber station union did not open the shared ledger")
    else open(stations) end
    B.stations,B.industries=stations,raw.industries
    function B.report(st,cargo,tick)
      if not (by_id[st.id] and Rules.cargo[cargo]) then return {accepts=false,eighths=0} end
      return refresh(st,tick)[cargo]
    end
    function B.tile_visit(x,z,tick)
      local forest=harvest_cells[z*Sim.W+x]
      local gfx=forest and forest.gfx
      local lot,moved,why=raw.tile_visit(x,z,tick)
      if gfx and forest.gfx~=gfx then
        s.changed=s.changed or {}
        s.changed[#s.changed+1]=assert(Sim.id(x+1,z+1))
      end
      return lot,moved,why
    end
    function B.after_vehicle_tick(tick)
      for _,p in ipairs(stations) do refresh(p.st,tick,true) end
      for _,i in ipairs(raw.industries) do raw.produce(i.id,tick) end
    end
    function B.month(ordinal,year,opts)
      local out={}
      for _,i in ipairs(raw.industries) do
        local kind,delta,percent=raw.month(i.id,ordinal,year,opts)
        if kind then out[#out+1]={id=i.id,kind=kind,change=delta,percent=percent} end
      end
      return out
    end
    local function queue(st,cargo)
      local p=assert(by_id[st.id],"Timber cargo requires a real truck stop")
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
    local function rate(g,stock,cargo,dirty)
      local n=0
      for _,p in ipairs(stock) do n=n+p.units end
      local p=Rating.step(g,{waiting=n,destinations=n>0 and 1 or 0,select_goods=s.stock_select_goods~=false,
        random_u32=random,waiting_changed=dirty})
      for _,k in ipairs({"rating","has_rating","time_since_pickup","last_speed","last_age","max_waiting_cargo"}) do g[k]=p[k] end
      if p.drop>0 then
        for id,count in pairs(Station.truncate(stock,n,p.drop,random)) do
          local src=s.stations[id]
          src=R.truck_stop(src) and src or B.rail and B.rail.station_at(id)
          if src then
            local g0=Rules.goods(src,cargo)
            g0.max_waiting_cargo=max(g0.max_waiting_cargo,count)
          end
        end
      end
      return p.waiting_changed
    end
    function B.step_rating(st,dirty)
      if not by_id[st.id] then return dirty end
      dirty=not not dirty
      for _,cargo in ipairs(ordered) do dirty=rate(Rules.goods(st,cargo),queue(st,cargo),cargo,dirty) end
      return dirty
    end
    function B.step_rail_rating(st)
      assert(st.freight_cargo=="goods")
      return rate(Rules.goods(st,"goods"),Rules.queue(st,"goods"),"goods",false)
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
        if r.cargo=="wood" then
          for _,d in ipairs(r.industries) do
            local ind=industry_at[d.id]
            if ind and d.units>0 then
              ind.wood_received=(ind.wood_received or 0)+d.units
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
      local function actual_tile(v,st)
        local f=v.road_stop_pose
        return f and f[4] or st.tile
      end
      return {
        accepts=function(st,v)return B.report(st,v.cargo,tick).accepts end,
        queue=function(st,v)return queue(st,v.cargo) end,
        can_load=function(st,v)
          if st.owner~=options.neutral_owner then return true end
          local r=options.town_rights and options.town_rights(st.town or st.site)
          return not r or (r.exclusive_counter or 0)==0 or r.exclusivity==v.owner
        end,
        attempt=function(st,v,capacity)
          local q=Rules.trucks[v.cargo]
          Rating.observe_loading(Rules.goods(st,v.cargo),floor(q.speed/2),
            Sim.date(s)-Sim.date(s,v.bought or s.day),capacity)
        end,
        loaded=function(st,v,n)
          Station.loaded(st)
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
          return Income.regular(p.units,Packets.distance(p,actual_tile(v,st),xy),p.age or 0,price,q.days1,q.days2)
        end,
        deliver=function(st,v,p)
          local l=assert(v.load_state)
          local seq=(l.timber_packet_sequence or 0)+1
          local token=table.concat({v.id,assert(l.arrived_tick),seq},":")
          local receipt,why=raw.stage(st.id,tick,token,p,actual_tile(v,st))
          assert(receipt,why)
          l.timber_packet_sequence=seq
          l.timber_accepted=(l.timber_accepted or 0)+receipt.units
          return receipt.payment
        end,
        payment=function(st,v,p)
          local l=assert(v.load_state)
          local n=l.timber_accepted or 0
          l.timber_accepted=nil
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
