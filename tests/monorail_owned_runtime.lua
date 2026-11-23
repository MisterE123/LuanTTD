-- SPDX-License-Identifier: GPL-2.0-only
-- Real paid X2001 route, native host adapters without graphics.
local mod="mods/luanttd_core/"
local function m(name) return dofile(mod..name..".lua") end
local Sim,T,Slope,Types=m("sim"),m("openttd/terrain"),m("openttd/slope"),m("openttd/rail_types")
local Codec=m("packed_campaign")
local Bind=m("campaign_simulation_bindings")(Sim,mod:sub(1,-2))
local s=Sim.new(1751)
local with_spans=arg and arg[1]=="spans"
local owner="Monorail Works"
s.sites={}
s.corner_grid=T.new(Sim.W,Sim.H,function(x)
  if not with_spans then return 0 end
  if x>=14 and x<=18 then return 5 end
  if x==7 or x==8 then return 3 end
  return 4
end)
for i=1,#s.tiles do local _,h=T.tile(s.corner_grid,Sim.xy(i));s.tiles[i]={terrain="grass",h=h,variant=0} end
for i,x in ipairs({12,38}) do
  s.sites[i]={id=i,kind="town",name=i==1 and "West" or "East",tile=Sim.id(x,16),population=800,
    stock={},produced={},received={},service=0}
  for z=15,17 do for dx=-3,4 do
    local t=s.tiles[Sim.id(x+dx,z)]
    t.house=true
    t.source_house={id=dx%2==0 and 4 or 1,town=i,completed=true}
  end end
end
Sim.company(s,owner).cash=300000
local function mount(world)
  Bind.road(world,{start_year=2010,foster=true,breakdowns=0,service_interval=0,extra={}} )
  Bind.towns(world)
  local function terrain(id) return T.tile(world.corner_grid,Sim.xy(id)) end
  local net=Bind.networks(world,Slope,terrain)
  net.motion=m("openttd/rail_motion")(net.track)
  net.speed=m("openttd/rail_station_speed")(net.track,net.follow)
  net.owned=true
  local run,signal,roster=Bind.rail(world,net)
  net.dispatch=run
  world.rail_paid_service=true
  Sim.mount_paid_rail(world,run)
  Bind.water(world,net.track,function() return false end)
  local owned=Bind.owned_rail(world,net.lab,roster,run,function()return false end)
  assert(owned.mount_advanced(Types,{[54]=true,[57]=true,[58]=true}))
  Sim.mount_rail_mail(world,true,{})
  local tools=Bind.rail_build({s=world,Sim=Sim,terrain={tile=terrain},render={update=function()end},
    save=function()end,company_can_build_stock_railtype=function(who,gauge)
      return Types.available(gauge,owned.railtype_mask(world,who,Types))
    end},net,run,signal)
  return owned,run,tools,net.spans
end
local depot,first,second=Sim.id(with_spans and 2 or 6,19),Sim.id(with_spans and 10 or 11,19),Sim.id(37,19)
local O,R,C,W=mount(s)
local function rail(x0,x1)
  assert(C.build(owner,assert(C.quote_track(owner,Sim.id(x0,19),Sim.id(x1,19),0,false,2))))
end
if with_spans then
  local function allowed(n,typ) return Types.available(typ,O.railtype_mask(s,n,Types)) end
  local a,b,m=Sim.id(5,19),Sim.id(9,19),Sim.id(13,19)
  assert(not W.quote_bridge(s,owner,a,b,2))
  assert(not W.quote_tunnel(s,owner,m,2))
  local bridge=assert(W.quote_bridge(s,owner,a,b,2,allowed))
  local normal=assert(W.quote_bridge(s,owner,a,b))
  assert(bridge.railtype==2 and bridge.price>normal.price)
  assert(W.commit(s,owner,bridge,allowed))
  local tunnel=assert(W.quote_tunnel(s,owner,m,2,allowed))
  normal=assert(W.quote_tunnel(s,owner,m))
  assert(tunnel.railtype==2 and tunnel.price>normal.price and tunnel["end"]~=tunnel.start)
  assert(W.commit(s,owner,tunnel,allowed))
  assert(W.by_portal(s,tunnel.start).tail.railtype==2 and W.by_portal(s,bridge.start).head.railtype==2)
  local exit=Sim.xy(tunnel["end"]);rail(3,4);rail(10,12);rail(exit+1,43)
else
  rail(7,43)
end
assert(C.build(owner,assert(C.quote_depot(owner,depot,2,2))))
for _,x in ipairs({with_spans and 10 or 11,37}) do
  local q=assert(C.quote_station(owner,Sim.id(x,19),Sim.id(x+2,19),{axis=0,drag=true,separate=true,railtype=2}))
  assert(C.build(owner,q))
end
local quote=assert(O.quote(s,owner,depot,{54,57,58}))
local id=assert(O.commit(s,owner,quote)).id
local ok,why=O.start_order_list(s,owner,id,{s.tiles[first].rail_station_id,s.tiles[second].rail_station_id})
assert(ok,why)
local watched
for _=1,130 do
  Sim.daily(s)
  local status=Sim.rail_paid_status(s,id)
  if status and status.cargo_onboard and status.cargo_onboard.passenger>0 and status.cargo_onboard.mail>0 then
    watched=status
    break
  end
end
assert(watched,"ordinary X2001 never took both passenger and Mail cargo")
local before=R.current(s).runs[1]
assert(before.stock_engine==54 and before.engine_railtype==2 and before.traction_railtypes[2] and not before.traction_railtypes[0])
assert(watched.cargo_capacity.passenger==45 and watched.cargo_capacity.mail==35)
s=Codec.decode(Codec.encode(s))
O,R=mount(s)
local seen=false
for _=1,150 do
  Sim.daily(s)
  local p=Sim.rail_paid_status(s,id)
  local r=R.current(s).runs[1]
  assert(not R.current(s).failure,R.current(s).failure)
  if p and p.cargo_totals and p.cargo_totals.passenger and p.cargo_totals.mail and r.shuttle.reversals>0 then
    local passengers,mail=p.cargo_totals.passenger,p.cargo_totals.mail
    if (passengers.route or 0)>0 and (mail.route or 0)>0 then
      print(("PASS paid monorail from typed depot%s: %d passengers and %d Mail delivered after restore"):format(with_spans and " across a real bridge and bore" or "",passengers.delivered or 0,mail.delivered or 0))
      seen=true
      break
    end
  end
end
assert(seen,"X2001 did not complete a paid round trip after checkpoint")
