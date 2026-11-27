-- SPDX-License-Identifier: GPL-2.0-only
-- Campaign authority adapter for RC1 subsidy.cpp. No separate clock:
-- the worker calls month from its economy boundary before Town rotates
-- the previous-month inputs. Load/unload adapters call pay only after
-- actual final acceptance, never for reservation or transfer credit.
return function(Rules,Host)
  local M={}
  local event_by_world=setmetatable({},{__mode="k"})
  local function book(s) return s.stock_economy_subsidies end

  function M.mount(s,opts)
    if not s.stock_town_growth then return nil,"STOCK_TOWNS_REQUIRED" end
    local state=book(s)
    if not state then
      state=Host.new()
      state.duration,state.multiplier=1,2
      s.stock_economy_subsidies=state
    end
    if opts then
      if opts.duration~=nil then state.duration=opts.duration end
      if opts.multiplier~=nil then state.multiplier=opts.multiplier end
      event_by_world[s]=opts.event
    end
    Host.board(s,state) -- derive participants from actual loaded records
    return state
  end
  local function event(s)
    local callback=event_by_world[s]
    if callback then return function(kind,entry) callback(s,kind,entry) end end
  end
  function M.month(s,ordinal,random)
    local state=book(s)
    if not state then return false end
    if state.last_month and state.last_month>=ordinal then return false end
    local board=Host.board(s,state)
    state.last_month=ordinal
    return Rules.month(state.subsidies,board,state.duration,random,event(s))
  end
  function M.placed(s,chain,native)
    local state=book(s)
    return state and Host.register(state,chain,native)
  end
  function M.removed(s,chain,native)
    local state=book(s)
    return state and Host.remove(state,chain,native)
  end
  function M.pay(s,cargo,owner,p,amount,coverage,chain,neutral_industry)
    local state=book(s)
    if not state or state.subsidies.count==0 then return amount end
    -- Build station geometry lazily, only for the first offer matching
    -- this genuine source and owner. Most paid packets have no subsidy.
    return Host.deliver(s,state,cargo,owner,p,amount,coverage,chain,neutral_industry,event(s))
  end
  function M.entries(s)
    local state=book(s)
    local rows={}
    if not state then return rows end
    for id=0,Rules.MAX-1 do
      local e=state.subsidies.rows[id]
      if e then rows[#rows+1]={id=id,cargo=e.cargo,remaining=e.remaining,awarded=e.awarded,
        src={id=e.src.id,type=e.src.type},dst={id=e.dst.id,type=e.dst.type}} end
    end
    return rows
  end
  return M
end
