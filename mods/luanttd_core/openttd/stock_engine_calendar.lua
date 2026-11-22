-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors; 14.1 original engines.cpp, table/engines.h,
-- core/random_func.cpp, engine_base.h and timer/timer_game_common.h.
-- Public sale calendar for original, unmodified vehicles only. A host
-- supplies both original seeds and an actual stock calendar day, never
-- the fictional 30-day economy/HUD calendar or manufactured GRF state.
local E={VERSION=1,ORIGINAL_BASE_YEAR=1920,MAX_YEAR=5000000,DEFAULT_AGING_STOP_YEAR=2050,
  DAYS_IN_YEAR=365,DAYS_IN_LEAP_YEAR=366,VEH_ROAD=1}
local floor,min,max=math.floor,math.min,math.max
local U32=2^32
local days={31,28,31,30,31,30,31,31,30,31,30,31}
local climate_ids={temperate=0,arctic=1,tropic=2,toyland=3}
local bus={
  [116]={stock_id=116,name="MPS Regal Bus",intro_after_1920=3378,decay_speed=20,life=12,base_life=40,climates=7},
  [117]={stock_id=117,name="Hereford Leopard Bus",intro_after_1920=16071,decay_speed=20,life=15,base_life=30,climates=7},
  [118]={stock_id=118,name="Foster Bus",intro_after_1920=24107,decay_speed=20,life=15,base_life=40,climates=7},
}
for _,r in pairs(bus) do r.vehicle_type=E.VEH_ROAD;r.retire_early=0 end
local function copy(t)
  local out={}
  for k,v in pairs(t) do out[k]=v end
  return out
end
local function uint(n,lim) return type(n)=="number" and n%1==0 and n>=0 and n<=lim end
local function positive(n,lim) return uint(n,lim) and n>0 end

-- TimerGame::DateAtStartOfYear counts leap year 0 for all intervening
-- dates. TimerGame::Month is zero based; this API uses display months.
local function year_start(y)
  if y==0 then return 0 end
  return 365*y+floor((y-1)/4)-floor((y-1)/100)+floor((y-1)/400)+1
end
local function month_length(y,m)
  return days[m]+(m==2 and year_start(y+1)-year_start(y)-365 or 0)
end
local function date(y,m,d)
  local out=year_start(y)+d-1
  for n=1,m-1 do out=out+month_length(y,n) end
  return out
end
E.BASE_DATE=year_start(E.ORIGINAL_BASE_YEAR)
E.MAX_DATE=year_start(E.MAX_YEAR+1)-1

function E.date(y,m,d)
  if not uint(y,E.MAX_YEAR) or not positive(m,12) or not positive(d,month_length(y,m)) then
    return nil,"INVALID_ENGINE_CALENDAR_DATE"
  end
  return date(y,m,d)
end
local function ymd(n)
  local y=floor(n/365.2425)
  while year_start(y)>n do y=y-1 end
  while year_start(y+1)<=n do y=y+1 end
  local m,rem=1,n-year_start(y)
  while rem>=month_length(y,m) do rem=rem-month_length(y,m);m=m+1 end
  return y,m,rem+1
end
function E.ymd(n)
  if not uint(n,E.MAX_DATE) then return nil,"INVALID_ENGINE_CALENDAR_DATE" end
  return ymd(n)
end
local function month(n,ceil)
  local y,m,d=ymd(n)
  return y*12+m-1+(ceil and d>1 and 1 or 0)
end
local function month_date(index) return date(floor(index/12),index%12+1,1) end

local function xor(a,b)
  local p,value=1,0
  while a~=0 or b~=0 do
    if (a+b)%2==1 then value=value+p end
    a,b,p=floor(a/2),floor(b/2),p*2
  end
  return value
end
local function rotr(v,n) return floor(v/2^n)+v%2^n*2^(32-n) end
local function next_word(s) return (rotr(s,3)-1)%U32 end
local function draws(seed)
  local hi=(seed+rotr(xor(seed,0x1234567F),7)+1)%U32
  return next_word(seed),next_word(hi)
end
local function bits(x,start,size) return floor(x/2^start)%2^size end
local function climate(c)
  if c==nil then return 0 end
  if type(c)=="string" then return climate_ids[c] end
  if uint(c,3) then return c end
end

function E.stock(id)
  local row=bus[id]
  return row and copy(row)
end

