-- Luanti worker: SH 125 with independent 4-bag heads
-- and a 40-seat coach. Checkpoint then native process restart.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local Track=m("openttd/rail_track")
local Roster=m("openttd/rail_roster")
local client=m("campaign_authority_client")(core,mod)
local file="luanttd-wide-campaign.chk"
local checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),file)
local initial=checkpoint.read()
local actor="RC1 SH 125 Express"
local balance=300000
local function cell(x,z) return (z-1)*64+x end
local function tile(x) return cell(x,17) end
local first,second,depot=tile(11),tile(45),tile(6)
local cap={road={start_year=1984,foster=true,breakdowns=0,service_interval=0},
  rail=m("rail_dispatch_manifest").scan(mod,false,false),ferry={},air={},oil_tanker=true,durable_actions=true}
assert(cap.rail.ready.sh_125 and cap.rail.ready.mail_van)
for _,id in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..id,"air") end
if not initial then
  local s=Sim.new(1725)
  Sim.W,Sim.H=64,64
  s.sites,s.tiles={},{}
  s.corner_grid=T.new(64,64,function() return 1 end)
  for i=1,4096 do s.tiles[i]={h=1,terrain="grass",variant=1} end
  s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
  s.rail_owned_service,s.rail_span_enabled,s.rail_paid_service=true,true,true
  for i,x in ipairs({11,45}) do
    s.sites[i]={id=i,kind="town",name=i==1 and "Western Vale" or "East End",tile=cell(x,14),
      population=600,stock={},produced={},received={},service=0}
    for z=12,15 do for dx=-2,5 do
      local t=s.tiles[cell(x+dx,z)]
      t.house=true
      t.source_house={id=dx%2==0 and 4 or 1,town=i,completed=true}
    end end
  end
  Sim.company(s,actor).cash=balance
  checkpoint.write_state(s)
end
local thread,revision,goal
local function resume(r)
  local ok,req=coroutine.resume(thread,r)
  assert(ok,req)
  if req then assert(client.query(req,resume)) end
end
local function ask(kind,fields)
  fields=fields or {};fields.kind,fields.player=kind,actor
  local r=assert(coroutine.yield(fields))
  assert(r.ok,tostring(r.why))
  revision=r.revision or revision
  return r.value
end
local function cmd(kind,p)
  p.kind,p.revision=kind,revision
  return ask("command",{command=p})
end
local function lay(p)
  local q=ask("rail_quote",{request=p})
  return cmd("rail_commit",{token=q.token})
end

local function visual()
  local groups=ask("actor_frames",{windows={{x=5,z=15,w=26,h=4},{x=31,z=15,w=27,h=4}},fraction=1})
  for _,sector in ipairs(groups) do for _,r in ipairs(sector.actors) do
    if r.mode=="rail" and r.complete_parts and #r.parts==3 then
      local p=r.parts
      assert(p[1].kind=="sh_125" and p[2].kind=="wagon" and p[3].kind=="sh_125")
      assert(p[1].stock_id==22 and p[2].stock_id==27 and p[3].stock_id==22)
      assert(p[1].body_id and p[2].body_id and p[3].body_id and p[1].body_id~=p[3].body_id)
      return true,p[1].reversed
    end
  end end
