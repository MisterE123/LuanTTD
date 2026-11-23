-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 contributors, industry_cmd.cpp IndustryBuildData,
-- IndustryTypeBuildData, PlaceIndustry/CreateNewIndustry and daily timer;
-- economy.cpp StartupIndustryDailyChanges; map_func.h Map::ScaleBySize.
-- Serializable independent state. Its host owns occupancy, allocation,
-- RNG ordering, map writes, close/open news and the authoritative clock.
local S={}
local floor,ceil,min,max=math.floor,math.ceil,math.min,math.max
local Q,U32=65536,4294967296
local NEW_PER_MONTH=floor(0x38000/(10*12))
local function scale(n,w,h) return ceil(n*w*h/Q) end
local function range(random,n) return floor(random()*n/U32) end
local function weight(random,n) return floor(((random()%Q)*100+50)/Q)<n end
local function zero() return {probability=0,min_number=0,target_count=0,max_wait=1,wait_count=0} end

function S.reset(num_types,count)
  local s={num_types=num_types,wanted_inds=count*Q,daily_counter=0,builddata={}}
  for id=0,num_types-1 do s.builddata[id]=zero() end
  return s
end

function S.month(s,ctx)
  if ctx.funded_only then return end
  local behind=1+min(99,scale(3,ctx.width,ctx.height))
  if ctx.total()+behind>=floor(s.wanted_inds/Q) then
    s.wanted_inds=(s.wanted_inds+scale(NEW_PER_MONTH,ctx.width,ctx.height))%U32
  end
end

function S.targets(s,ctx)
  local changed,planned=false,0
  for id=0,s.num_types-1 do
    local b=s.builddata[id]
    local prob,least=ctx.available(id)
    changed=changed or prob~=b.probability or least~=b.min_number
    b.probability,b.min_number=prob,least
    planned=planned+b.target_count
  end
  local total=floor(s.wanted_inds/Q)
  if not changed and planned==total then return false end
  local force,prob=0,0
  for id=0,s.num_types-1 do
    local b=s.builddata[id]
    force,prob=force+b.min_number,prob+b.probability
    b.target_count=b.min_number
  end
  if prob==0 then return true end
  for _=1,max(0,total-force) do
    local r=range(ctx.random,prob)
    for id=0,s.num_types-1 do
      local b=s.builddata[id]
      if r<b.probability then b.target_count=b.target_count+1;break end
      r=r-b.probability
    end
  end
  return true
end

function S.try_build(s,ctx)
  S.targets(s,ctx)
  local eligible,missing,prob,forced,forced_difference={},0,0,nil,nil
  for id=0,s.num_types-1 do
    local b,count=s.builddata[id],ctx.count(id)
    local d=b.target_count-count
    missing=missing+d
    if d>0 and b.wait_count==0 then
      eligible[#eligible+1]={id=id,weight=d}
      prob=prob+d
      if count==0 and b.min_number>0 and (forced==nil or d>forced_difference) then
        forced,forced_difference=id,d -- keep first source industry type on ties
      end
    end
  end
  local id,placed
  if not ctx.recession and (forced~=nil or missing>0 and prob>0) then
    id=forced
    if id==nil and #eligible==1 then
      id=eligible[1].id
    elseif id==nil then
      local r=range(ctx.random,prob)
      for _,e in ipairs(eligible) do
        if r<e.weight then id=e.id;break end
        r=r-e.weight
      end
    end
    if id~=nil then
      local b=s.builddata[id]
      placed=ctx.place(id)
      if placed then
        if ctx.advertise then ctx.advertise(placed) end
        b.max_wait=max(floor(b.max_wait/2),1)
      else
        b.wait_count=b.max_wait+1
        b.max_wait=min(1000,b.max_wait+2)
      end
    end
  end
  for key=0,s.num_types-1 do
    local b=s.builddata[key]
    if b.wait_count>0 then b.wait_count=b.wait_count-1 end
  end
  return id,placed
end

function S.place_attempts(ctx,id,try_hard)
  local area=ctx.width*ctx.height
  local layouts=ctx.layout_count(id)
  for _=1,try_hard and 10000 or 2000 do
    local tile=ctx.random()%area -- RandomTileSeed: raw RNG bits masked to map size
    local seed,seed2=ctx.random(),ctx.random()
    local index=range(ctx.random,layouts) -- draws even when only one layout exists
    local placed=ctx.create(id,tile%ctx.width,floor(tile/ctx.width),index,seed,seed2%Q)
    if placed then return placed end
  end
end

function S.day(s,ctx)
  -- Lower 16 bits accrue without a month reset. Source calculates
  -- the chance once for the entire day, not after each build/closure.
  local work=s.daily_counter+floor(ctx.width*ctx.height/31)
  local slots=floor(work/Q)
  s.daily_counter=work%Q
  if slots==0 then return 0 end
  local pc=min(9,3+max(0,floor(s.wanted_inds/Q)-ctx.total()))
  for _=1,slots do
    if weight(ctx.random,pc) then S.try_build(s,ctx)
    else ctx.change_random_industry() end
  end
  return slots
end
return S
