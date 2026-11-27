-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 subsidy.cpp, subsidy_base.h and economy.cpp.
-- Shared stock economy-before-town monthly clock.
-- Adapter contract: ordered stock IDs, canonical participant objects, and
-- the exact preceding-month production and station catchment inputs.
return function(range,chance)
  local S={MAX=256,OFFER_MONTHS=12}
  local abs,floor,min=math.abs,math.floor,math.min
  function S.percent(transported,production)
    return production==0 and 0 or min(255,floor(transported*256/production))
  end
  function S.new() return {rows={},count=0} end
  local function same(a,b)
    return a.id==b.id and a.type==b.type
  end
  local function notice(emit,kind,row)
    if emit then emit(kind,row) end
  end
  local function subject(a) return {id=a.id,type=a.type} end
  local function duplicate(state,cargo,src,dst)
    for i=0,S.MAX-1 do
      local e=state.rows[i]
      if e and e.cargo==cargo and same(e.src,src) and same(e.dst,dst) then return true end
    end
    return false
  end
  local function distance(a,b)
    return abs(a.x-b.x)+abs(a.z-b.z)
  end
  local function choose(list,random)
    if #list==0 then return end
    return list[range(#list,random())+1]
  end
  function S.create(state,cargo,src,dst,emit)
    if state.count>=S.MAX then return end
    local id=0
    while state.rows[id] do id=id+1 end
    local entry={id=id,cargo=cargo,src=subject(src),dst=subject(dst),remaining=S.OFFER_MONTHS}
    state.rows[id],state.count=entry,state.count+1
    notice(emit,"offer",entry)
    return entry
  end
  local function offer(state,cargo,src,dst,emit)
    if not dst or same(src,dst) or distance(src,dst)>70 or duplicate(state,cargo,src,dst) then return end
    return S.create(state,cargo,src,dst,emit)
  end
  local function passenger(state,board,random,emit)
    if state.count>=S.MAX then return end
    local cargo=assert(choose(board.passengers,random),"Stock passenger CargoSpec required")
    local src=choose(board.towns,random)
    if not src or src.population<400 or board.town_transported(src,cargo)>42 then return end
    local dst=choose(board.towns,random)
    if not dst or dst.population<400 then return end
    return offer(state,cargo,src,dst,emit)
  end
  local function cargo_destination(state,board,src,cargo,random,emit)
    local dst
    if chance(1,2,random()) then
      dst=choose(board.towns,random)
      if not dst or board.town_accepts(dst,cargo,6)<8 then return end
    else
      dst=choose(board.industries,random)
      if not dst or not board.industry_accepts(dst,cargo) then return end
    end
    return offer(state,cargo,src,dst,emit)
  end
  local function town_cargo(state,board,random,emit)
    if state.count>=S.MAX then return end
    local src=choose(board.towns,random)
    if not src or src.population<900 then return end
    -- Adapter returns the non-passenger positive-production CargoSpecs
    -- in ascending CargoID, from the radius-six scan of actual houses.
    local cargo=choose(board.town_cargo(src,6),random)
    if cargo==nil or not board.valid_cargo(cargo) or board.town_transported(src,cargo)>42 then return end
    return cargo_destination(state,board,src,cargo,random,emit)
  end
  local function industry_cargo(state,board,random,emit)
    if state.count>=S.MAX then return end
    local src=choose(board.industries,random)
    if not src then return end
    local slot=choose(board.industry_produced(src),random)
    if not slot or slot.production==0 or slot.transported_pct>42 or not board.valid_cargo(slot.cargo) then return end
    return cargo_destination(state,board,src,slot.cargo,random,emit)
  end
  function S.month(state,board,duration,random,emit)
    local modified=false
    for i=0,S.MAX-1 do
      local e=state.rows[i]
      if e then
        e.remaining=(e.remaining-1)%65536
        if e.remaining==0 then
          notice(emit,e.awarded~=nil and "expired" or "offer_expired",e)
          state.rows[i],state.count=nil,state.count-1
          modified=true
        end
      end
    end
    if not modified and duration==0 then return false end
    local roll=range(16,random())
    local search=roll<2 and passenger or roll==2 and town_cargo or roll==3 and industry_cargo
    if search then
      for _=0,1000 do
        local e=search(state,board,random,emit)
        if e then return true,e end
      end
    end
    return modified
  end
  function S.delete_source(state,src)
    local changed=false
    for i=0,S.MAX-1 do
      local e=state.rows[i]
      if e and (same(e.src,src) or same(e.dst,src)) then
        state.rows[i],state.count=nil,state.count-1
        changed=true
      end
    end
    return changed
  end
  function S.deliver(state,cargo,company,src,near,duration,emit)
    if not src then return false end
    local applies=false
    for i=0,S.MAX-1 do
      local e=state.rows[i]
      -- Check each qualified destination in the actual station catchment;
      -- the same delivery can award several distinct offers.
      if e and cargo==e.cargo and same(e.src,src) and
          (e.awarded==nil or e.awarded==company) and near(e.dst) then
        if e.awarded==nil then
          e.awarded,e.remaining=company,duration*12
          notice(emit,"awarded",e)
        end
        applies=true
      end
    end
    return applies
  end
  function S.pay(profit,multiplier)
    if multiplier==0 then return profit+floor(profit/2) end
    return profit*(multiplier+1)
  end
  return S
end
