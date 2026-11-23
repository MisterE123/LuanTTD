-- SPDX-License-Identifier: GPL-2.0-only
-- Ordinary worker route, stock rotary transition at both ends and real
-- two-way passengers, outward Mail, neutral station, save/rebind and fares.
local root="mods/luanttd_core/"
local function m(n) return dofile(root..n..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local Rig=m("openttd/oil_rig")
local compose=m("campaign_authority_runtime")
local Endpoint=m("campaign_authority_endpoint")
local owner="North Reach Aviation"
local size=64
local balance=120000
local profile=arg[1]=="city" and "city" or "country"
local function cell(x,z) return (z-1)*size+x end
local function copy(t)
  if type(t)~="table" then return t end
  local b={};for k,v in pairs(t) do b[k]=copy(v) end;return b
end
local s=Sim.new(1751)
Sim.W,Sim.H=size,size
s.sites,s.tiles={},{}
s.corner_grid=T.new(size,size,function(_,z) return z<33 and 1 or 0 end)
for z=1,size do for x=1,size do
  s.tiles[cell(x,z)]={h=z<33 and 1 or 0,variant=1,terrain=z<33 and "grass" or "water",
    water_class=z>=33 and "sea" or nil}
end end
s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
s.road_oil,s.air_paid_service,s.air_owned_preview,s.air_fleet_preview=true,true,true,true
s.stock_serve_neutral_industries=false
s.sites[1]={id=1,name="North Reach",kind="town",tile=cell(8,11),population=600,stock={},produced={},received={},service=0}
s.tiles[cell(8,11)].site=1
for x=8,19 do for z=15,19 do
  local tile=s.tiles[cell(x,z)]
  tile.house,tile.source_house=true,{id=x%2==0 and 4 or 1,town=1,completed=true}
end end
local W=assert(Sim.mount_oil_world(s,T,true))
local p={economy_year=1965,name="North Reach Oil Rig",random=function() return 0 end,initial_random=122}
local firm=assert(W.offshore.place(s,assert(W.offshore.quote(s,cell(12,47),p)),p))
Sim.company(s,owner).cash=balance
local rt,authority
local cap={road={start_year=1965,foster=true,breakdowns=0,service_interval=0},ferry={},air={[215]=true,[253]=true},
  city_airport=true,oil_tanker=true}
local function mount()
  rt=compose(Sim,root:sub(1,-2),s,cap)
  authority=Endpoint(Sim,rt)
end
mount()
for _=1,150 do
  rt.day()
  if firm.neutral_station then break end
end
local rig=assert(firm.neutral_station)
assert(s.stock_neutral_stations[rig].industry==firm.id and not s.stock_small_airports[rig].owner)

local q
local function commit(args)
  q=authority.transport_quote(owner,args)
  assert(q.ok,q.why)
  local r=authority.command(owner,{kind="transport_commit",token=q.value.token,revision=q.revision})
  assert(r.ok,r.why)
  q=r
  return r.value
end
local field=commit({mode="air",operation="build",tile=cell(12,20),layout=profile}).id
assert(not rt.air.run.fits(s.stock_small_airports[rig],215))
assert(not rt.air.network.quote(s,owner,cell(12,46),"oilrig"))
local candidates=assert(rt.transport.depot(owner,"air",field))
local offer
for _,o in ipairs(candidates.offers) do if o.request.engine==253 then offer=o end end
assert(offer and offer.price==41015)
local unit=commit(offer.request)
local panel=assert(rt.transport.depot(owner,"air",field))
local target
for _,t in ipairs(panel.targets) do if t.id==rig then target=t end end
assert(target and target.label:find("Oil Rig",1,true))
local result=authority.command(owner,{kind="transport_start",mode="air",vehicle=unit.id,first=field,second=rig,
  revision=q.revision})
assert(result.ok,result.why)
local orders=assert(rt.orders.air.read(owner,unit.id))
assert(#orders.items==2 and orders.items[2].id==rig and orders.items[2].label:find("Oil Rig",1,true))

local seen,restored,inbound_mail,returned,oil_station
for _=1,400 do
  rt.day()
  local r=assert(rt.air.run.current(s,unit.id))
  assert(not r.failure,r.failure)
  local service=s.stock_ship_commercial.service
  local v=assert(service.vehicles[0xC000+unit.id])
  oil_station=service.stations[0xC000+rig]
  assert(v.air_mail and #v.carrying_parts==2)
  assert(oil_station.owner==false and oil_station.neutral_rig==firm.id)
  if r.last_airfield==rig then
    seen=true
    assert(r.last_terminal_tile==cell(12,47))
  end
  local f=v.cargo_totals or {}
  inbound_mail=inbound_mail or f.mail and f.mail.delivered>0
  for _,b in ipairs(v.carrying_parts[1].batches or {}) do
    if b.source_type=="industry" and b.source==firm.id then
      returned=true
      if not restored then
        assert(r.target==rig or r.target==field)
        local units=v.carrying_parts[1].units
        s=copy(s)
        mount()
        assert(s.stock_ship_commercial.service.vehicles[v.id].carrying_parts[1].units==units)
        restored=true
      end
    end
  end
  if restored and seen and inbound_mail and returned and r.last_airfield==field and f.passenger and f.passenger.delivered>45 then
    local c=assert(s.companies[owner])
    assert(c.revenue==v.route_profit and c.paid_units==v.delivered and c.cash==balance-c.expense+c.revenue)
    assert(f.passenger.delivered+f.mail.delivered==v.delivered and r.finance.expense>0)
    print(("PASS Tricario stock %s / Oil Rig service: %d people + %d Mail for $%d, rig-origin packets restored"):format(
      profile,f.passenger.delivered,f.mail.delivered,c.revenue))
    return
  end
end
error("Tricario never delivered cargo from both ends")
