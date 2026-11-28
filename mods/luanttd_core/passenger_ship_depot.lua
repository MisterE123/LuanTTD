-- A purchased passenger hull remains company property while stopped or
-- between orders. The shared passenger clock owns loading and fares.
return function(Sim,Roster,Calendar,Run,art)
  local D={}
  local source=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/openttd/"
  local Fault=dofile(source.."road_breakdowns.lua")
  local Trigger=dofile(source.."vehicle_random_trigger.lua")
  local Effects=dofile(source.."industry_chimney_effect.lua")
  local markets=setmetatable({},{__mode="k"})
  local function snapshot(s,stock,date)
    local market=s.stock_bus_market
    if not market then return end
    local models=markets[market]
    if not models then models={};markets[market]=models end
    if not models[stock] then
      local data=assert(Roster.model(stock))
      models[stock]=assert(Calendar.prepare_original(data,market.settings))
    end
    return assert(Calendar.snapshot(models[stock],date or market.epoch+s.day))
  end
  function D.offer(s,id)
    if not art(id) then return end
    local r=Roster.quote(id,s.stock_ship_purchase_base)
    if not r then return end
    local status=snapshot(s,id)
    return status and status.public and r or nil
  end
  function D.quote(s,owner,depot,id)
    if s.stock_owned_ferry then return nil,"The current passenger fleet supports one owned ferry." end
    if Run.current(s) then return nil,"Clear the active test ferry before buying a vessel." end
    local q=(s.stock_ship_depots or {})[depot]
    if not q or q.owner~=owner then return nil,"Choose a ship depot you own." end
    if s.stock_coal_ship and s.stock_coal_ship.depot==depot then return nil,"The Yate already uses this depot." end
    if s.stock_owned_oil_ship and s.stock_owned_oil_ship.depot==depot then return nil,"The oil tanker already uses this depot." end
    local r=D.offer(s,id)
    return r,r and nil or "That ferry is not on sale."
  end
  function D.buy(s,owner,depot,id)
    local quote,why=D.quote(s,owner,depot,id)
    if not quote then return nil,why end
    local c=Sim.company(s,owner)
    if c.cash<quote.price then return nil,"Not enough cash for this ferry." end
    local unit={owner=owner,depot=depot,engine_id=id,price=quote.price,built=Sim.date(s),purchase_day=s.day,
      running_ticks=0,charged_ticks=0,expense=0}
    if s.stock_engine_startup_seed~=nil then
      local slots,why=Sim.stock_vehicle_slots(s,1)
      if not slots then return nil,why end
      local engine=assert(snapshot(s,id))
      unit.stock_pool_id=slots[1]
      unit.stock_fault=Fault.new(engine.reliability,engine.reliability_decay,engine.life_days,engine.at,engine.at)
      Trigger.built(unit,function() return Sim.stock_random_u32(s) end)
    end
    c.cash,c.expense,c.month_exp=c.cash-quote.price,c.expense+quote.price,c.month_exp+quote.price
    s.stock_owned_ferry=unit
    return unit,"Purchased "..quote.name..". Choose two docks to order the ferry."
  end
  function D.staged(s,owner,depot)
    local u=s.stock_owned_ferry
    return u and u.owner==owner and u.depot==depot and not Run.current(s) and art(u.engine_id) and u or nil
  end
  function D.start(s,owner,depot,a,b,via)
    local u=D.staged(s,owner,depot)
    if not u then return nil,"BUY_PASSENGER_FERRY_FIRST" end
    local p,why=Run.start(s,owner,depot,a,b,via,u.engine_id)
    if not p then return nil,why end
    p.owned=true
    p.paid_build_year=u.built
    return p
  end
  function D.stock_cargo_random(s,p,kind)
    local u=p.owned and s.stock_owned_ferry
    if u and u.stock_pool_id~=nil then
      Trigger.single(u,kind,function() return Sim.stock_random_u32(s) end)
    end
  end
  function D.stock_fault_days(s)
    local u=s.stock_owned_ferry
    local h=u and u.stock_fault
    if not h then return {} end
    local p=Run.current(s)
    if p and not D.ready(s,p) then return {} end
    return {{id=u.stock_pool_id,calendar=function()
      Fault.calendar_day(h)
    end,economy=function(date)
      local v=p and p.vehicle
      local engine=assert(snapshot(s,u.engine_id,date))
      u.stock_economy_age=math.min(Fault.MAX_AGE,(u.stock_economy_age or 0)+1)
      u.stock_day_counter=((u.stock_day_counter or 0)+1)%256
      if u.stock_day_counter%8==0 then
        local value=u.stock_value or u.price
        u.stock_value=value-math.floor(value/256)
      end
      Fault.economy_day(h,{ship=true,cur_speed=v and v.speed or 0,stopped=not v or p.stopped,
        loading=v and v.loading,engine_reliability=engine.reliability,difficulty=Run.stock_breakdown_difficulty},
        function() return Sim.stock_random_u32(s) end)
      if p then D.settle(s,p) end
    end}}
  end
  function D.phased_economy(s,p)
    local u=s.stock_owned_ferry
    return p and p.owned and u and u.stock_fault and s.stock_generated_profile
      and s.stock_bus_market and Sim.road_stock_service_active(s)
  end
  function D.stock_fault_turn(s,p)
    local u=p.owned and s.stock_owned_ferry
    local h=u and u.stock_fault
    if not h then return end
    local v=p.vehicle
    local event=Fault.tick(h,{cur_speed=v.speed,loading=v.loading,hidden=v.hidden,crashed=v.crashed})
    v.speed,v.breakdown=event.cur_speed,event.hold_motion or nil
    if event.hold_motion then
      v.tick=v.tick+1
      v.order_time=(v.order_time or 0)+1
    end
    if event.smoke_animation_state then
      local ids=Sim.stock_vehicle_slots(s,1)
      if ids then Effects.add_timed(s,ids[1],"ship_smoke",v.x+4,v.z+5,v.y+4,u.stock_pool_id,event.smoke_animation_state) end
    end
    return event.hold_motion
  end
  function D.stop(s,owner,stopped)
    local u=s.stock_owned_ferry
    local p=Run.current(s)
    if not (u and p and p.owned and u.owner==owner and p.owner==owner and art(u.engine_id)) then
      return nil,"This is not your active ferry."
    end
    if p.failure then return nil,"The route is blocked: "..tostring(p.failure) end
    p.stopped=not not stopped
    return true,stopped and "Ferry stopped." or "Ferry resumed."
  end
  function D.ready(s,p)
    if not p then return false end
    local u=s.stock_owned_ferry
    return not p.owned or (u and u.owner==p.owner and u.engine_id==p.engine_id and art(u.engine_id))
  end
  function D.count_tick(s,p)
    if not p or not p.owned or p.stopped then return end
    local u=assert(s.stock_owned_ferry)
    u.running_ticks=u.running_ticks+1
  end
  function D.settle(s,p)
    local u=s.stock_owned_ferry
    if not u or not p or not p.owned then return end
    local ticks=u.running_ticks-u.charged_ticks
    if ticks<=0 then return end
    local c=Sim.company(s,u.owner)
    local amount=Roster.running_fixed(u.engine_id,ticks,s.stock_ship_running_base)
    local old=c.stock_money_fraction or 0
    local rem=(old-amount%256)%256
    local debit=math.floor(amount/256)+(rem>old and 1 or 0)
    c.stock_money_fraction=rem
    c.cash,c.expense,c.month_exp=c.cash-debit,c.expense+debit,c.month_exp+debit
    if Sim.stock_economy_money then Sim.stock_economy_money(c,"ship_run",debit) end
    if Sim.stock_vehicle_operating then Sim.stock_vehicle_operating(s,u,-debit) end
    u.expense,u.charged_ticks=u.expense+debit,u.running_ticks
  end
  return D
end
