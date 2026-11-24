-- SPDX-License-Identifier: GPL-2.0-only
-- Native authority and SQLite restart, using acknowledged command tokens.
local mod=core.get_modpath(core.get_current_modname())
local function m(p) return dofile(mod.."/"..p..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local client=m("campaign_authority_client")(core,mod)
local file="luanttd-wide-campaign.chk"
local checkpoint=m("campaign_checkpoint")(core,m("packed_campaign"),file)
local initial=checkpoint.read()
local actor="North Reach Aviation"
local balance=120000
local function cell(x,z) return (z-1)*64+x end
local profile=core.settings:get("luanttd_qa_rotary_field") or "country"
local stock=tonumber(core.settings:get("luanttd_qa_rotary_model")) or 253
local model=assert(m("openttd/airport_roster").entry(stock))
assert(model.helicopter)
local manifest=m("airport_manifest")(core,mod)
assert(manifest[stock] and manifest[stock].rotor and manifest[stock].tail_rotor)
local cap={road={start_year=stock==254 and 2001 or 1965,foster=true,breakdowns=0,service_interval=0},
  air={[215]=true,[stock]=true},ferry={},city_airport=true,oil_tanker=true,durable_actions=true}
for _,id in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..id,"air") end
if not initial then
  local s=Sim.new(1751)
  Sim.W,Sim.H=64,64
  s.sites,s.tiles={},{}
  s.corner_grid=T.new(64,64,function(_,z) return z<33 and 1 or 0 end)
  for z=1,64 do for x=1,64 do
    s.tiles[cell(x,z)]={h=z<33 and 1 or 0,variant=1,terrain=z<33 and "grass" or "water",
      water_class=z>=33 and "sea" or nil}
  end end
  s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
  s.road_oil,s.air_paid_service,s.air_owned_preview,s.air_fleet_preview=true,true,true,true
  s.stock_serve_neutral_industries=false
  s.sites[1]={id=1,name="North Reach",kind="town",tile=cell(8,11),population=600,stock={},produced={},received={},service=0}
  s.tiles[cell(8,11)].site=1
  for x=8,19 do for z=15,19 do
    local t=s.tiles[cell(x,z)]
    t.house,t.source_house=true,{id=x%2==0 and 4 or 1,town=1,completed=true}
  end end
  local W=assert(Sim.mount_oil_world(s,T,true))
  local opt={economy_year=1965,name="North Reach Oil Rig",random=function() return 0 end,initial_random=122}
  local ind=assert(W.offshore.place(s,assert(W.offshore.quote(s,cell(12,47),opt)),opt))
  assert(ind.id==0x3000 and not ind.neutral_station)
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
  assert(r.ok,kind..": "..tostring(r.why))
  revision=r.revision or revision
  return r.value
end
local function cmd(kind,p)
  p.kind,p.revision=kind,revision
  return ask("command",{command=p})
end
local function commit(rq)
  local q=ask("transport_quote",{request=rq})
  return cmd("transport_commit",{token=q.token})
end
local function view()
  local groups=ask("actor_frames",{windows={{x=1,z=8,w=31,h=28},{x=1,z=36,w=31,h=24}},fraction=1})
  for _,group in ipairs(groups) do for _,r in ipairs(group.actors) do
    if r.mode=="air" and r.engine==stock then
      assert(r.rotor_period~=nil and r.rotor_period>=0)
      return true,r.pos.y
    end
  end end
end
local function snapshot()
  local s=assert(checkpoint.read())
  local rig=assert(s.stock_oil_industries[0x3000])
  assert(rig.neutral_station==1 and s.stock_neutral_stations[1].industry==rig.id)
  local run=assert(s.airport_owned_runs[1])
  local v=assert(s.stock_ship_commercial.service.vehicles[0xC001])
  assert(run.engine_id==stock and run.vehicle.helicopter and not run.failure,run.failure)
  assert(v.air_mail and #v.carrying_parts==2)
  assert(v.carrying_parts[1].capacity==model.passengers and v.carrying_parts[2].capacity==model.mail)
  return s,run,v,rig
end
local function work()
  if not initial then
    for _=1,150 do
      ask("advance",{days=1});ask("checkpoint")
      if checkpoint.read().stock_oil_industries[0x3000].neutral_station then break end
    end
    local field=commit({mode="air",operation="build",layout=profile,tile=cell(12,20)}).id
    local airport=ask("depot",{mode="air",depot=field})
    local offer
    for _,row in ipairs(airport.offers) do if row.request.engine==stock then offer=row end end
    assert(offer and offer.price==(stock==254 and 46484 or 41015) and offer.help.model:find(model.passengers.." seats",1,true))
    local v=commit(offer.request)
    cmd("transport_start",{mode="air",vehicle=v.id,first=field,second=1})
    local orders=ask("orders",{mode="air",vehicle=v.id,page=1})
    assert(orders.items[2].id==1 and orders.items[2].label:find("Oil Rig",1,true))
    local mixed,shown=false,false
    for _=1,260 do
      ask("advance",{days=1});shown=view() or shown;ask("checkpoint")
      local s,r,v,rig=snapshot()
      if r.last_airfield==1 then assert(r.last_terminal_tile==cell(12,47)) end
      local cargo=v.cargo_totals or {}
      mixed=mixed or (cargo.mail and cargo.mail.delivered>0 and cargo.passenger and cargo.passenger.delivered>0)
      if mixed and shown then
        for _,p in ipairs(v.carrying_parts[1].batches or {}) do
          if p.source_type=="industry" and p.source==rig.id then
            goal=("OFFSHORE_ROTARY_NATIVE_SAVED %d passengers from rig after prior outbound Mail"):format(
              v.carrying_parts[1].units)
            return {kind="stop"}
          end
        end
      end
    end
    error("Did not board real rig passengers")
  else
    local saved=initial.stock_ship_commercial.service.vehicles[0xC001]
    local s,r,v,rig=snapshot()
    local baseline=s.companies[actor].revenue
    assert(saved.carrying_parts[1].units==v.carrying_parts[1].units)
    assert(initial.airport_owned_runs[1].vehicle.rotor_speed==r.vehicle.rotor_speed)
    local target=v.carrying_parts[1].units+v.cargo_totals.passenger.delivered
    for _=1,150 do
      ask("advance",{days=1});ask("checkpoint")
      s,r,v=snapshot()
      if r.last_airfield~=1 and v.cargo_totals.passenger.delivered>=target then
        local c=s.companies[actor]
        assert(c.revenue==v.route_profit and c.revenue>baseline and c.cash==balance-c.expense+c.revenue)
        assert(c.paid_units==v.delivered and r.finance.expense>0)
        goal=("OFFSHORE_ROTARY_NATIVE_PASS %s #%d airport restored and paid fare; %d people and %d bags total $%d")
          :format(profile,stock,v.cargo_totals.passenger.delivered,v.cargo_totals.mail.delivered,c.revenue)
        return {kind="stop"}
      end
    end
    error("Real rig passengers did not reach their land field")
  end
end
core.register_on_mods_loaded(function()
  thread=coroutine.create(work)
  assert(client.start(cap,function(info)
    assert(info.ready);revision=info.revision;resume(info)
  end,function(reason,_,_,detail)
    assert(reason=="stopped" and goal,tostring(detail or reason))
    core.log("action",goal)
    core.request_shutdown("Stock offshore helicopter verified",false,0)
  end,file))
end)
