-- A purchased passenger hull remains company property while stopped or
-- between orders. The shared passenger clock owns loading and fares.
return function(Sim,Roster,Calendar,Run,art)
  local D={}
  function D.offer(s,id)
    if not art(id) then return end
    local r=Roster.quote(id,s.stock_ship_purchase_base)
    if not r then return end
    local market=s.stock_bus_market -- same stock campaign epoch and seed
    local cfg=market and market.settings
    if not cfg then return end
    local record=assert(Calendar.prepare_original(r,cfg))
    local status=assert(Calendar.snapshot(record,market.epoch+s.day))
    return status.public and r or nil
  end
  function D.quote(s,owner,depot,id)
    if s.stock_owned_ferry then return nil,"The current passenger fleet supports one owned ferry." end
    if Run.current(s) then return nil,"Clear the active test ferry before buying a vessel." end
    local q=(s.stock_ship_depots or {})[depot]
    if not q or q.owner~=owner then return nil,"Choose a ship depot you own." end
    if s.stock_coal_ship and s.stock_coal_ship.depot==depot then return nil,"The Yate already uses this depot." end
    local r=D.offer(s,id)
    return r,r and nil or "That ferry is not on sale."
  end
  function D.buy(s,owner,depot,id)
    local quote,why=D.quote(s,owner,depot,id)
    if not quote then return nil,why end
    local c=Sim.company(s,owner)
    if c.cash<quote.price then return nil,"Not enough cash for this ferry." end
    c.cash,c.expense,c.month_exp=c.cash-quote.price,c.expense+quote.price,c.month_exp+quote.price
    local unit={owner=owner,depot=depot,engine_id=id,price=quote.price,built=Sim.date(s),
      running_ticks=0,charged_ticks=0,expense=0}
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
    u.expense,u.charged_ticks=u.expense+debit,u.running_ticks
  end
  return D
end
