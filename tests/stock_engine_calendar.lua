-- SPDX-License-Identifier: GPL-2.0-only
local E=dofile("mods/bayline/openttd/stock_engine_calendar.lua")
local function fields(n,y,m,d)
  local a,b,c=E.ymd(n)
  assert(a==y and b==m and c==d)
  assert(E.date(y,m,d)==n)
end
fields(0,0,1,1)
fields(59,0,2,29)
fields(366,1,1,1)
fields(E.BASE_DATE,1920,1,1)
fields(E.MAX_DATE,5000000,12,31)
assert(not E.date(1900,2,29))
assert(E.date(2000,3,1)-E.date(2000,2,28)==2)
assert(E.date(2100,3,1)-E.date(2100,2,28)==1)
assert(not E.date(1920,0,1) and not E.date(1920,1,0) and not E.date("1950",1,1))
assert(not E.ymd(-1) and not E.ymd(E.MAX_DATE+1))

local cfg={starting_year=1950,generation_seed=1751,startup_seed=97721,climate="temperate"}
local date1950=assert(E.date(1950,1,1))
local regal,hereford,foster=assert(E.prepare(116,cfg)),assert(E.prepare(117,cfg)),assert(E.prepare(118,cfg))
fields(regal.base_date,1929,4,1)
fields(hereford.base_date,1964,1,1)
fields(foster.base_date,1986,1,1)
assert(regal.intro_date==regal.base_date and regal.public_date==date1950)
assert(E.snapshot(regal,date1950).public and E.snapshot(regal,date1950).age_months==249)
assert(not E.snapshot(hereford,date1950).public and not E.snapshot(foster,date1950).public)
for _,m in ipairs({hereford,foster}) do
  assert(m.intro_date-m.base_date>=0 and m.intro_date-m.base_date<512)
  assert(E.snapshot(m,m.intro_date).status=="awaiting_public")
  assert(E.snapshot(m,m.public_date-1).status=="awaiting_public")
  local first=assert(E.snapshot(m,m.public_date))
  assert(first.public and first.age_months==0 and first.reliability==m.reliability_start)
  assert(m.public_date>=m.intro_date+365 and m.public_date<=m.intro_date+395)
  local y,mm=E.ymd(m.public_date)
  local next_month=mm==12 and E.date(y+1,1,1) or E.date(y,mm+1,1)
  assert(E.snapshot(m,next_month).age_months==1 and E.snapshot(m,next_month).reliability>m.reliability_start)
end
fields(hereford.public_date,1965,11,1)
fields(foster.public_date,1987,12,1)
local h=assert(E.snapshot(hereford,E.date(2040,1,1)))
assert(h.status=="retired" and not h.public and h.engine_available_flag and h.reliability==hereford.reliability_final)
local f49=assert(E.snapshot(foster,E.date(2049,12,1)))
local f50=assert(E.snapshot(foster,E.date(2050,2,1)))
assert(f49.age_months==f50.age_months and f49.reliability==f50.reliability and f49.public==f50.public)
local late=assert(E.prepare(118,{starting_year=2200,generation_seed=0,startup_seed=2^32-1}))
assert(E.snapshot(late,E.date(2200,1,1)).age_months==64*12)
assert(E.snapshot(late,E.date(2300,1,1)).age_months==64*12)

cfg.climate="toyland"
local bad=assert(E.prepare(116,cfg))
local wrong=assert(E.snapshot(bad,E.date(1986,1,1)))
assert(wrong.status=="wrong_climate" and not wrong.public and wrong.engine_available_flag and wrong.age_months>500)
assert(not bad.public_date)
cfg.climate,cfg.never_expire="temperate",true
local immortal=assert(E.prepare(117,cfg))
local late_h=assert(E.snapshot(immortal,E.date(2070,1,1)))
assert(late_h.public and late_h.reliability==immortal.reliability_max)
assert(immortal.life_days==15*366 and regal.life_days==12*366)
assert(regal.reliability_decay==80 and hereford.reliability_decay==80 and foster.reliability_decay==80)

cfg.never_expire=false
local stock=assert(E.stock(117));stock.stock_id=500
local paired=assert(E.prepare_original(stock,cfg))
assert(paired.intro_date==hereford.intro_date)
assert(paired.reliability_start~=hereford.reliability_start or paired.phase1~=hereford.phase1)
local separate={starting_year=1950,startup_date=E.date(1950,1,1),generation_seed=cfg.startup_seed,startup_seed=cfg.generation_seed+1}
assert(E.prepare(117,separate).intro_date~=hereford.intro_date)
assert(not E.prepare(116,{starting_year=1950,generation_seed=1751}))
assert(not E.snapshot(hereford,date1950-1))
local r=E.stock(116);r.base_life=1
assert(E.stock(116).base_life==40)
r.grfid=1;assert(not E.prepare_original(r,cfg))

-- Startup/reinitialization in a partial introduction month exposes the
-- source signed age -1, and the unsigned check retires it immediately.
local same_month=assert(E.prepare(117,{starting_year=1950,startup_date=hereford.intro_date,
  generation_seed=cfg.generation_seed,startup_seed=cfg.startup_seed}))
local first=assert(E.snapshot(same_month,same_month.startup_date))
assert(first.age_months==-1 and first.status=="retired" and not first.public)
local next_date=same_month.startup_date+40
local after=assert(E.snapshot(same_month,next_date))
assert(after.age_months>=0 and after.status=="retired" and after.reliability>=same_month.reliability_start)
print("PASS: stock Gregorian dates, public releases, climate and age cutoff, seeded design/reliability, exact partial-month startup")