-- Build one original road model. Exposed for same-intro comparisons and
-- an eventual separately verified roster; not a NewGRF adapter.
function E.prepare_original(row,cfg)
  if type(row)~="table" or not uint(row.stock_id,65535) or (row.vehicle_type~=E.VEH_ROAD and row.vehicle_type~=2) or
      not uint(row.intro_after_1920,65535) or not uint(row.decay_speed,255) or
      not uint(row.life,255) or not uint(row.base_life,255) or not uint(row.climates,15) or
      not uint(row.retire_early or 0,127) or (row.grfid or 0)~=0 or row.variant_id~=nil then
    return nil,"UNSUPPORTED_ORIGINAL_ENGINE"
  end
  if cfg==nil then cfg={} end
  if type(cfg)~="table" then return nil,"INVALID_ENGINE_WORLD_SEEDS_OR_CALENDAR" end
  local c=climate(cfg.climate)
  local cutoff=cfg.aging_stop_year or E.DEFAULT_AGING_STOP_YEAR
  if c==nil or not uint(cfg.starting_year,E.MAX_YEAR) or not uint(cfg.generation_seed,U32-1) or
      not uint(cfg.startup_seed,U32-1) or not uint(cutoff,E.MAX_YEAR) or cutoff<E.DEFAULT_AGING_STOP_YEAR or
      cfg.never_expire~=nil and type(cfg.never_expire)~="boolean" then
    return nil,"INVALID_ENGINE_WORLD_SEEDS_OR_CALENDAR"
  end
  local original_start=year_start(cfg.starting_year)
  local startup_date=cfg.startup_date or original_start
  if not uint(startup_date,E.MAX_DATE) or startup_date<original_start then
    return nil,"INVALID_ENGINE_STARTUP_DATE"
  end

  local base=E.BASE_DATE+row.intro_after_1920
  local common=xor(cfg.generation_seed,cfg.startup_seed)
  local introduction_seed=xor(xor(common,base),row.vehicle_type)
  local intro_delta=bits(next_word(introduction_seed),0,9)
  local intro=base<=year_start(cfg.starting_year+2) and base or base+intro_delta
  local reliability_seed=xor(common,(row.stock_id*2^16)%U32)
  reliability_seed=xor(reliability_seed,(base*2^12)%U32)
  reliability_seed=xor(reliability_seed,row.decay_speed*2^8)
  reliability_seed=xor(reliability_seed,row.life*2^4)
  reliability_seed=xor(reliability_seed,row.retire_early or 0)
  reliability_seed=xor(reliability_seed,row.vehicle_type)
  local r1,r2=draws(reliability_seed)
  local phase1=bits(r2,0,5)+7
  local phase2=max(0,bits(r2,5,4)+row.base_life*12-96)
  local phase3=bits(r2,9,7)+120
  local age=0
  if intro<=startup_date then
    -- StartupOneEngine can get -1 when activated partway through the
    -- introduction month. Engine::age is signed; CalcEngineReliability
    -- converts it to uint32 and can clear the company mask at startup.
    age=month(min(startup_date,year_start(cutoff)))-month(intro,true)
  end
  local may_sell=bits(row.climates,c,1)==1
  local public_month=month(intro+E.DAYS_IN_YEAR,true)
  local startup_public=may_sell and intro<=startup_date
  local expiry
  if not cfg.never_expire and row.base_life~=255 then
    expiry=phase1+phase2+phase3
    if (row.retire_early or 0)>0 then expiry=min(expiry,max(0,phase1+phase2-row.retire_early*12)) end
  end
  return {
    version=E.VERSION,stock_id=row.stock_id,name=row.name,vehicle_type=row.vehicle_type,climate=c,
    starting_year=cfg.starting_year,startup_date=startup_date,aging_stop_year=cutoff,
    generation_seed=cfg.generation_seed,startup_seed=cfg.startup_seed,never_expire=not not cfg.never_expire,
    base_date=base,intro_date=intro,public_month=public_month,
    public_date=may_sell and (startup_public and startup_date or
      public_month<cutoff*12 and month_date(public_month) or nil) or nil,
    climate_matches=may_sell,startup_public=startup_public,startup_age=age,
    phase1=phase1,phase2=phase2,phase3=phase3,expiry_age=expiry,
    reliability_start=bits(r1,16,14)+0x7AE0,reliability_max=bits(r1,0,14)+0xBFFF,
    reliability_final=bits(r2,16,14)+0x3FFF,reliability_decay=row.decay_speed*4,
    life_days=row.life*E.DAYS_IN_LEAP_YEAR,infinite=row.base_life==255,
  }
end

function E.prepare(id,cfg)
  local row=bus[id]
  if not row then return nil,"UNKNOWN_STOCK_ROAD_ENGINE" end
  return E.prepare_original(row,cfg)
end

local function reliability(model,age)
  age=age%U32 -- uint32_t local in CalcEngineReliability
  if age<model.phase1 then
    return model.reliability_start+floor(age*(model.reliability_max-model.reliability_start)/model.phase1)
  end
  age=age-model.phase1
  if age<model.phase2 or model.never_expire or model.infinite then return model.reliability_max end
  age=age-model.phase2
  if age<model.phase3 then
    -- Signed division in the falling segment truncates toward zero.
    return model.reliability_max-floor(age*(model.reliability_max-model.reliability_final)/model.phase3)
  end
  return model.reliability_final
end

-- Pure public design projection. Global ENGINE_AVAILABLE is distinct
-- from the per-company public bitmask: wrong-climate and retired
-- designs retain the flag but cannot be selected for purchase.
function E.snapshot(model,at)
  if type(model)~="table" or model.version~=E.VERSION then return nil,"INVALID_ENGINE_MODEL" end
  if not uint(at,E.MAX_DATE) or at<model.startup_date then return nil,"ENGINE_DATE_BEFORE_STARTUP_OR_INVALID" end
  local last_month=min(month(at),model.aging_stop_year*12-1)
  local updates=max(0,last_month-month(model.startup_date))
  local flagged=not model.climate_matches or model.startup_public
  local age=model.startup_age
  local public,retired=false,false
  if flagged then
    age=age+updates
    if model.climate_matches then
      retired=model.expiry_age~=nil and
        (model.startup_age%U32>=model.expiry_age or age%U32>=model.expiry_age)
      public=not retired
    end
  elseif last_month>=model.public_month then
    flagged=true
    age=last_month-model.public_month
    retired=model.expiry_age~=nil and age>0 and age>=model.expiry_age
    public=not retired
  end
  local status=not model.climate_matches and "wrong_climate" or public and "available" or
    retired and "retired" or at<model.intro_date and "not_introduced" or "awaiting_public"
  return {stock_id=model.stock_id,at=at,public=public,engine_available_flag=flagged,status=status,
    age_months=age,intro_date=model.intro_date,public_date=model.public_date,base_date=model.base_date,
    phase1=model.phase1,phase2=model.phase2,phase3=model.phase3,
    reliability=reliability(model,age),reliability_decay=model.reliability_decay,
    reliability_start=model.reliability_start,reliability_max=model.reliability_max,reliability_final=model.reliability_final,
    life_days=model.life_days}
end

return E
