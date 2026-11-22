-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 temperate Forest #3 and Sawmill #2. Original
-- table/build_industry.h, industry_cmd.cpp, economy.cpp,
-- station_cmd.cpp, station.cpp and table/cargo_const.h.
return function(Packets,Catchment,Rating,Income,Commons,Houses)
  local T={TICKS=256,MAX_WAITING=65535,ABANDON_YEARS=5}
  local floor,ceil,min,max,abs=math.floor,math.ceil,math.min,math.max,math.abs
  local history=function() return {production=0,transported=0} end
  T.layout={
    sawmill={
      [0]={{1,0,14},{1,1,12},{1,2,11},{2,0,14},{2,1,13},{0,0,15},{0,1,15},{0,2,12}},
      {{0,0,15},{0,1,11},{0,2,14},{1,0,15},{1,1,13},{1,2,12},{2,0,11},{2,1,13}},
    },
    forest={
      [0]={{0,0,16},{0,1,16},{0,2,16},{0,3,16},{1,0,16},{1,1,16},{1,2,16},{1,3,16},
        {2,0,16},{2,1,16},{2,2,16},{2,3,16},{3,0,16},{3,1,16},{3,2,16},{3,3,16},{1,4,16},{2,4,16}},
      {{0,0,16},{1,0,16},{2,0,16},{3,0,16},{4,0,16},{0,1,16},{1,1,16},{2,1,16},{3,1,16},{4,1,16},
        {0,2,16},{1,2,16},{2,2,16},{3,2,16},{4,2,16},{0,3,16},{1,3,16},{2,3,16},{3,3,16},{4,3,16},
        {1,4,16},{2,4,16},{3,4,16}},
    },
  }
  T.spec={
    forest={id=3,output="wood",rate=13,minimum=30,life="organic",cost_factor=200,probability=0xBFFFFFFF,climates=3,sounds=0},
    sawmill={id=2,output="goods",rate=0,minimum=5,life="processing",cost_factor=224,probability=0xFFFFFFFF,
      climates=1,sounds=1,input="wood",multiplier=256},
  }
  T.cargo={
    wood={id=7,label="WOOD",payment=5005,days1=15,days2=255,weight_16=16,capacity_multiplier=256,class="piece_goods",town_effect="none"},
    goods={id=5,label="GOOD",payment=6144,days1=5,days2=28,weight_16=8,capacity_multiplier=512,class="express",town_effect="goods"},
  }
  T.trucks={
    goods={id=138,index=22,name="Balogh Goods Truck",cargo="goods",capacity=14,buy_factor=107,
      running_factor=90,speed=96,weight_quarters=38,power_tens_hp=12,intro_days_after_1920=5479,climates=7,
      load_amount=5,age_ticks=185},
    wood={id=144,index=28,name="Witcombe Wood Truck",cargo="wood",capacity=20,buy_factor=118,
      running_factor=90,speed=96,weight_quarters=38,power_tens_hp=12,intro_days_after_1920=5479,climates=7,
      load_amount=5,age_ticks=185},
  }
  local function as_list(map)
    local a={}
    for _,v in pairs(map or {}) do a[#a+1]=v end
    table.sort(a,function(l,r)return l.id<r.id end)
    return a
  end
  T.ordered=as_list
  local function option(t,name,default)
    if t[name]==nil then return default end
    return t[name]
  end
  function T.new(kind,id,x,z,opts)
    opts=opts or {}
    local p=assert(T.spec[kind],"Unknown temperate timber industry")
    local layout=opts.layout or 0
    local tiles=assert(T.layout[kind][layout],"Unknown layout")
    local ind={id=id,kind=kind,x=x,z=z,layout=layout,tiles={},
      counter=option(opts,"counter",floor((opts.initial_random or 16)%65536/16)),prod_level=16,
      last_prod_year=opts.economy_year or 0,exclusive_consumer=opts.exclusive_consumer,
      exclusive_supplier=opts.exclusive_supplier,was_cargo_delivered=false}
    for i,t in ipairs(tiles) do
      ind.tiles[i]={x=x+t[1],z=z+t[2],gfx=t[3],completed=not not opts.completed,
        stage=opts.completed and 3 or opts.generating_world and 2 or 0,
        construction_counter=not opts.completed and opts.generating_world and 3 or 0}
    end
    local rate=p.rate
    if not opts.original and opts.production_random then
      rate=min(255,floor((128+floor(opts.production_random*256/4294967296))*rate/256))
    end
    ind.produced={cargo=p.output,rate=rate,waiting=0,current=history(),last=history()}
    if opts.generating_world then
      ind.produced.last.production=Commons.scale(rate*8,opts.scale,opts.random_u32)
    end
    if p.input then ind.accepted={cargo=p.input,waiting=0} end
    return ind
  end

  -- Existing host calls this after station ratings and vehicle ticks.
  -- Both active industries consume the source ambient Random draw at
  -- the 64-counter boundary even if no sound is played.
  function T.production_tick(ind,opts)
    opts=opts or {}
    if opts.editor or ind.removed then return 0 end
    if ind.counter%64==0 and opts.random_u32 then
      local r=opts.random_u32()
      if T.spec[ind.kind].sounds>0 and Commons.chance(14,r) and ind.produced.last.production>0 and
          opts.ambient then opts.ambient(ind) end
    end
    ind.counter=(ind.counter-1)%65536
    if ind.counter%T.TICKS~=0 then return 0 end
    local p=ind.produced
    local old=p.waiting
    p.waiting=min(T.MAX_WAITING,old+Commons.scale(p.rate,opts.scale,opts.random_u32))
    return p.waiting-old
  end

  function T.tile_loop(ind,t,opts,offer)
    opts=opts or {}
    if ind.removed then return 0,0 end
    if not t.completed then
      t.construction_counter=(t.construction_counter+1)%4
      if t.construction_counter==0 then
        t.stage=t.stage+1
        if t.stage==3 then t.completed=true end
      end
      return 0,0
    end
    if opts.editor then return 0,0 end
    local spec=assert(T.spec[ind.kind])
    local p=ind.produced
    local n=min(p.waiting,255)
    local moved=0
    if n>spec.minimum then
      p.waiting=p.waiting-n
      if opts.recession then n=floor((n+1)/2) end
      p.current.production=(p.current.production+n)%65536
      moved=offer and offer(ind,p.cargo,n) or 0
      assert(moved>=0 and moved<=n)
      p.current.transported=(p.current.transported+moved)%65536
    else n=0 end
    -- Stock completed forest tile: successful delivery starts gfx 17;
    -- on a subsequent visit it goes back to the ordinary tree graphics.
    if t.gfx==16 and moved>0 then t.gfx=17
    elseif t.gfx==17 then t.gfx=16 end
    return n,moved
  end

  function T.goods(st,cargo)
    assert(T.cargo[cargo],"Unsupported timber-chain cargo")
    st.goods=st.goods or {}
    local g=st.goods[cargo]
    if not g then g=Rating.new();st.goods[cargo]=g end
    return g
  end
  function T.queue(st,cargo)
    assert(T.cargo[cargo],"Unsupported timber-chain cargo")
    st.stock=st.stock or {}
    st.stock[cargo]=st.stock[cargo] or {}
    return st.stock[cargo]
  end
  local function freight(cover)
    for k,on in pairs(cover.facilities) do if on and k~="bus" then return true end end
    return false
  end
  local function covered(cover,ind)
    local n=0
    for _,tile in ipairs(ind.tiles) do if Catchment.contains(cover,tile.x,tile.z) then n=n+1 end end
    return n>0
  end
  function T.distribute(ind,cargo,amount,stations,covers,opts)
    opts=opts or {}
    assert(ind.produced.cargo==cargo and amount>=0 and amount%1==0)
    if amount==0 then return 0,{} end
    local used,seen={},{}
    for _,st in ipairs(stations) do
      local c=covers[st.id]
      if not seen[st.id] and c and freight(c) and
          (ind.exclusive_consumer==nil or ind.exclusive_consumer==st.owner) and covered(c,ind) then
        seen[st.id]=true
        local r=st.owner~=opts.neutral_owner and opts.town_rights and opts.town_rights(st.town)
        if not r or (r.exclusive_counter or 0)==0 or r.exclusivity==st.owner then
          local g=T.goods(st,cargo)
          if g.rating>0 and (opts.select_goods==false or Rating.has_tried_loading(g)) then
            used[#used+1]={st={id=st.id,owner=st.owner or false},station=st,g=g,rating=g.rating}
          end
        end
      end
    end
    table.sort(used,function(a,b)return a.st.id<b.st.id end)
    Packets.allocate(amount,used)
    local moved=0
    for _,v in ipairs(used) do
      if v.fixed and (not opts.packet_allocatable or opts.packet_allocatable(v.station,cargo)) then
        local g,st=v.g,v.station
        local total=(g.amount_fract or 0)+v.fixed
        g.amount_fract=total%256
        local units=floor(total/256)
        if units>0 then
          local q=T.queue(st,cargo)
          local merged=false
          for i=#q,1,-1 do
            local p=q[i]
            if p.origin_station==st.id and p.origin_tile==nil and (p.age or 0)==0 and p.source_type=="industry"
                and p.source==ind.id and p.units+units<=65535 then
              p.units=p.units+units;merged=true;break
            end
          end
          if not merged then q[#q+1]={cargo=cargo,source_type="industry",source=ind.id,origin_station=st.id,units=units,age=0} end
          Rating.observe_waiting(g,units)
          moved=moved+units
        end
      end
    end
    return moved,used
  end

  function T.acceptance(st,cover,cargo,industries,house_at)
    local raw,always,near,towns=0,false,{},{}
    if cargo=="wood" then
      for _,ind in pairs(industries) do
        if not ind.removed and ind.accepted and ind.accepted.cargo=="wood" then
          local distance
          for _,tile in ipairs(ind.tiles) do
            if Catchment.contains(cover,tile.x,tile.z) then
              if tile.gfx==13 then raw=raw+8 end
              local d=max(abs(st.x-tile.x),abs(st.z-tile.z))
              distance=distance and min(d,distance) or d
            end
          end
          if distance then near[#near+1]={id=ind.id,distance=distance} end
        end
      end
      table.sort(near,function(a,b) return a.distance<b.distance or a.distance==b.distance and a.id<b.id end)
    else
      assert(cargo=="goods")
      for key in pairs(cover.tiles) do
        local house=house_at and house_at(key%cover.width,floor(key/cover.width))
        if house then
          local n=assert(Houses.house_acceptance(house.id),"Unknown stock house ID")
          raw=raw+n
          if n>0 then
            always=true
            if house.town~=nil then towns[house.town]=(towns[house.town] or 0)+n end
          end
        end
      end
    end
    local n=freight(cover) and raw or 0
    return {raw_eighths=raw,eighths=n,accepts=n>=8,demand=floor(n/8),
      always_accepted=always,near=near,house_eighths_by_town=towns}
  end

  -- Actual loading controller has already staged this packet for final
  -- delivery, not transfer. This accepts against the station's current
  -- GES_ACCEPTANCE snapshot; an industry may still be absent or refuse.
  function T.deliver(st,report,packet,industry_at,opts)
    opts=opts or {}
    local spec=assert(T.cargo[packet.cargo])
    local left=packet.units
    local out={units=0,payment=0,remaining=left,industries={},town=st.town,cargo=packet.cargo}
    if not report.accepts or not Packets.accept_at(packet,st) or opts.transfer or opts.no_unload then return out end
    if packet.cargo=="wood" then
      local src=packet.source_type=="industry" and packet.source
      for _,candidate in ipairs(report.near) do
        if left==0 then break end
        local i=industry_at(candidate.id)
        if i and not i.removed and i.id~=src and i.accepted and i.accepted.cargo=="wood" and
            (i.exclusive_supplier==nil or i.exclusive_supplier==st.owner) and
            (not opts.refuses or not opts.refuses(i,"wood")) then
          local n=min(left,T.MAX_WAITING-i.accepted.waiting)
          i.accepted.waiting=i.accepted.waiting+n
          i.accepted.last_accepted=opts.economy_date
          left=left-n
          -- Source includes qualifying processors even if they are full.
          out.industries[#out.industries+1]={id=i.id,units=n}
        end
      end
    else
      if report.always_accepted then left=0 end
    end
    local n=packet.units-left
    if n>0 then
      local g=T.goods(st,packet.cargo)
      g.ever_accepted,g.current_month,g.accepted_bigtick=true,true,true
      local dist=opts.distance
      if dist==nil then dist=Packets.distance(packet,assert(opts.cargo_tile),assert(opts.xy)) end
      out.distance,out.age=dist,packet.age or 0
      out.payment=Income.regular(n,dist,out.age,opts.current_payment or spec.payment,spec.days1,spec.days2)
    end
    out.units,out.remaining=n,left
    return out
  end

  function T.trigger(ind)
    if ind.removed or not ind.accepted then return 0,0 end
    local s=assert(T.spec[ind.kind])
    local inputs,out=ind.accepted,ind.produced
    ind.was_cargo_delivered=true
    local used=inputs.waiting
    local before=out.waiting
    out.waiting=min(T.MAX_WAITING,before+floor(used*s.multiplier/256))
    inputs.waiting=0
    return out.waiting-before,used
  end

  function T.change(ind,year,opts)
    opts=opts or {}
    if ind.removed or ind.prod_level==0 or (not not opts.monthly)==(not not opts.original) or
        (opts.frozen and not opts.original) then return end
    local p,close,old=ind.produced,false,ind.produced.rate
    local rnd=opts.random_u32
    if ind.kind=="forest" then
      local pct=Commons.pct_transported(p)
      if opts.original then
        if Commons.chance(3,assert(rnd)()) then
          local increase=(pct>153)~=Commons.chance(3,rnd())
          if (increase and opts.no_increase) or (not increase and opts.no_decrease) or opts.external_prod_level then return end
          local lvl=ind.prod_level
          if increase then ind.prod_level=min(128,lvl*2)
          elseif lvl==4 then close=true
          else ind.prod_level=max(4,floor(lvl/2)) end
          if lvl~=ind.prod_level then p.rate=min(255,ceil(T.spec.forest.rate*ind.prod_level/16)) end
        end
      else
        local r=assert(rnd)()
        local mult=pct>153 and 1 or -1
        if Commons.chance(pct>204 and 6 or 3,r) then mult=-mult end
        local rate=old
        if Commons.chance(22,floor(r/65536)) then
          rate=rate+mult*max(floor((floor(rnd()*50/4294967296)+10)*old/256),1)
        end
        rate=min(255,max(1,rate))
        if (rate<old and opts.no_decrease) or (rate>old and opts.no_increase) then return end
        p.rate=rate
        close=rate<=1 and not opts.no_decrease
      end
    elseif year-ind.last_prod_year>=T.ABANDON_YEARS then
      close=Commons.chance(opts.original and 2 or 180,assert(rnd)())
    end
    if close and not opts.no_closure and not opts.closure_protected then
      ind.prod_level=0
      return "closure"
    end
    if p.rate~=old then return "rate",p.rate-old,old==0 and 100 or floor(p.rate*100/old)-100 end
  end

  function T.month(ind,year,opts)
    if ind.removed then return "removed" end
    local p=ind.produced
    if p.current.production~=0 then ind.last_prod_year=year end
    p.last,p.current=p.current,history()
    if ind.prod_level==0 then ind.removed=true;return "removed" end
    local o={monthly=true}
    for k,v in pairs(opts or {}) do o[k]=v end
    return T.change(ind,year,o)
  end
  return T
end
