-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 ordinary temperate Farm (9) and Factory (6), original
-- build_industry.h, industry_cmd.cpp, economy.cpp, industry.h,
-- station.cpp, cargo_const.h and engines.h. No NewGRF callbacks.
local here=debug and debug.getinfo(1,"S").source:match("^@(.*/)")
local path=here or (core and core.get_modpath("luanttd_core").."/openttd/") or "mods/luanttd_core/openttd/"
local Arrival=dofile(path.."industry_production_arrival_rc1.lua")
local Delivery=dofile(path.."industry_delivery_rc1.lua")
local Layout=dofile(path.."stock_industry_layouts_rc1.lua")
return function(Packets,Catchment,Rating,Income,Commons,Timber)
  local F={TICKS=256,SLOTS=16,MAX_WAITING=65535,ABANDON_YEARS=5}
  local floor,ceil,min,max,abs=math.floor,math.ceil,math.min,math.max,math.abs
  local function range(limit,u32) return floor(limit*u32/4294967296) end
  local history=function() return {production=0,transported=0} end
  F.layout={farm=Layout[9],factory=Layout[6]}
  F.spec={
    farm={id=9,life="organic",minimum=5,cost_factor=250,procurement_probability=0xD9999999,
      climates=3,sounds=3,out={"grain","livestock"},rates={10,10},input={},multiplier={},
      plant_fields=true,plant_on_built=true,generation={9,9,0,0},appearance={2,4,0,0},map_colour=48},
    factory={id=6,life="processing",minimum=5,cost_factor=208,procurement_probability=0xFFFFFFFF,
      climates=1,sounds=1,out={"goods"},rates={0},input={"livestock","grain","steel"},multiplier={256,256,256},
      generation={5,0,0,0},appearance={2,0,0,0},map_colour=174},
  }
  F.cargo={
    livestock={id=4,label="LVST",class="piece_goods",payment=4322,days1=4,days2=18,weight_16=3,capacity_multiplier=256},
    goods={id=5,label="GOOD",class="express",payment=6144,days1=5,days2=28,weight_16=8,capacity_multiplier=512},
    grain={id=6,label="GRAI",class="bulk",payment=4778,days1=4,days2=40,weight_16=16,capacity_multiplier=256},
    steel={id=9,label="STEL",class="piece_goods",payment=5688,days1=7,days2=255,weight_16=16,capacity_multiplier=256},
  }
  F.trucks={
    livestock={id=135,index=19,image=4,name="Talbott Livestock Van",capacity=14,buy_factor=105,climates=3},
    grain={id=141,index=25,image=6,name="Hereford Grain Truck",capacity=20,buy_factor=114,climates=7},
    goods={id=138,index=22,image=5,name="Balogh Goods Truck",capacity=14,buy_factor=107,climates=7},
    steel={id=150,index=34,image=9,name="Balogh Steel Truck",capacity=15,buy_factor=112,climates=1},
  }
  for cargo,v in pairs(F.trucks) do
    v.cargo,v.speed,v.running_factor=cargo,96,90
    v.intro_days_after_1920,v.life,v.base_life,v.decay=5479,15,55,20
    v.weight_quarters,v.power_tens_hp,v.load_amount,v.age_ticks=38,12,5,185
  end
  local function keys(t)
    local a={};for k in pairs(t) do a[#a+1]=k end
    table.sort(a);return a
  end
  function F.ordered(map)
    local a={};for _,v in pairs(map or {}) do a[#a+1]=v end
    table.sort(a,function(l,r) return l.id<r.id end);return a
  end
  function F.output(ind,cargo)
    for _,p in ipairs(ind.produced) do if p.cargo==cargo then return p end end
  end
  function F.input(ind,cargo)
    for i,a in ipairs(ind.accepted) do if a.cargo==cargo then return a,i end end
  end
  function F.tile_acceptance(gfx,cargo)
    if gfx>=39 and gfx<=42 and (cargo=="livestock" or cargo=="grain" or cargo=="steel") then return 8 end
    if (gfx==33 or gfx==34) and cargo=="passenger" then return 1 end
    return 0
  end
  function F.cost(kind,raw_setting,base,raw_base)
    local s=assert(F.spec[kind])
    local raw=s.life=="extractive" or s.life=="organic"
    return floor((raw and raw_setting==1 and (raw_base or 8000000) or (base or 1000000))*s.cost_factor/256)
  end
  function F.new(kind,id,x,z,opts)
    opts=opts or {}
    local spec=assert(F.spec[kind],"Unknown stock farm or factory")
    local layout=opts.layout or 0
    local ind={id=id,kind=kind,x=x,z=z,layout=layout,selected_layout=layout+1,tiles={},
      width=1,height=1,produced={},accepted={},prod_level=16,last_prod_year=opts.economy_year or 0,
      exclusive_consumer=opts.exclusive_consumer,exclusive_supplier=opts.exclusive_supplier,
      was_cargo_delivered=false}
    local rnd=opts.random_u32
    for slot=1,F.SLOTS do
      local c,r=spec.out[slot] or false,spec.rates[slot] or 0
      -- The source consumes a draw for each of all 16 output slots
      -- in non-original economy, including invalid zero-rate rows.
      if opts.original==false then r=min(255,floor((128+range(256,assert(rnd)()))*r/256)) end
      ind.produced[slot]={cargo=c,rate=r,waiting=0,current=history(),last=history()}
      ind.accepted[slot]={cargo=spec.input[slot] or false,waiting=0}
    end
    local r=opts.initial_random or (rnd and rnd()) or 16
    ind.counter=opts.counter or floor(r%65536/16)
    ind.random_colour=r%16
    if opts.generating_world then
      for _,p in ipairs(ind.produced) do p.last.production=Commons.scale(p.rate*8,opts.scale,rnd) end
    end
    for i,t in ipairs(assert(F.layout[kind][layout],"Unknown stock industry layout")) do
      ind.tiles[i]={x=x+t[1],z=z+t[2],gfx=t[3],completed=not not opts.completed,
        stage=opts.completed and 3 or opts.generating_world and 2 or 0,
        construction_counter=not opts.completed and opts.generating_world and 3 or 0}
      if rnd and opts.seed_tile_random~=false then ind.tiles[i].random_bits=rnd()%256 end
      ind.width,ind.height=max(ind.width,t[1]+1),max(ind.height,t[2]+1)
    end
    return ind
  end

  -- Source Industry::OnTick. Caller owns global IndustryID order and
  -- provides a physical farm-field planting hook where there is a map.
  function F.production_tick(ind,opts,silent)
    opts=opts or {}
    if opts.editor or ind.removed then return 0 end
    local rnd=opts.random_u32
    local spec=F.spec[ind.kind]
    if ind.counter%64==0 and rnd then
      local r=rnd()
      if not silent and opts.ambient and Commons.chance(14,r) then
        for _,p in ipairs(ind.produced) do
          if p.last.production>0 then
            opts.ambient(ind,floor(floor(r/65536)*spec.sounds/65536)+1);break
          end
        end
      end
    end
    ind.counter=(ind.counter-1)%65536
    if ind.counter%F.TICKS~=0 then return 0 end
    local n=0
    for _,p in ipairs(ind.produced) do
      if p.cargo then
        local before=p.waiting
        p.waiting=min(F.MAX_WAITING,before+Commons.scale(p.rate,opts.scale,rnd))
        n=n+p.waiting-before
      end
    end
    if spec.plant_fields and rnd and Commons.chance(8,rnd()) and opts.field_attempt then
      opts.field_attempt(ind,rnd)
    end
    return n
  end
  function F.tile_loop(ind,tile,opts,offer)
    opts=opts or {}
    if ind.removed then return 0,0 end
    if not tile.completed then
      tile.construction_counter=(tile.construction_counter+1)%4
      if tile.construction_counter==0 then
        tile.stage=tile.stage+1
        if tile.stage==3 then tile.completed=true end
      end
      return 0,0
    end
    if opts.editor then return 0,0 end
    local threshold=F.spec[ind.kind].minimum
    local n,moved,detail=0,0,{}
    for _,p in ipairs(ind.produced) do
      local lot=min(p.waiting,255)
      if p.cargo and lot>threshold then
        p.waiting=p.waiting-lot
        if opts.recession then lot=floor((lot+1)/2) end
        p.current.production=(p.current.production+lot)%65536
        local sent=offer and offer(ind,p.cargo,lot) or 0
        assert(sent>=0 and sent<=lot)
        p.current.transported=(p.current.transported+sent)%65536
        n,moved=n+lot,moved+sent
        detail[#detail+1]={cargo=p.cargo,production=lot,transported=sent}
      end
    end
    return n,moved,detail
  end

  function F.goods(st,cargo)
    assert(F.cargo[cargo],"Unsupported farm-chain cargo")
    st.goods=st.goods or {}
    local g=st.goods[cargo]
    if not g then g=Rating.new();st.goods[cargo]=g end
    return g
  end
  function F.queue(st,cargo)
    assert(F.cargo[cargo],"Unsupported farm-chain cargo")
    st.stock=st.stock or {}
    st.stock[cargo]=st.stock[cargo] or {}
    return st.stock[cargo]
  end
  local function freight(c)
    for k,on in pairs(c.facilities) do if on and k~="bus" then return true end end
    return false
  end
  local function covered(c,ind)
    for _,t in ipairs(ind.tiles) do if Catchment.contains(c,t.x,t.z) then return true end end
    return false
  end
  function F.distribute(ind,cargo,amount,stations,covers,opts)
    opts=opts or {}
    assert(F.output(ind,cargo) and amount>=0 and amount%1==0)
    local candidates,seen={},{}
    if amount<=0 then return amount,candidates end
    for _,st in ipairs(stations) do
      local c=covers[st.id]
      if not seen[st.id] and c and freight(c) and covered(c,ind) and
          (ind.exclusive_consumer==nil or ind.exclusive_consumer==st.owner) then
        seen[st.id]=true
        local rights=opts.town_rights and st.owner~=opts.neutral_owner and opts.town_rights(st.town)
        if not rights or (rights.exclusive_counter or 0)==0 or rights.exclusivity==st.owner then
          local g=F.goods(st,cargo)
          if g.rating>0 and (opts.select_goods==false or Rating.has_tried_loading(g)) then
            candidates[#candidates+1]={st={id=st.id,owner=st.owner or false},station=st,g=g,rating=g.rating}
          end
        end
      end
    end
    table.sort(candidates,function(a,b) return a.st.id<b.st.id end)
    Packets.allocate(amount,candidates)
    local moved=0
    for _,v in ipairs(candidates) do
      if v.fixed and (not opts.packet_allocatable or opts.packet_allocatable(v.station,cargo)) then
        local g,st=v.g,v.station
        local total=(g.amount_fract or 0)+v.fixed
        g.amount_fract=total%256
        local units=floor(total/256)
        if units>0 then
          local q=F.queue(st,cargo)
          local merged=false
          for i=#q,1,-1 do
            local p=q[i]
            if p.origin_station==st.id and p.origin_tile==nil and (p.age or 0)==0 and p.source_type=="industry"
                and p.source==ind.id and p.units+units<=65535 then
              p.units=p.units+units;merged=true;break
            end
          end
          if not merged then
            q[#q+1]={cargo=cargo,source_type="industry",source=ind.id,origin_station=st.id,units=units,age=0}
          end
          Rating.observe_waiting(g,units)
          moved=moved+units
        end
      end
    end
    return moved,candidates
  end

  function F.acceptance(st,c,cargo,industries,house_at)
    if cargo=="goods" then return Timber.acceptance(st,c,cargo,{},house_at) end
    local raw,near=0,{}
    for _,ind in pairs(industries) do
      if not ind.removed and (F.input(ind,cargo) or cargo=="passenger") then
        local distance
        for _,t in ipairs(ind.tiles) do
          if Catchment.contains(c,t.x,t.z) then
            raw=raw+F.tile_acceptance(t.gfx,cargo)
            local d=max(abs(st.x-t.x),abs(st.z-t.z))
            distance=distance and min(distance,d) or d
          end
        end
        if distance and cargo~="passenger" then near[#near+1]={id=ind.id,distance=distance} end
      end
    end
    table.sort(near,function(a,b) return a.distance<b.distance or a.distance==b.distance and a.id<b.id end)
    local household=0
    if cargo=="food" and F.house_acceptance and house_at then
      for key in pairs(c.tiles) do
        local house=house_at(key%c.width,floor(key/c.width))
        if house then household=household+assert(F.house_acceptance(house.id,cargo),"Unknown house acceptance") end
      end
    end
    raw=raw+household
    local n=(cargo=="passenger" or freight(c)) and raw or 0
    return {raw_eighths=raw,eighths=n,accepts=n>=8,demand=floor(n/8),near=near,always_accepted=household>0}
  end

  -- Delivery accepts against station big-tick cache, then finds each
  -- live factory input separately; neither domestic Goods nor steel
  -- is approximated as farm output.
  function F.deliver(st,report,packet,industry_at,opts)
    opts=opts or {}
    local cargo=packet.cargo
    if cargo=="goods" then return Timber.deliver(st,report,packet,industry_at,opts) end
    local spec=assert(F.cargo[cargo])
    local left=packet.units
    local out={units=0,payment=0,remaining=left,industries={},town=st.town,cargo=cargo}
    if not report.accepts or not Packets.accept_at(packet,st) or opts.transfer or opts.no_unload then return out end
    local src=packet.source_type=="industry" and packet.source
    local accepted,industries=Delivery.to_industries(st,cargo,left,src,report.near,industry_at,F.input,opts)
    local n,household=Delivery.acceptance_split(left,accepted,report.always_accepted)
    left=left-n
    out.industries=industries
    if household>0 then out.town_units=household end
    if n>0 then
      local g=F.goods(st,cargo)
      g.ever_accepted,g.current_month,g.accepted_bigtick=true,true,true
      local dist=opts.distance
      if dist==nil then dist=Packets.distance(packet,assert(opts.cargo_tile),assert(opts.xy)) end
      out.distance,out.age=dist,packet.age or 0
      out.payment=Income.regular(n,dist,out.age,opts.current_payment or spec.payment,spec.days1,spec.days2)
    end
    out.units,out.remaining=n,left
    return out
  end

  local arrival_matrices=setmetatable({},{__mode="k"})
  -- Trigger once after a whole Station::LoadUnloadStation scan. Input
  -- slot order is source-stable and saturation always consumes accepted
  -- input even if the shared stockpile is already full.
  function F.trigger(ind)
    local scheme=F.spec[ind.kind]
    if ind.removed or not scheme or (scheme.life~="processing" and scheme.life~="black_hole") then return 0,0,{} end
    local output=ind.produced[1]
    local before=output.waiting
    local matrix=arrival_matrices[scheme]
    if not matrix then
      matrix={}
      for slot,value in ipairs(scheme.multiplier) do matrix[slot]={value} end
      arrival_matrices[scheme]=matrix
    end
    local used,details=Arrival.apply(ind,matrix)
    return output.waiting-before,used,details
  end

  -- Original random industry-change dispatch is selected by the host
  -- industry builder. Smooth updates are monthly, per valid cargo. The
  -- last original Farm and Factory are protected as in the stock count.
  function F.change(ind,year,opts)
    opts=opts or {}
    if ind.removed or (not not opts.monthly)==(not not opts.original) or
        (opts.frozen and not opts.original) then return end
    local close=false
    local changes={}
    local rnd=opts.random_u32
    local function record(p,rate)
      local old=p.rate
      p.rate=rate
      if rate~=old then
        changes[#changes+1]={cargo=p.cargo,before=old,rate=rate,
          percent=old==0 and 100 or floor(rate*100/old)-100}
      end
    end
    local spec=F.spec[ind.kind]
    if spec.life=="black_hole" then return end
    if spec.life~="processing" then
      if opts.original then
        if Commons.chance(3,assert(rnd)()) then
          local pct=Commons.pct_transported(ind.produced[1])
          local increase=(pct>153)~=Commons.chance(3,rnd())
          if (increase and opts.no_increase) or (not increase and opts.no_decrease) or opts.external_prod_level then return end
          local level=ind.prod_level
          if increase then ind.prod_level=min(128,level*2)
          elseif level==4 then close=true
          else ind.prod_level=max(4,floor(level/2)) end
          if level~=ind.prod_level or increase and level<128 then
            for slot,p in ipairs(ind.produced) do
              if p.cargo then record(p,min(255,ceil(spec.rates[slot]*ind.prod_level/16))) end
            end
          end
        end
      else
        close=not (opts.no_closure or opts.no_decrease)
        for _,p in ipairs(ind.produced) do
          if p.cargo then
            local r=assert(rnd)()
            local pct=Commons.pct_transported(p)
            local mult=pct>153 and 1 or -1
            if Commons.chance(pct>204 and 6 or 3,r) then mult=-mult end
            local old,rate=p.rate,p.rate
            if Commons.chance(22,floor(r/65536)) then
              rate=rate+mult*max(floor((range(50,rnd())+10)*old/256),1)
            end
            rate=max(1,min(255,rate))
            -- Source continue matters at minimum: one unchanged above
            -- minimum may independently prevent the whole farm closing.
            if not ((opts.no_decrease and rate<old) or (opts.no_increase and rate>old)) then
              record(p,rate)
              if rate>1 then close=false end
            end
          end
        end
      end
    elseif year-ind.last_prod_year>=F.ABANDON_YEARS then
      close=Commons.chance(opts.original and 2 or 180,assert(rnd)())
    end
    local protected=opts.closure_protected
    if protected==nil then protected=(opts.type_count or 1)<=1 end
    if close and not protected and not opts.no_closure then
      ind.prod_level=0
      return "closure",changes
    end
    if #changes>0 then return "rate",changes end
  end

  function F.month(ind,year,opts)
    if ind.removed then return "removed" end
    for _,p in ipairs(ind.produced) do
      if p.cargo then
        if p.current.production~=0 then ind.last_prod_year=year end
        p.last,p.current=p.current,history()
      end
    end
    if ind.prod_level==0 then ind.removed=true;return "removed" end
    local o={monthly=true}
    for _,key in ipairs(keys(opts or {})) do o[key]=opts[key] end
    return F.change(ind,year,o)
  end
  return F
end