end
local function payload()
  local s=assert(checkpoint.read())
  local r=assert(s.stock_rail_dispatch.runs[1])
  local v=assert(s.stock_ship_commercial.service.vehicles[0x4000+r.paid_clock])
  assert(r.stock_engine==22 and r.express_mail and r.dual_head and v.linked_heads and v.cargo=="mixed")
  assert(r.max_track_speed==200 and r.total_length==24)
  local front,coach,rear=unpack(v.carrying_parts)
  assert(#v.carrying_parts==3 and front.role=="front_mail" and coach.role=="carriage" and rear.role=="rear_mail")
  assert(front.capacity==4 and rear.capacity==4 and coach.capacity==40)
  assert(front.stock==22 and rear.stock==22 and coach.stock==27 and front.body_id~=rear.body_id)
  local stats=assert(Roster.stats({{stock_id=22,cargo_count=front.units,rear_cargo_count=rear.units},
    {stock_id=27,cargo_count=coach.units}}))
  assert(v.units==front.units+coach.units+rear.units and r.passengers_onboard==coach.units
    and r.mail_onboard==front.units+rear.units and r.consist_mass==stats.weight)
  return s,r,v,{front.units,coach.units,rear.units}
end
local function work()
  if not initial then
    lay({tool="track",first=tile(7),last=tile(55),track=Track.X})
    lay({tool="depot",first=depot,direction=Track.SW})
    for _,x in ipairs({11,45}) do
      lay({tool="station",first=tile(x),last=tile(x+2),axis=0,length=3,tracks=1,separate=true,drag=true})
    end
    local panel=ask("depot",{mode="rail",depot=depot})
    local offer
    for _,o in ipairs(panel.offers) do
      local ids=o.request.parts
      if ids[1]==22 and ids[2]==27 then offer=o end
    end
    assert(offer and offer.help.model:find("40 seats",1,true) and offer.help.model:find("8 Mail bags",1,true))
    local q=ask("transport_quote",{request=offer.request})
    local train=cmd("transport_commit",{token=q.token}).id
    ask("checkpoint")
    local t=checkpoint.read().tiles
    local from,to=t[first].rail_station_id,t[second].rail_station_id
    cmd("transport_start",{mode="rail",vehicle=train,first=from,second=to})
    local order=ask("orders",{mode="rail",vehicle=train,page=1})
    assert(order.items[1].id==from and order.items[2].id==to)
    cmd("vehicle_order",{mode="rail",vehicle=train,order_revision=order.revision,operation="load",row=1,destination=2})
    local displayed=false
    for _=1,270 do
      ask("advance",{days=1})
      displayed=visual() or displayed
      ask("checkpoint")
      local _,r,v,p=payload()
      if displayed and not v.delivered and p[1]>0 and p[2]>0 and p[3]>0 then
        goal=("EXPRESS_MAIL_NATIVE_SAVED %d Mail / %d people / %d Mail"):format(unpack(p))
        return {kind="stop"}
      end
    end
    error("No native #22 departure boarded both holds and the coach")
  end
  local s,r,v,p=payload()
  local saved=initial.stock_ship_commercial.service.vehicles[v.id]
  for i,u in ipairs(p) do assert(u>0 and saved.carrying_parts[i].units==u) end
  assert(not v.delivered and visual())
  local reversed
  for _=1,220 do
    ask("advance",{days=1})
    local _,rev=visual();reversed=reversed or rev
    ask("checkpoint")
    s,r,v=payload()
    if reversed and (v.delivered or 0)>0 and v.cargo_totals and v.cargo_totals.mail and v.cargo_totals.passenger then
      local c=assert(s.companies[actor])
      local mail,people=v.cargo_totals.mail,v.cargo_totals.passenger
      assert(c.paid_units==v.delivered and c.revenue==v.route_profit and c.cash==balance-c.expense+c.revenue,
        ("units %s/%s revenue %s/%s cash %s vs %s (expenses %s Day %s) Mail %s/%s riders %s/%s"):format(
          c.paid_units,v.delivered,c.revenue,v.route_profit,c.cash,balance-c.expense+c.revenue,c.expense,s.day,
          mail.delivered,mail.route,people.delivered,people.route))
      assert(mail.delivered==8 and people.delivered==40 and mail.route>0 and people.route>0)
      assert(mail.delivered+people.delivered==c.paid_units and mail.route+people.route==c.revenue)
      assert(r.passenger_finance.expense>0 and r.shuttle.reversals>0)
      goal=("EXPRESS_MAIL_NATIVE_PASS restored %d/%d/%d, paid %d riders and %d bags for $%d across reversal")
        :format(p[1],p[2],p[3],people.delivered,mail.delivered,c.revenue)
      return {kind="stop"}
    end
  end
  error("Real #22 had no combined payout")
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(work)
  assert(client.start(cap,function(info)
    assert(info.ready);revision=info.revision;resume(info)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and goal,tostring(detail or reason))
    core.log("action",goal)
    core.request_shutdown("Ordinary stock SH 125 Mail verified",false,0)
  end,file))
end)
