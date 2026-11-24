-- No engine globals. The worker-side endpoint uses the ordinary stock Sim rules.
local mod="mods/luanttd_core"
local Sim=dofile(mod.."/sim.lua")
local T=dofile(mod.."/openttd/terrain.lua")
local s=Sim.new(1751)
s.corner_grid=T.new(Sim.W,Sim.H,function() return 0 end)
for _,tile in ipairs(s.tiles) do
  tile.terrain,tile.h="grass",0
  tile.wood,tile.house,tile.site,tile.build,tile.owner=nil,nil,nil,nil,nil
end
local runtime=dofile(mod.."/campaign_authority_runtime.lua")(Sim,mod,s,{
  road={start_year=1950,breakdowns=0,service_interval=150},
})
local A=dofile(mod.."/campaign_authority_endpoint.lua")(Sim,runtime)
local john="Authorised"
local p,q,d=Sim.id(4,7),Sim.id(14,7),Sim.id(8,8)
local build={kind="road_build",first=p,last=q,revision=0}
local built=A.command(john,build)
assert(built.ok and built.revision==1)
local cash=s.companies[john].cash
assert(not A.command(john,build).ok and cash==s.companies[john].cash)
assert(not A.snapshot(1,1,33,1).ok and not A.snapshot(0,1,1,1).ok)
local patch=A.snapshot(4,7,11,1)
assert(patch.ok and #patch.value.tiles==11 and patch.value.tiles[1].id==p)
for _,tile in ipairs(patch.value.tiles) do assert(tile.build=="road" and tile.road and tile.road>0) end
patch.value.tiles[1].build="changed in projection"
assert(s.tiles[p].build=="road")
assert(Sim.build(s,john,"road_station",{p,q}))
assert(Sim.build(s,john,"road_depot",{d}))
local id=assert(Sim.purchase(s,john,"bus","passenger",nil,d))
local first={kind="vehicle_order",mode="road",vehicle=id,tile=p,operation="append",
  order_revision=A.orders(john,"road",id).value.revision,revision=1}
assert(not A.command("Not owner",first).ok)
assert(not A.command(john,{kind="vehicle_order",mode="road",vehicle=id,tile=d,operation="append",
  order_revision=first.order_revision,revision=1}).ok,"a depot is not a passenger stop")
local raw_owner=s.stations[s.tiles[p].station].owner
s.stations[s.tiles[p].station].owner="Rival"
assert(not A.command(john,first).ok,"a rival's stop cannot be picked")
s.stations[s.tiles[p].station].owner=raw_owner
local added=A.command(john,first)
assert(added.ok and added.revision==2 and added.value.count==1)
assert(not A.command(john,first).ok,"an obsolete command must not append twice")
local second={kind="vehicle_order",mode="road",vehicle=id,tile=q,operation="append",
  order_revision=added.value.order_revision,revision=2}
assert(not A.command(john,{kind=second.kind,mode=second.mode,vehicle=id,tile=q,destination=s.tiles[p].station,
  operation=second.operation,order_revision=second.order_revision,revision=2}).ok,"mixed tile and station ID")
local assembled=A.command(john,second)
assert(assembled.ok and assembled.revision==3 and assembled.value.count==2)
assert(s.fleet[id].orders[1].station==s.tiles[p].station and s.fleet[id].orders[2].station==s.tiles[q].station)
assert(A.command(john,{kind="road_toggle",vehicle=id,revision=3}).revision==4)
assert(not A.advance(5).ok and A.advance(1).tick==74)
local close=A.snapshot(3,6,24,12)
local far=A.snapshot(35,22,4,3)
assert(close.ok and #close.value.vehicles==1 and close.value.vehicles[1].id==id)
assert(far.ok and #far.value.vehicles==0)
assert(s.fleet[id].running)
print("PASS single-owner construction/road orders; stale and foreign edits rejected; scoped projection does not own actors")
do
  local resolve=dofile(mod.."/campaign_order_target.lua")
  local registry={
    stock_rail_stations={[2]={owner=john},[3]={owner="Rival"}},
    stock_ship_stations={[4]={owner=john}},stock_small_airports={[5]={owner=john,layout="city"}}}
  local function record(kind,key) return registry[kind] and registry[kind][key] end
  assert(resolve("rail",1,john,12,{rail_station_id=2},record)==2)
  assert(resolve("rail",1,john,13,{rail_station_id=2},record)==2) -- platform is multi-tile
  assert(not resolve("rail",1,john,13,{rail_station_id=3},record))
  assert(resolve("ship","oil",john,21,{ship={kind="dock",station=4}},record)==4)
  assert(resolve("ship","ferry",john,22,{ship={kind="dock",station=4}},record)==4)
  assert(resolve("ship","ferry",john,23,{ship={kind="buoy",station=7}},record)=="buoy:7")
  assert(not resolve("ship","oil",john,23,{ship={kind="buoy",station=7}},record))
  assert(not resolve("ship","ferry",john,23,{ship={kind="buoy"}},record))
  assert(resolve("air",1,john,31,{airfield={airport=5}},record)==5)
  assert(resolve("tram",1,john,41,{tram={kind="drive_stop",owner=john}},record)==41)
  assert(not resolve("tram",1,john,42,{tram={kind="drive_stop",owner="Rival"}},record))
  print("PASS world target resolves rail platforms, docks, ferry buoys, airports, and owned tram stops")
end
local sectors=A.snapshots({{x=3,z=6,w=24,h=12},{x=35,z=22,w=4,h=3}},.5)
assert(sectors.ok and sectors.tick==74 and #sectors.value==2 and #sectors.value[1].actors==1 and #sectors.value[2].actors==0)
assert(not A.snapshots({{x=1,z=1,w=1,h=1},{x=2,z=2,w=100,h=100}}).ok)
print("PASS multiple sectors captured at the same authoritative tick")
local bend={tool="bend",first=Sim.id(20,10),last=Sim.id(23,13)}
local offer=A.road_quote(john,bend)
assert(offer.ok and offer.revision==4 and #offer.value.tiles>2 and offer.value.cost>0)
local starting_cash=s.companies[john].cash
s.topology=s.topology+1
assert(not A.command(john,{kind="road_commit",revision=4,request=bend,quote=offer.value}).ok)
assert(s.companies[john].cash==starting_cash)
local fresh=A.road_quote(john,bend)
local built_bend=A.command(john,{kind="road_commit",revision=4,request=bend,quote=fresh.value})
assert(built_bend.ok and #built_bend.value==#fresh.value.tiles)
assert(s.companies[john].cash==starting_cash-fresh.value.cost)
print("PASS worker validates and applies the ordinary paid road bend; obsolete topology quote cannot spend")
assert(A.company("Another").why=="COMPANY_NOT_OPEN")
assert(A.command("Another",{kind="company_open",revision=5}).revision==6)
local before=A.company("Another")
assert(before.ok and before.value.day==nil and before.day==1 and before.value.cash>0)
assert(A.command("Another",{kind="company_loan",revision=6,amount=10000}).revision==7)
assert(A.company("Another").value.cash==before.value.cash+10000)
local vehicle=assert(Sim.vehicle_offer(s,"bus"))
assert(not A.command(john,{kind="road_buy",revision=7,engine="bus",cargo="passenger",depot=d,cost=vehicle.cost+1}).ok)
local purchase=A.command(john,{kind="road_buy",revision=7,engine="bus",cargo="passenger",depot=d,cost=vehicle.cost})
assert(purchase.ok and purchase.revision==8 and s.fleet[purchase.value].owner==john)
print("PASS typed company and depot actions charge only the owning company at the quoted price")
local paint=A.snapshot(3,6,17,5)
assert(#paint.value.corners==18*6)
local source=paint.value.tiles[19].surface
assert(source.build==s.tiles[p].build and source.road_bits==s.tiles[p].road_bits)
source.build="visual only"
assert(s.tiles[p].build=="road_station")
print("PASS projected ground, road geometry and shared corners are detached from authoritative tiles")
local s2=Sim.new(1751)
s2.corner_grid=T.new(Sim.W,Sim.H,function() return 0 end)
s2.rail_paid_service,s2.rail_owned_service,s2.rail_block_preview=true,true,true
for _,t in ipairs(s2.tiles) do
  t.terrain,t.h="grass",0
  t.wood,t.house,t.site,t.build,t.owner=nil,nil,nil,nil,nil
end
local rails=dofile(mod.."/campaign_authority_runtime.lua")(Sim,mod,s2,{
  road={start_year=1950,breakdowns=0,service_interval=150},rail={ready={},engines={},split={}},
})
local station_worker=dofile(mod.."/campaign_authority_endpoint.lua")(Sim,rails)
assert(station_worker.command(john,{kind="company_open",revision=0}).ok)
local t0,t1=Sim.id(12,15),Sim.id(21,15)
local rails_offer=station_worker.rail_quote(john,{tool="track",first=t0,last=t1,track=0})
assert(rails_offer.ok and #rails_offer.value.tiles==10 and rails_offer.value.cost>0)
local money=s2.companies[john].cash
assert(not station_worker.command("Stranger",{kind="rail_commit",revision=1,token=rails_offer.value.token}).ok)
assert(station_worker.command(john,{kind="rail_commit",revision=1,token=rails_offer.value.token}).ok)
assert(s2.tiles[t0].rail_tracks==1 and s2.companies[john].cash==money-rails_offer.value.cost)
assert(not station_worker.command(john,{kind="rail_commit",revision=2,token=rails_offer.value.token}).ok)
local depot=station_worker.rail_quote(john,{tool="depot",first=Sim.id(11,15),direction=2})
assert(depot.ok,depot.why)
assert(station_worker.command(john,{kind="rail_commit",revision=2,token=depot.value.token}).ok)
print("PASS worker owns pinned railway track and auto-connecting depot quote, debit and commit")
local plot=Sim.id(36,26)
local land=A.terrain_quote(john,{operation="raise",first=plot})
assert(land.ok and #land.value.corners==1 and land.value.cost>0)
local cost=A.company(john).value.cash
local applied=A.command(john,{kind="terrain_commit",revision=8,token=land.value.token})
assert(applied.ok and T.corner(s.corner_grid,36,26)==1)
assert(A.company(john).value.cash==cost-land.value.cost)
local clear=A.terrain_quote(john,{operation="bulldoze",first=Sim.id(21,10)})
assert(clear.ok and A.command(john,{kind="terrain_commit",revision=9,token=clear.value.token}).ok)
print("PASS worker reshapes shared terrain and bulldozes through the existing paid commands")
local bridge=A.transport_quote(john,{operation="bridge",mode="road",tile=Sim.id(6,24),last=Sim.id(10,24),style=0})
assert(bridge.ok,bridge.why)
local before_bridge=A.company(john).value.cash
local committed=A.command(john,{kind="transport_commit",revision=10,token=bridge.value.token})
assert(committed.ok and #committed.value.tiles==5 and A.company(john).value.cash==before_bridge-bridge.value.cost)
assert(s.bridge_above[Sim.id(8,24)])
print("PASS worker commits a real timber bridge at the stock price and preserves ground below")
local support=A.snapshot(8,24,1,1).value.registries
assert(support.bridge_above and support.stock_road_bridges)
local support_id=support.bridge_above[Sim.id(8,24)]
assert(support.stock_road_bridges[support_id].axis==0 and #support.stock_road_bridges[support_id].middle==3)
assert(not support.stations and not support.fleet and not support.companies)
print("PASS bridge support sectors include the linked span without exposing unrelated simulation registries")
local interest={x=3,z=6,w=17,h=5}
local a=assert(A.snapshots({interest},.5).value)[1]
interest.scene=a.scene
assert(a.tiles and a.corners)
local b=assert(A.snapshots({interest},.6).value)[1]
assert(b.scene==a.scene and not b.tiles and not b.corners and b.actors)
-- A tile can change through the landscape loop without a user command.
local topology=s.topology
s.tiles[Sim.id(3,6)].variant=19
local c=assert(A.snapshots({interest},.7).value)[1]
assert(topology==s.topology and c.scene~=a.scene and c.tiles[1].surface.variant==19)
print("PASS clean scene sends actor-only deltas; non-command scene edits invalidate the exact bounded cache")
s.road_economy,s.road_stock_clock=true,true
local sign={tool="oneway",first=Sim.id(8,19),last=Sim.id(13,19),axis=0,start_half=false,end_half=true}
local company=assert(A.company(john).value)
local offer=A.road_quote(john,sign)
assert(offer.ok,offer.why)
assert(not s.tiles[Sim.id(9,19)].road_disallowed)
local r=A.command(john,{kind="road_commit",revision=offer.revision,request=sign,quote=offer.value})
assert(r.ok,r.why)
assert(s.tiles[Sim.id(9,19)].road_disallowed==1)
assert(s.companies[john].cash==company.cash-offer.value.cost)
assert(not A.command(john,{kind="road_commit",revision=r.revision,request=sign,quote=offer.value}).ok)
print("PASS one-way road gestures keep stock directional restrictions, price, and stale-quote safety on the worker")
local pose=runtime.road_pose
local counted={}
runtime.road_pose=function(v,f)
  counted[v]=(counted[v] or 0)+1
  return pose(v,f)
end
assert(A.snapshots({{x=3,z=6,w=24,h=12},{x=35,z=22,w=4,h=3}},.4).ok)
for _,v in pairs(s.fleet) do assert(counted[v]==1) end
print("PASS one authoritative road pose per vehicle per multi-sector observation")
local support_tile=Sim.id(8,24)
local support_ground=s.tiles[support_tile].terrain
local owned=A.demolition(john,support_tile)
assert(owned.ok and owned.value.options[1].key=="road_bridge" and owned.value.options[1].ok)
local unauthorized=A.demolition("Another",support_tile)
assert(unauthorized.ok and not unauthorized.value.options[1].ok)
local function dismantle(q)
  return {kind="demolition",revision=q.revision,token=q.value.token,layer="road_bridge"}
end
assert(not A.command("Another",dismantle(owned)).ok)
assert(s.bridge_above[support_tile])
s.corner_grid.revision=s.corner_grid.revision+1
assert(not A.command(john,dismantle(owned)).ok and s.bridge_above[support_tile])
local refreshed=A.demolition(john,support_tile)
local removed=A.command(john,dismantle(refreshed))
assert(removed.ok and #removed.value>=5,removed.why)
assert(not s.bridge_above[support_tile] and s.tiles[support_tile].terrain==support_ground)
assert(not A.command(john,{kind="demolition",revision=removed.revision,token=refreshed.value.token,layer="road_bridge"}).ok)
print("PASS layer confirmation is owner-bound, stale selections fail, and bridge removal preserves ground")
local page=A.company_fleet(john,1)
assert(page.ok and page.value.total==2 and page.value.records[1].id==id)
assert(A.company_fleet("Another",1).value.total==0)
assert(A.vehicle(john,"road",purchase.value,true).value.position.x==16.5)
assert(not A.vehicle("Another","road",purchase.value,true).ok)
local own_depot=station_worker.demolition(john,Sim.id(11,15))
assert(own_depot.ok and own_depot.value.options[1].key=="rail_facility")
for i=100,139 do s.fleet[i]={owner=john,id=i,name="Bus "..i,home_depot=d,orders={},engine="bus"} end
local many=A.company_fleet(john,2)
assert(many.ok and many.value.total==42 and many.value.pages==3 and #many.value.records==20 and many.value.records[1].id==118)
local end_page=A.company_fleet(john,4)
assert(end_page.value.page==3 and #end_page.value.records==2)
print("PASS paged company fleet contains only owned units and can locate a parked vehicle without subscribing to terrain")
local steel=A.bridge_picker(john,"road",Sim.id(6,24),Sim.id(10,24))
assert(steel.ok and #steel.value.ids==5 and #steel.value.offers>=1)
local choice=steel.value.offers[1]
assert(choice.name=="Timber" and choice.speed and choice.price==bridge.value.cost)
local function purchase_bridge(q)
  return {kind="bridge_picker",revision=q.revision,token=q.value.token,style=0}
end
assert(not A.command("Another",purchase_bridge(steel)).ok and not s.bridge_above[support_tile])
local prior_funds=s.companies[john].cash
s.corner_grid.revision=s.corner_grid.revision+1
assert(not A.command(john,purchase_bridge(steel)).ok and prior_funds==s.companies[john].cash)
local repeat_quote=A.bridge_picker(john,"road",Sim.id(6,24),Sim.id(10,24))
assert(A.command(john,purchase_bridge(repeat_quote)).ok)
assert(s.bridge_above[support_tile] and s.companies[john].cash==prior_funds-choice.price)
print("PASS worker offers stock bridge styles, does not charge on quote, and applies only the confirmed current offer")
local signal_tile=Sim.id(16,15)
local sig=station_worker.signal_panel(john,signal_tile,nil,4,false)
assert(sig.ok and sig.value.track==0 and sig.value.choices.td0.price and sig.value.choices.td8.price,sig.why)
local witness=station_worker.signal_panel(john,signal_tile,nil,4,false,true)
assert(witness.ok and not witness.value.token)
local function send_signal(r,action)
  return {kind="signal_panel",revision=r.revision,token=r.value.token,action=action}
end
assert(not station_worker.command("Stranger",send_signal(sig,"td0")).ok)
assert(not station_worker.command(john,send_signal(sig,"td9")).ok)
assert(station_worker.command(john,send_signal(sig,"td0")).ok)
local signed=station_worker.signal_panel(john,signal_tile,nil,nil,true)
assert(signed.ok and signed.value.details.dirs[1]==0 and signed.value.choices.flip.price==0)
assert(station_worker.command(john,send_signal(signed,"flip")).ok)
assert(station_worker.signal_panel(john,signal_tile,nil,nil,true).value.details.dirs[1]==2)
print("PASS rail signal selection uses original directional quotes; hovering does not invalidate a chosen signal ticket")
local crossing_at=Sim.id(18,15)
s2.road_economy,s2.road_stock_clock=true,true
local cross=station_worker.rail_quote(john,{tool="crossing",first=crossing_at})
assert(cross.ok and cross.value.cost>0,cross.why)
assert(station_worker.command(john,{kind="rail_commit",revision=cross.revision,token=cross.value.token}).ok)
assert(s2.tiles[crossing_at].level_crossing and s2.tiles[crossing_at].level_crossing.rail_axis==0)
do
  local t=s2.tiles[crossing_at]
  local rm={tool="remove",first=crossing_at,axis=1,start_half=false,end_half=false}
  local across={tool="remove",first=crossing_at,axis=0,start_half=false,end_half=true}
  assert(not station_worker.road_quote(john,across).ok)
  local p=assert(station_worker.road_quote(john,rm).value)
  assert(p.cost==80 and #p.tiles==1 and p.tiles[1]==crossing_at)
  local money=s2.companies[john].cash
  local claims={example={tile=crossing_at,track=0}}
  s2.stock_rail_dispatch={runs={},life={bits={[crossing_at]=1},claims=claims}}
  s2.fleet[901]={id=901,owner=john,engine="bus",road_stop_pose={[4]=crossing_at}}
  assert(not station_worker.road_place(john,rm,p).ok and t.level_crossing and s2.companies[john].cash==money)
  s2.fleet[901]=nil
  local receipt=station_worker.road_place(john,rm,p)
  assert(receipt.ok,receipt.why)
  assert(t.build=="stock_rail" and t.owner==john and t.rail_tracks==1 and t.rail_type==0 and t.road_bits==nil)
  assert(not t.level_crossing and not s2.level_crossing_tiles[crossing_at] and s2.companies[john].cash==money-80)
  assert(s2.stock_rail_dispatch.life.bits[crossing_at]==1 and s2.stock_rail_dispatch.life.claims==claims)
  s2.stock_rail_dispatch=nil
  print("PASS removing one road half of an empty crossing restores the same plain rail, including its untouched reservation")
end
s.road_mail,s.road_stock_house_supply=true,true
local truck_at=Sim.id(12,7)
local loading={tool="truck_stop",first=truck_at}
local freight=A.road_quote(john,loading)
assert(freight.ok,freight.why)
assert(A.command(john,{kind="road_commit",revision=freight.revision,request=loading,quote=freight.value}).ok)
assert(s.stations[s.tiles[truck_at].station].stop_type=="truck")
assert(s.stations[s.tiles[truck_at].station].freight_art)
print("PASS native crossing and freight loading stop use stock construction and retain their paid presentation metadata")
local chart=A.jump_map(john,false,p)
assert(chart.ok and chart.value.cols<=24 and chart.value.rows<=24 and
  #chart.value.pixels==chart.value.pixel_cols*chart.value.pixel_rows)
assert(next(chart.value.targets) and #chart.value.towns>=1)
assert(not A.jump_map(john,true,p,Sim.W*Sim.H+1).ok)
local target=A.jump_tile(john,nil,8,24)
assert(target.ok and target.value.x==16.5 and target.value.z==48.5 and target.value.y>=9.5)
assert(not A.jump_tile(john,nil,-1,Sim.H).ok)
print("PASS the worker sends bounded map samples and a live safe altitude above a remote bridge")

local motion=A.actor_frames({{x=3,z=6,w=17,h=5}},.5)
assert(motion.ok and #motion.value==1 and #motion.value[1].actors>=0)
assert(not motion.value[1].tiles and not motion.value[1].scene and not motion.value[1].corners)
assert(not A.actor_frames({{x=0,z=1,w=17,h=5}},.5).ok)
assert(not A.actor_frames({{x=1,z=1,w=33,h=32}},.5).ok)
print("PASS worker motion observation stays bounded and does not serialize terrain")

do
  -- Reconstruct the depot transaction with a running source, a parked
  -- receiver with existing orders, two flags, and an incompatible truck.
  local depot=Sim.id(8,8)
  local copied_bus=s.fleet[purchase.value]
  local original=s.fleet[id]
  local incompatible=70
  local outside=71
  s.road_economy=true
  local first,last=s.tiles[p].station,s.tiles[q].station
  original.orders={{station=last,action="transfer"},{station=first,action="full"}}
  local before_src=original.orders
  copied_bus.orders={{station=first,action="normal"},{station=last,action="unload"}}
  copied_bus.index=2
  s.fleet[incompatible]={id=incompatible,owner=john,name="Truck",engine="coal_tipper",cargo="coal",
    home_depot=depot,index=1,orders={{station=s.tiles[truck_at].station,action="full"}}}
  s.fleet[outside]={id=outside,owner="Another",name="Rival bus",engine="bus",cargo="passenger",
    home_depot=depot,index=1,orders={{station=first,action="normal"}}}
  assert(not A.depot_order_sources("Another","road",copied_bus.id,depot).ok)
  assert(not A.depot_order_sources(john,"road",original.id,depot).ok,"a running receiver cannot copy")
  local choices=A.depot_order_sources(john,"road",copied_bus.id,depot)
  assert(choices.ok and #choices.value.sources==1 and choices.value.sources[1].id==id and original.running)
  local ticket=choices.value.sources[1]
  local command={kind="depot_copy_orders",mode="road",vehicle=copied_bus.id,source=ticket.id,depot=depot,
    revision=choices.revision,source_revision=ticket.revision,target_revision=choices.value.revision}
  original.orders[2].action="unload"
  assert(not A.command(john,command).ok and copied_bus.orders[1].station==first,"stale source must not change receiver")
  original.orders[2].action="full"
  copied_bus.orders[1].action="full"
  assert(not A.command(john,command).ok and copied_bus.orders[1].station==first,"stale receiver must not be overwritten")
  copied_bus.orders[1].action="normal"
  command.source=outside
  assert(not A.command(john,command).ok and copied_bus.orders[1].station==first)
  command.source=incompatible
  command.source_revision=A.orders(john,"road",incompatible).value.revision
  assert(not A.command(john,command).ok and copied_bus.orders[1].station==first,"incompatible stations must fail atomically")
  command.source,command.source_revision=ticket.id,ticket.revision
  assert(A.command(john,command).ok)
  assert(copied_bus.orders~=before_src and original.orders==before_src and copied_bus.index==2)
  assert(copied_bus.orders[1].station==last and copied_bus.orders[1].action=="transfer")
  assert(copied_bus.orders[2].station==first and copied_bus.orders[2].action=="full")
  copied_bus.orders[1].action="normal"
  assert(original.orders[1].action=="transfer","copying must not share editable row tables")
  assert(not A.command(john,command).ok,"outdated native confirmation cannot overwrite newer orders")
end
print("PASS worker depot order copy preserves sequence and flags, source identity and receiving cursor; stale, foreign and incompatible copies fail atomically")
do
  local r=Sim.new(1731)
  r.corner_grid=T.new(Sim.W,Sim.H,function()return 1 end)
  for _,t in ipairs(r.tiles) do
    t.terrain,t.h="grass",1
    t.build,t.station,t.road_bits,t.wood,t.house,t.site,t.stock_industry=nil,nil,nil,nil,nil,nil,nil
  end
  local rules=dofile(mod.."/campaign_authority_runtime.lua")(Sim,mod,r,{road={start_year=1950,breakdowns=0,service_interval=0}})
  local R=dofile(mod.."/campaign_authority_endpoint.lua")(Sim,rules)
  local selected={tool="drag",first=Sim.id(3,9),last=Sim.id(10,9),axis=0,start_half=false,end_half=true}
  assert(R.road_place("Unknown",selected).why=="COMPANY_NOT_OPEN")
  assert(R.command(john,{kind="company_open"}).ok)
  local quote=assert(R.road_quote(john,selected).value)
  local cash=r.companies[john].cash
  quote.cost=quote.cost-1
  assert(R.road_place(john,selected,quote).why=="ROAD_QUOTE_CHANGED" and cash==r.companies[john].cash)
  quote.cost=quote.cost+1
  r.topology=r.topology+1 -- unrelated owner-side work; the shown price and footprint stay valid
  local accepted=R.road_place(john,selected,quote)
  assert(accepted.ok and #accepted.value==#quote.tiles and r.companies[john].cash==cash-quote.cost)
  local again=R.road_place(john,selected,quote)
  assert(not again.ok and r.companies[john].cash==cash-quote.cost)
  local fresh={tool="drag",first=Sim.id(4,16),last=Sim.id(8,16),axis=0,start_half=true,end_half=false}
  assert(R.road_place(john,fresh).ok)
  local removal={tool="remove",first=fresh.first,last=fresh.last,axis=0,start_half=true,end_half=true}
  local rq=assert(R.road_quote(john,removal).value)
  local budget=r.companies[john]
  local full_cash,full_expense=budget.cash,budget.expense
  assert(#rq.tiles==5 and rq.cost==320)
  r.fleet[7]={id=7,engine="bus",owner=john,road_stop_pose={[4]=Sim.id(6,16)}}
  assert(R.road_place(john,removal,rq).why=="ROAD_QUOTE_CHANGED")
  assert(budget.cash==full_cash and budget.expense==full_expense)
  r.fleet[7]=nil
  budget.cash=120
  local receipt=R.road_place(john,removal,rq)
  assert(receipt.ok and #receipt.value==2 and receipt.why:find("cash ran out"))
  assert(budget.cash==0 and budget.expense==full_expense+120)
  assert(Sim.road_bits(r,fresh.first)==0 and Sim.road_bits(r,Sim.id(5,16))==0 and Sim.road_bits(r,Sim.id(6,16))==10)
  local too_short={tool="remove",first=Sim.id(6,16),axis=0,start_half=false,end_half=true}
  assert(not R.road_place(john,too_short).ok and Sim.road_bits(r,Sim.id(6,16))==10)
  print("PASS road removal refuses stale occupancy changes, respects the affordable prefix, charges exact pieces, and reports the applied footprint")
  print("PASS one owner turn applies exact visible roads, rejects stale price without spending, and safely quotes a fresh placement")
end
