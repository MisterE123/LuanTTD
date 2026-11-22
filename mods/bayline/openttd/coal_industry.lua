-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, OpenTTD 14.1: table/build_industry.h, table/engines.h,
-- industry_cmd.cpp, landscape.cpp RunTileLoop, station.cpp/station_cmd.cpp,
-- economy.cpp and table/cargo_const.h. Ordinary temperate stock, no NewGRFs.
-- Bedrock, industry funding/location validation and overall industry spawning
-- are host concerns. This module operates on the actual occupied layout tiles,
-- with manual-distribution cargo and explicitly supplied RNG/clock events.
return function(Packets,Rating,Catchment,Income)
  local C={PRODUCE_TICKS=256,MIN_CARGO=5,PRODLEVEL_DEFAULT=16,PRODLEVEL_MIN=4,PRODLEVEL_MAX=128}
  local floor,ceil,abs,max,min=math.floor,math.ceil,math.abs,math.max,math.min
  C.mine_layouts={
    [0]={{1,1,0},{1,2,2},{0,0,5},{1,0,6},{2,0,3},{2,2,3}},
    {{1,1,0},{1,2,2},{2,0,0},{2,1,2},{1,0,3},{0,0,3},{0,1,4},{0,2,4},{2,2,4}},
    {{0,0,0},{0,1,2},{0,2,5},{1,0,3},{1,1,3},{1,2,6}},
    {{0,1,0},{0,2,2},{0,3,4},{1,0,5},{1,1,0},{1,2,2},{1,3,3},{2,0,6},{2,1,4},{2,2,3}},
  }
  C.power_layouts={
    [0]={{0,0,7},{0,1,9},{1,0,7},{1,1,8},{2,0,7},{2,1,8},{3,0,10},{3,1,10}},
    {{0,1,7},{0,2,7},{1,0,8},{1,1,8},{1,2,7},{2,0,9},{2,1,10},{2,2,9}},
    {{0,0,7},{0,1,7},{1,0,9},{1,1,8},{2,0,10},{2,1,9}},
  }
  C.spec={
    coal_mine={id=0,life="extractive",rate=15,minimum=5,build_cost_factor=210,procurement_probability=0xB3333333},
    power_station={id=1,life="black_hole",accepts="coal",input_multiplier=256,
      minimum=5,build_cost_factor=240,procurement_probability=0xFFFFFFFF},
  }
  C.cargo={id=1,label="COAL",class="bulk",weight_16=16,capacity_multiplier=256,payment=5916,days1=7,days2=255}
  C.truck={id=123,road_index=7,name="Balogh Coal Truck",intro_days_after_1920=5479,decay_speed=20,
    life_years=15,base_life_years=55,cargo="coal",image_index=1,buy_factor=108,running_factor=90,
    speed=96,display_speed=48,capacity=20,climates={temperate=true,arctic=true},weight_quarters=38,power_tens_hp=12,
    tractive_effort=76,air_drag=0,load_amount=5,cargo_age_ticks=185,roadtype=0}

  local function chance(denominator,u32)
    return floor(((u32%65536)*denominator+floor(denominator/2))/65536)<1
  end
  local function range(limit,u32)
    return floor(u32*limit/4294967296)
  end
  C.chance=chance
  function C.scale(amount,percentage,random)
    percentage=percentage or 100
    assert(percentage>0)
    if amount==0 or percentage==100 then return amount end
    local n=floor(amount*percentage/100)
    if n==0 and random and chance(max(floor(100/percentage),1),random()) then return 1 end
    return n
  end
  local function history() return {production=0,transported=0} end
  function C.new(kind,id,x,z,opts)
    opts=opts or {}
    local spec=assert(C.spec[kind],"Unknown temperate coal industry")
    local layout=opts.layout or 0
    local tiles=assert((kind=="coal_mine" and C.mine_layouts or C.power_layouts)[layout])
    local rec={kind=kind,id=id,x=x,z=z,layout=layout,tiles={},counter=opts.counter or
      floor((opts.initial_random or 16)%65536/16),prod_level=16,
      last_prod_year=opts.economy_year,exclusive_consumer=opts.exclusive_consumer,
      exclusive_supplier=opts.exclusive_supplier,owner=opts.owner}
    for i,t in ipairs(tiles) do
      rec.tiles[i]={x=x+t[1],z=z+t[2],gfx=t[3],
        completed=opts.completed==true,stage=opts.completed==true and 3 or opts.generating_world and 2 or 0,
        construction_counter=opts.completed~=true and opts.generating_world and 3 or 0}
    end
    if spec.rate then
      local r=spec.rate
      if not opts.original and opts.production_random then
        r=min(255,floor((128+range(256,opts.production_random))*r/256))
      end
      rec.produced={rate=r,waiting=0,current=history(),last=history()}
      if opts.generating_world then rec.produced.last.production=C.scale(r*8,opts.scale,opts.random_u32) end
    else rec.accepted={waiting=0} end
    return rec
  end

  function C.production_tick(ind,opts)
    opts=opts or {}
    if opts.editor or ind.removed then return 0 end
    -- The ambient Chance16R samples even for a spec having no sounds.
    if ind.counter%64==0 and opts.ambient_rng then opts.ambient_rng() end
    ind.counter=(ind.counter-1)%65536
    local p=ind.produced
    if not p or ind.counter%256~=0 then return 0 end
    local before=p.waiting
    p.waiting=min(65535,before+C.scale(p.rate,opts.scale,opts.random_u32))
    return p.waiting-before
  end

  -- Landscape tile-loop order (the host can use an exact square stock map
  -- or a larger virtual power-of-two landscape with untouched void tiles).
  local feedback={0xD8F,0x1296,0x2496,0x4357,0x8679,0x1030E,0x206CD,0x403FE,
    0x807B8,0x1004B2,0x2006A8,0x4004B2,0x800B87}
  local function xor(a,b)
    local n,p=0,1
    while a~=0 or b~=0 do
      if a%2~=b%2 then n=n+p end
      a,b,p=floor(a/2),floor(b/2),p*2
    end
    return n
  end
  function C.landscape_tick(clock,log_x,log_z,dispatch)
    assert(log_x>=6 and log_x<=12 and log_z>=6 and log_z<=12)
    local log=log_x+log_z
    local f=assert(feedback[log-11])
    local left=2^(log-8)
    local tile=clock.cursor
    assert(tile>0 and tile<2^log)
    if clock.tick%256==0 then dispatch(0);left=left-1 end
    for i=1,left do
      dispatch(tile)
      local shifted=floor(tile/2)
      if tile%2==1 then tile=xor(shifted,f) else tile=shifted end
    end
    clock.cursor=tile
  end

  -- Producing is not distributing. Construction still progresses before
  -- the editor check, and the tile completing this loop does not distribute
  -- until its next loop. Commodity recession shrinks the drained batch.
  function C.tile_loop(ind,t,opts,offer)
    opts=opts or {}
    if ind.removed then return 0,0 end
    if not t.completed then
      t.construction_counter=(t.construction_counter or 0)+1
      if t.construction_counter==4 then
        t.construction_counter=0
        t.stage=(t.stage or 0)+1
        if t.stage==3 then t.completed=true end
      end
      return 0,0
    end
    local p=ind.produced
    if opts.editor or not p then return 0,0 end
    local amount=min(255,p.waiting)
    if amount<=C.MIN_CARGO then return 0,0 end
    p.waiting=p.waiting-amount
    if opts.recession then amount=floor((amount+1)/2) end
    p.current.production=(p.current.production+amount)%65536
    local shipped=offer and offer(ind,amount) or 0
    p.current.transported=(p.current.transported+shipped)%65536
    return amount,shipped
  end

  local function cargo_facility(c)
    local f=c.facilities
    for k,on in pairs(f) do if k~="bus" and on then return true end end
    return false
  end
  function C.acceptance(st,c,industries)
    local raw,near=0,{}
    for _,ind in ipairs(industries) do
      if not ind.removed and ind.accepted then
        local distance
        for _,t in ipairs(ind.tiles) do
          if Catchment.contains(c,t.x,t.z) then
            if t.gfx==8 then raw=raw+8 end -- AddAcceptedCargo_Industry does not check completion
            local d=max(abs(st.x-t.x),abs(st.z-t.z))
            distance=distance and min(distance,d) or d
          end
        end
        if distance then near[#near+1]={ind=ind,distance=distance} end
      end
    end
    table.sort(near,function(a,b) return a.distance<b.distance or a.distance==b.distance and a.ind.id<b.ind.id end)
    local n=cargo_facility(c) and raw or 0
    return {raw_eighths=raw,eighths=n,demand=floor(n/8),accepts=n>=8,near=near}
  end
  function C.goods(st)
    st.goods=st.goods or {}
    st.goods.coal=st.goods.coal or Rating.new()
    return st.goods.coal
  end
  local function queue(st)
    st.stock=st.stock or {}
    st.stock.coal=st.stock.coal or {}
    return st.stock.coal
  end
  function C.waiting(st)
    local amount=0
    for _,p in ipairs(st.stock and st.stock.coal or {}) do amount=amount+p.units end
    return amount
  end
  function C.observe_loading(st,v,capacity_left,year)
    local speed=v.max_speed or C.truck.speed
    if v.mode==nil or v.mode=="road" then speed=floor(speed/2) end
    Rating.observe_loading(C.goods(st),speed,year-v.build_year,capacity_left)
  end

  -- Own frame phase is not stored here: stations share their ordinary
  -- 185-tick rating event across cargos. Call in cargo-index order after
  -- incrementing the station timers once. truncate is the stock manual
  -- packet-ring helper supplied by station_rating_runtime (pass it directly).
  function C.rating_tick(st,opts)
    local g=(opts.get_goods or C.goods)(st)
    local waiting=C.waiting(st)
    local r=Rating.step(g,{waiting=waiting,destinations=waiting>0 and 1 or 0,
      select_goods=opts.select_goods~=false,random_u32=opts.random_u32,
      ship=opts.ship,statue=opts.statue,cheat=opts.cheat,waiting_changed=opts.waiting_changed})
    g.rating,g.has_rating,g.time_since_pickup=r.rating,r.has_rating,r.time_since_pickup
    g.last_speed,g.last_age,g.max_waiting_cargo=r.last_speed,r.last_age,r.max_waiting_cargo
    if r.drop>0 then
      local retained=assert(opts.truncate,"Coal rating decay requires cargo truncation")(
        queue(st),waiting,r.drop,opts.random_u32)
      if opts.station_at then
        for id,n in pairs(retained) do
          local original=opts.station_at(id)
          if original then
            local og=(opts.get_goods or C.goods)(original)
            og.max_waiting_cargo=max(og.max_waiting_cargo,n)
          end
        end
      end
    end
    return r
  end

  -- An industry offers to every station covering *any actual footprint
  -- tile*, not just this particular output animation tile and not the
  -- bounding rectangle around it. Selective goods / company/town rights
  -- and per-cargo fractional residue are identical to MoveGoodsToStation.
  function C.distribute(mine,amount,stations,covers,opts)
    opts=opts or {}
    local cand,seen={},{}
    for _,st in ipairs(stations) do
      local c=covers[st.id]
      if c and not seen[st.id] and cargo_facility(c) and
          (mine.exclusive_consumer==nil or mine.exclusive_consumer==st.owner) then
        seen[st.id]=true
        local rights=opts.town_rights and opts.town_rights(st.town)
        local neutral=st.owner==nil or st.owner==opts.neutral_owner
        if neutral or not rights or (rights.exclusive_counter or 0)==0 or rights.exclusivity==st.owner then
          local covers_ind=false
          for _,t in ipairs(mine.tiles) do
            if Catchment.contains(c,t.x,t.z) then covers_ind=true; break end
          end
          if covers_ind then
            local g=(opts.get_goods or C.goods)(st)
            if g and g.rating>0 and (opts.select_goods==false or Rating.has_tried_loading(g)) then
              cand[#cand+1]={st={id=st.id,owner=st.owner or false},source=st,g=g,rating=g.rating}
            end
          end
        end
      end
    end
    table.sort(cand,function(a,b) return a.st.id<b.st.id end)
    Packets.allocate(amount,cand)
    local moved=0
    for _,it in ipairs(cand) do
      local st,g=it.source,it.g
      if it.fixed and (not opts.packet_allocatable or opts.packet_allocatable(st)) then
        local total=(g.amount_fract or 0)+it.fixed
        g.amount_fract=total%256
        local whole=floor(total/256)
        if whole>0 then
          local p={cargo="coal",source_type="industry",source=mine.id,origin_station=st.id,
            origin_tile=st.tile,units=whole,age=0,day=opts.day}
          local q=queue(st)
          q[#q+1]=p
          Rating.observe_waiting(g,whole)
          moved=moved+whole
        end
      end
    end
    return moved,cand
  end

  -- Manual pickup reuses exact origin/travel packet bookkeeping. Host
  -- controls progressive loading cadence, order restrictions and motion.
  function C.pickup(st,room,xy)
    local out,got={},0
    local q=queue(st)
    while room>0 and #q>0 do
      local p=q[1]
      local n=min(room,p.units)
      if n==p.units then table.remove(q,1) else p=Packets.split(p,n) end
      Packets.pickup(p,st,xy)
      out[#out+1]=p
      room,got=room-n,got+n
    end
    return out,got
  end
  function C.delivery(st,acceptance,p,opts)
    opts=opts or {}
    if not acceptance.accepts or not Packets.accept_at(p,st) or opts.transfer or opts.no_unload then
      return {accepted=0,payment=0,remaining=p.units,plants={}}
    end
    local remaining,plants=p.units,{}
    local source=p.source_type=="industry" and p.source or nil
    for _,t in ipairs(acceptance.near) do
      if remaining==0 then break end
      local i=t.ind
      if not i.removed and i.id~=source and i.accepted and
          (i.exclusive_supplier==nil or i.exclusive_supplier==st.owner) and
          (not opts.refused or not opts.refused(i)) then
        local n=min(remaining,65535-i.accepted.waiting)
        i.accepted.waiting=i.accepted.waiting+n
        i.accepted.last_accepted=opts.date
        plants[#plants+1]={industry=i,amount=n}
        remaining=remaining-n
      end
    end
    local accepted=p.units-remaining
    local money=0
    if accepted>0 then
      local distance=opts.distance or Packets.distance(p,st.tile,assert(opts.xy,"Delivery coordinates required"))
      money=Income.regular(accepted,distance,p.age or 0,opts.current_payment or C.cargo.payment,
        C.cargo.days1,C.cargo.days2)
      local g=(opts.get_goods or C.goods)(st)
      g.ever_accepted,g.current_month,g.accepted_bigtick=true,true,true
    end
    return {accepted=accepted,payment=money,remaining=remaining,plants=plants}
  end
  function C.trigger_delivery(result)
    for _,p in ipairs(result.plants) do
      local i=p.industry
      i.was_cargo_delivered=true
      i.accepted.waiting=0 -- TriggerIndustryProduction: consumes, not stores or produces electricity cargo
    end
  end

  function C.pct_transported(p)
    return p.last.production==0 and 0 or min(255,floor(p.last.transported*256/p.last.production))
  end
  function C.production_change(ind,opts)
    opts=opts or {}
    local p=ind.produced
    if not p or ind.removed then return end -- black-hole plants do not change/close
    local original=not not opts.original
    local monthly=not not opts.monthly
    if monthly==original or opts.frozen and not original then return end
    local rnd=assert(opts.random_u32,"Industry production change requires deterministic RNG")
    local rating=C.pct_transported(p)
    local close=false
    local old=p.rate
    if original then
      if chance(3,rnd()) then
        local increase=(rating>153)~=chance(3,rnd())
        if opts.external_prod_level or (increase and opts.no_increase) or (not increase and opts.no_decrease) then return end
        local level=ind.prod_level
        if increase then
          if level<C.PRODLEVEL_MAX then ind.prod_level=min(level*2,C.PRODLEVEL_MAX) end
        elseif level==C.PRODLEVEL_MIN then close=true
        else ind.prod_level=max(floor(level/2),C.PRODLEVEL_MIN) end
        if ind.prod_level~=level then p.rate=min(255,ceil(15*ind.prod_level/16)) end
      end
    else
      local r=rnd()
      local sign=rating>153 and 1 or -1
      if chance(rating>204 and 6 or 3,r) then sign=-sign end
      local rate=old
      if chance(22,floor(r/65536)) then rate=old+sign*max(floor((range(50,rnd())+10)*old/256),1) end
      rate=min(255,max(1,rate))
      if rate<old and opts.no_decrease or rate>old and opts.no_increase then return end
      p.rate=rate
      close=rate<=1 and not opts.no_decrease
    end
    if close and not opts.no_closure and not opts.closure_protected and (opts.industry_count or 2)>1 then
      ind.prod_level=0
      return "closure"
    end
    if p.rate~=old then return "rate",p.rate-old,old==0 and 100 or floor(p.rate*100/old)-100 end
  end
  function C.month(ind,year,opts)
    if ind.removed then return "removed" end
    local p=ind.produced
    if p then
      if p.current.production~=0 then ind.last_prod_year=year end
      p.last,p.current=p.current,history()
    end
    if ind.prod_level==0 then ind.removed=true;return "removed" end
    local settings={monthly=true}
    for k,v in pairs(opts or {}) do settings[k]=v end
    return C.production_change(ind,settings)
  end
  return C
end
