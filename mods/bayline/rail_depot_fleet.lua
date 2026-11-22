-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 public stock rail availability (engine.cpp), build checks
-- (vehicle_cmd.cpp), and per-company train allocation (vehicle.cpp).
-- This is an owned-depot aggregate purchase with an explicit consist
-- layout, not a port of the stock loose-wagon autoattachment command.
return function(Sim,Lab,Roster)
  local F={VERSION=1,MAX_POOL=0xFF000}
  local floor,min,max=math.floor,math.min,math.max
  local U32=2^32
  local function uint(n,cap) return type(n)=="number" and n>=0 and n<=cap and n%1==0 end
  local function clone(t)
    if type(t)~="table" then return t end
    local out={}
    for k,v in pairs(t) do out[k]=clone(v) end
    return out
  end
  local function state(s)
    local d=s.stock_rail_fleet
    if d and d.version==F.VERSION then return d end
  end
  local function year_start(y)
    return y==0 and 0 or 365*y+floor((y-1)/4)-floor((y-1)/100)+floor((y-1)/400)+1
  end
  local days={31,28,31,30,31,30,31,31,30,31,30,31}
  local function month_length(y,m)
    return days[m]+(m==2 and year_start(y+1)-year_start(y)-365 or 0)
  end
  local function date_parts(day)
    local y=floor(day/365.2425)
    while year_start(y)>day do y=y-1 end
    while year_start(y+1)<=day do y=y+1 end
    local m,rem=1,day-year_start(y)
    while rem>=month_length(y,m) do rem=rem-month_length(y,m);m=m+1 end
    return y,m,rem+1
  end
  local function month_index(day)
    local y,m,dom=date_parts(day)
    return y*12+m-1,dom
  end
  local function next_month(day)
    local month,dom=month_index(day)
    return month+(dom>1 and 1 or 0)
  end
  local function xor(x,y)
    local power,out=1,0
    while (x>0 or y>0) do
      if (x+y)%2==1 then out=out+power end
      x,y,power=floor(x/2),floor(y/2),power*2
    end
    return out
  end
  local function rotr(x,n) return floor(x/2^n)+x%2^n*2^(32-n) end
  local function random_pair(seed)
    -- Same-seed state immediately after OpenTTD SetRandomSeed; only
    -- the first two draws matter to these stock reliability fields.
    local hi=(seed+rotr(xor(seed,0x1234567F),7)+1)%U32
    return (rotr(seed,3)-1)%U32,(rotr(hi,3)-1)%U32
  end
  local function bits(x,shift,n) return floor(x/2^shift)%2^n end
  local function model(stock,cfg)
    local base=year_start(1920)+stock.base_intro
    local seed=xor(cfg.generation_seed,cfg.startup_random)
    seed=xor(seed,(stock.stock_id*2^16)%U32)
    seed=xor(seed,(base*2^12)%U32)
    seed=xor(seed,(stock.decay_speed*2^8)%U32)
    seed=xor(seed,(stock.vehicle_life*2^4)%U32)
    local r1,r2=random_pair(seed)
    return {
      intro=Roster.introduction(stock.stock_id,cfg.starting_year,cfg.generation_seed,cfg.startup_random),
      phase1=bits(r2,0,5)+7,phase2=max(0,bits(r2,5,4)+stock.model_life*12-96),phase3=bits(r2,9,7)+120,
      reliability_start=bits(r1,16,14)+0x7AE0,reliability_max=bits(r1,0,14)+0xBFFF,
      reliability_final=bits(r2,16,14)+0x3FFF,reliability_decay=stock.decay_speed*4,
    }
  end
  local function availability(d,id,today)
    local item=Roster.entry(id)
    if not item then return nil,"UNKNOWN_RAIL_VEHICLE" end
    -- Later stock roster rows are derived from this world's original
    -- generation seed, startup draw and month. Old saves keep every
    -- purchased unit and their existing stock-model records unchanged.
    local base=d.models[id] or model(item,d.config)
    local info=clone(base)
    info.public=false
    info.stock_id=id
    info.climate=Roster.climate_ok(id,d.config.climate)
    info.as_of=today
    local start=year_start(d.config.starting_year)
    local intro_month=next_month(base.intro)
    local age=0
    local aging_cutoff=year_start(d.config.aging_stops_year)
    local now_month=month_index(min(max(start,today),aging_cutoff-1))
    if not info.climate then
      info.status="wrong_climate"
      -- Startup still computes the age before the climate mask clears
      -- company rights, and the ENGINE_AVAILABLE flag still reaches the
      -- stock monthly aging step even for the wrong-climate design.
      if base.intro<=start then age=max(0,month_index(min(start,aging_cutoff))-intro_month) end
      age=age+max(0,now_month-month_index(start))
    elseif base.intro<=start then
      -- StartupEngines initial age uses the clamped January 1 in a
      -- late-starting world. Monthly updates stop before cutoff year.
      age=month_index(min(start,aging_cutoff))-intro_month
      age=max(0,age)+max(0,now_month-month_index(start))
      info.public=true
    else
      -- Public introduction occurs at the first monthly loop on/after
      -- the first anniversary, not at the exclusive preview date.
      local first_public=next_month(base.intro+365)
      info.first_public_month=first_public
      if now_month<first_public then
        info.status=today<base.intro and "not_introduced" or "preview_period"
      else
        info.public=true
        age=now_month-first_public
      end
    end
    local reliability
    if age<base.phase1 then
      reliability=base.reliability_start+floor(age*(base.reliability_max-base.reliability_start)/base.phase1)
    elseif age<base.phase1+base.phase2 or d.config.never_expire or item.model_life==255 then
      reliability=base.reliability_max
    elseif age<base.phase1+base.phase2+base.phase3 then
      -- C++ signed division truncates toward zero on the declining
      -- segment, which is one point different from floor in general.
      local decline=(age-base.phase1-base.phase2)*(base.reliability_max-base.reliability_final)
      reliability=base.reliability_max-floor(decline/base.phase3)
    else
      reliability=base.reliability_final
      if info.public then info.public=false;info.status="retired" end
    end
    info.age_months,info.reliability=age,reliability
    if info.public then info.status="available" end
    return info
  end
  local function today(s,d)
    -- Dedicated Gregorian calendar offsets for this ruleset. A flat
    -- 30-day HUD month must not drive stock intro/reliability.
    return year_start(d.config.starting_year)+(s.day-d.initial_day)
  end
  function F.initialize(s,cfg)
    if state(s) then return nil,"RAIL_FLEET_ALREADY_INITIALIZED" end
    if s.stock_rail_fleet then return nil,"INVALID_RAIL_FLEET_VERSION" end
    cfg=cfg or {}
    if not uint(cfg.starting_year,5000000) or cfg.starting_year<1 or
        not uint(cfg.generation_seed,U32-1) or not uint(cfg.startup_random,U32-1) or
        not Roster.climate_ok(27,cfg.climate) or not uint(s.day,U32-1) then
      return nil,"INVALID_RAIL_FLEET_OPTIONS"
    end
    cfg={starting_year=cfg.starting_year,climate=cfg.climate or "temperate",
      generation_seed=cfg.generation_seed,startup_random=cfg.startup_random,
      aging_stops_year=cfg.aging_stops_year or 2050,never_expire=cfg.never_expire==true,
      max_trains=cfg.max_trains or 500,vehicle_pool=cfg.vehicle_pool or F.MAX_POOL,
      max_train_tiles=cfg.max_train_tiles or Roster.DEFAULT_MAX_TRAIN_TILES,
      extend_vehicle_life=cfg.extend_vehicle_life or 0,
      calendar_origin_day=cfg.calendar_origin_day or 0,roster_preview=cfg.roster_preview==true}
    if not uint(cfg.aging_stops_year,5000000) or cfg.aging_stops_year<2050 or
        not uint(cfg.max_trains,5000) or not uint(cfg.vehicle_pool,F.MAX_POOL) or
        not uint(cfg.max_train_tiles,64) or cfg.max_train_tiles<1 or
        not uint(cfg.extend_vehicle_life,255) or not uint(cfg.calendar_origin_day,s.day) then
      return nil,"INVALID_RAIL_FLEET_OPTIONS"
    end
    local d={version=F.VERSION,config=cfg,initial_day=cfg.calendar_origin_day,next_id=1,units={},models={}}
    for _,row in ipairs(Roster.catalog(s.stock_electrification==true)) do d.models[row.stock_id]=model(row,cfg) end
    s.stock_rail_fleet=d
    return true
  end
  function F.availability(s,id)
    local d=state(s)
    if not d then return nil,"RAIL_FLEET_UNAVAILABLE" end
    return availability(d,id,today(s,d))
  end
  function F.catalog(s)
    local d=state(s)
    if not d then return nil,"RAIL_FLEET_UNAVAILABLE" end
    local rows=Roster.catalog(s.stock_electrification==true)
    local day=today(s,d)
    for _,row in ipairs(rows) do
      row.availability=availability(d,row.stock_id,day)
      row.preview=d.config.roster_preview
    end
    return rows
  end
  function F.railtype_mask(s,owner,Types)
    local d=state(s)
    if not (d and s.companies[owner]) then return 0 end
    local climate=type(d.config.climate)=="number" and d.config.climate or
      ({temperate=0,arctic=1,tropic=2,toyland=3})[d.config.climate]
    if not climate then return 0 end
    local now=today(s,d)
    local candidates={}
    -- This host models public sale only and uses the same current
    -- public state for each company (no exclusive preview offer yet).
    for _,row in ipairs(Roster.catalog(s.stock_electrification==true)) do
      local a=availability(d,row.stock_id,now)
      candidates[#candidates+1]={intended_railtype=row.railtype,kind=row.kind,climates=row.climates,
        company_avail=a.public and 1 or 0,intro_date=a.intro}
    end
    return Types.company_types(candidates,0,climate,now,false)
  end

  local function depot(s,id)
    if not uint(id,U32-1) or id==0 then return end
    local t=Lab.board(s).tile(id)
    if t and t.kind=="depot" then return {id=id,kind=t.kind,owner=t.owner,dir=t.dir,railtype=t.railtype} end
  end
  local function read_limits(d,s,owner,hooks)
    local count,parts,used=0,0,{}
    for _,record in pairs(d.units) do
      parts=parts+#record.parts
      if record.owner==owner then
        count=count+1;used[record.unit_number]=true
      end
    end
    if hooks and hooks.other_pool_count then parts=parts+hooks.other_pool_count(s)
    else for _ in pairs(s.fleet or {}) do parts=parts+1 end end
    if hooks and hooks.other_company_units then
      for unit in pairs(hooks.other_company_units(s,owner)) do
        if not used[unit] then count=count+1;used[unit]=true end
      end
    end
    local unit=1
    while used[unit] do unit=unit+1 end
    return {
      vehicle_slots=max(0,d.config.vehicle_pool-parts),
      free_locomotive_numbers=max(0,d.config.max_trains-count),unit_number=unit,
    }
  end
  local function config_options(d,s,source,hooks)
    local opts=hooks and hooks.price_settings and clone(hooks.price_settings(s)) or {}
    opts.freight_trains=hooks and hooks.freight_trains and hooks.freight_trains(s) or opts.freight_trains
    opts.max_train_tiles=d.config.max_train_tiles
    if source then
      opts.climate=d.config.climate
      opts.roster_preview=d.config.roster_preview
      local day=today(s,d)
      opts.available=function(id) return availability(d,id,day).public end
      -- Vanilla 14.1 compatible railtypes for each roster member include
      -- normal and electric. Hosts with separate per-company railtype
      -- availability can supply the exact current flag set.
      opts.company_railtypes=hooks and hooks.company_railtypes and hooks.company_railtypes(s,source) or {[0]=true}
    end
    return opts
  end
  local function layout(selection)
    if type(selection)~="table" or #selection==0 or #selection>128 then return nil,"INVALID_RAIL_FLEET_CONSIST" end
    local ids={}
    for k in pairs(selection) do
      if not uint(k,#selection) or k<1 then return nil,"INVALID_RAIL_FLEET_CONSIST" end
    end
    for i=1,#selection do
      local id=selection[i]
      if id==nil then return nil,"INVALID_RAIL_FLEET_CONSIST" end
      local row=Roster.entry(id)
      if not row then return nil,"UNKNOWN_RAIL_VEHICLE",i end
      if row.kind~=(i==1 and "engine" or "wagon") then return nil,"ONE_LEAD_LOCOMOTIVE_REQUIRED",i end
      ids[i]=id
    end
    return ids
  end
  function F.quote(s,owner,depot_id,selection,hooks)
    local d=state(s)
    if not d then return nil,"RAIL_FLEET_UNAVAILABLE" end
    local company=s.companies[owner]
    if not company then return nil,"RAIL_COMPANY_REQUIRED" end
    local at=depot(s,depot_id)
    if not at or at.owner~=owner then return nil,"INVALID_OWNED_DEPOT" end
    local ids,why,index=layout(selection)
    if not ids then return nil,why,index end
    local limits=read_limits(d,s,owner,hooks)
    local opts=config_options(d,s,owner,hooks)
    if not opts.company_railtypes[0] and not opts.company_railtypes[1] then
      return nil,"RAIL_VEHICLE_NOT_AVAILABLE"
    end
    -- Only a verified live host can open this opted-in wagon. Never
    -- accept a request-side flag from the selection or persisted receipt.
    opts.mount_oil_wagon=s.rail_oil_service==true and hooks and
      hooks.oil_wagon_ready and hooks.oil_wagon_ready(s)==true or false
    opts.mount_goods_wagon=s.rail_goods_service==true and hooks and
      hooks.goods_wagon_ready and hooks.goods_wagon_ready(s)==true or false
    opts.mount_manley=s.rail_paid_service==true and hooks and
      hooks.manley_ready and hooks.manley_ready(s)==true or false
    opts.mounted_electric={}
    if s.stock_electrification==true and hooks and hooks.electric_model_ready then
      for _,id in ipairs(ids) do
        if Roster.electric_engine(id) then opts.mounted_electric[id]=hooks.electric_model_ready(id)==true end
      end
    end
    opts.cash=company.cash
    opts.vehicle_slots,opts.free_locomotive_numbers=limits.vehicle_slots,limits.free_locomotive_numbers
    local q
    q,why,index=Roster.quote(at,owner,ids,opts)
    if not q then return nil,why,index end
    q.stock_ids,q.expect_id,q.unit_number,q.depot_dir=ids,d.next_id,limits.unit_number,at.dir
    q.depot_railtype=at.railtype
    q.calendar_day=today(s,d)
    return q
  end
  function F.commit(s,owner,q,hooks)
    local d=state(s)
    if not d then return nil,"RAIL_FLEET_UNAVAILABLE" end
    if type(q)~="table" or q.kind~="rail_purchase" or q.owner~=owner or q.expect_id~=d.next_id or
        d.units[d.next_id]~=nil then return nil,"STALE_RAIL_FLEET_QUOTE" end
    local fresh,why,i=F.quote(s,owner,q.depot,q.stock_ids,hooks)
    if not fresh then return nil,why,i end
    if q.price~=fresh.price or q.unit_number~=fresh.unit_number or q.depot_dir~=fresh.depot_dir or
        q.depot_railtype~=fresh.depot_railtype or q.preview~=fresh.preview then return nil,"STALE_RAIL_FLEET_QUOTE" end
    local c=s.companies[owner]
    if type(c.cash)~="number" or type(c.expense)~="number" or type(c.month_exp)~="number" then
      return nil,"INVALID_RAIL_COMPANY_LEDGER" end
    local r={id=d.next_id,unit_number=fresh.unit_number,owner=owner,depot=fresh.depot,
      depot_dir=fresh.depot_dir,stock_ids=clone(fresh.stock_ids),status="depot",purchase_day=s.day,
      price=fresh.price,expense="new_vehicles",roster_preview=fresh.preview,parts={}}
    for n,row in ipairs(fresh.stats.parts) do
      local part={stock_id=row.stock_id,cargo_count=0,build_year=date_parts(fresh.calendar_day),
        purchase_value=row.price,last_service_calendar=fresh.calendar_day}
      if row.multiheaded then part.role,part.mate=row.role,row.mate end
      if row.kind=="engine" then
        local a=availability(d,row.stock_id,fresh.calendar_day)
        part.reliability=a.reliability
        part.reliability_decay=a.reliability_decay
        part.max_age_days=Roster.vehicle_life_days(row.stock_id,d.config.extend_vehicle_life)
      end
      r.parts[n]=part
    end
    -- No callbacks or fallible work beyond this point. The same world
    -- snapshot persists the cash ledger, purchase receipt and identity.
    c.cash,c.expense,c.month_exp=c.cash-r.price,c.expense+r.price,c.month_exp+r.price
    d.units[r.id],d.next_id=r,r.id+1
    return clone(r)
  end
  function F.get(s,owner,id)
    local d=state(s)
    local r=d and d.units[id]
    if r and r.owner==owner then return clone(r) end
  end
  function F.list(s,owner,depot_id)
    local out={}
    local d=state(s)
    if not d then return out end
    for _,r in pairs(d.units) do
      if r.owner==owner and (not depot_id or r.depot==depot_id) then out[#out+1]=clone(r) end
    end
    table.sort(out,function(a,b) return a.unit_number<b.unit_number end)
    return out
  end
  function F.occupies_depot(s,depot_id)
    local d=state(s)
    for _,r in pairs(d and d.units or {}) do
      if r.status=="depot" and r.depot==depot_id then return true end
    end
    return false
  end
  function F.prepare_dispatch(s,owner,id,hooks)
    local d=state(s)
    local r=F.get(s,owner,id)
    if not r then return nil,"UNKNOWN_OWNED_RAIL_CONSIST" end
    if r.status~="depot" then return nil,"RAIL_CONSIST_ALREADY_DISPATCHED" end
    local at=depot(s,r.depot)
    if not at or at.owner~=owner or at.dir~=r.depot_dir or at.railtype~=0 and at.railtype~=1 then
      return nil,"INVALID_OWNED_DEPOT"
    end
    local stats,why=Roster.stats(r.parts,config_options(d,s,nil,hooks))
    if not stats then return nil,why end
    if not stats.compatible[at.railtype] then return nil,"INCOMPATIBLE_DEPOT_RAIL" end
    if stats.too_long then return nil,"TRAIN_TOO_LONG" end
    return {id=id,unit_number=r.unit_number,owner=owner,depot=r.depot,stock_ids=r.stock_ids,
      parts=r.parts,stats=stats,roster_preview=r.roster_preview}
  end
  -- Call only after a real dispatch has been prepared/started on the same
  -- world tick; the host owns rollback if its own runtime handoff fails.
  function F.can_bind_dispatch(s,owner,id,run_id)
    local d=state(s)
    local r=d and d.units[id]
    if not r or r.owner~=owner then return nil,"UNKNOWN_OWNED_RAIL_CONSIST" end
    if r.status~="depot" then return nil,"RAIL_CONSIST_ALREADY_DISPATCHED" end
    if not uint(run_id,U32-1) or run_id==0 then return nil,"INVALID_RAIL_DISPATCH_ID" end
    for _,other in pairs(d.units) do
      if other.run_id==run_id then return nil,"RAIL_DISPATCH_ID_IN_USE" end
    end
    return true
  end
  function F.bind_dispatch(s,owner,id,run_id)
    local ok,why=F.can_bind_dispatch(s,owner,id,run_id)
    if not ok then return nil,why end
    local r=state(s).units[id]
    r.status,r.run_id="dispatched",run_id
    return true
  end
  return F
end
