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
local sea_invalidations=0
runtime.invalidate_sea=function() sea_invalidations=sea_invalidations+1 end
local A=dofile(mod.."/campaign_authority_endpoint.lua")(Sim,runtime)
local john="Authorised"
local p,q,d=Sim.id(4,7),Sim.id(14,7),Sim.id(8,8)
local build={kind="road_build",first=p,last=q,revision=0}
local built=A.command(john,build)
assert(built.ok and built.revision==1 and sea_invalidations==1)
local cash=s.companies[john].cash
assert(not A.command(john,build).ok and cash==s.companies[john].cash and sea_invalidations==1)
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
assert(s.fleet[id].running and sea_invalidations==1)
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
assert(sectors.value[1].vehicles==nil and sectors.value[2].vehicles==nil,
  "Ordinary view batches use projected actors, not duplicate fleet summaries")
assert(not A.snapshots({{x=1,z=1,w=1,h=1},{x=2,z=2,w=100,h=100}}).ok)
print("PASS multiple sectors captured at the same authoritative tick")
local bend={tool="bend",first=Sim.id(20,10),last=Sim.id(23,13)}
local Packed=dofile(mod.."/packed_campaign.lua")
local before_bend=Packed.encode(s)
local offer=A.road_quote(john,bend)
assert(Packed.encode(s)==before_bend,"bend hover mutated the saved graph")
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
local expected_sea=sea_invalidations
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
assert(sea_invalidations==expected_sea)
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
assert(sea_invalidations==expected_sea+1)
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
do
  local original=runtime.terrain_projection.corners
  local encoded=0
  runtime.terrain_projection.corners=function(...)
    encoded=encoded+1
    return original(...)
  end
  local window={x=34,z=25,w=4,h=4}
  local first=assert(A.snapshots({window}).value)[1]
  window.scene=first.scene
  local warm=assert(A.snapshots({window}).value)[1]
  assert(encoded==1 and not warm.corners)
  local old_revision=s.corner_grid.revision
  -- Even the shared eastern edge affects this sector, not just its tiles.
  local plan=assert(T.plan(s.corner_grid,window.x+window.w-1,window.z,1,true))
  assert(T.apply(s.corner_grid,plan) and s.corner_grid.revision>old_revision)
  local fresh=assert(A.snapshots({window}).value)[1]
  assert(encoded==2 and fresh.scene~=first.scene and fresh.corners~=first.corners)
  assert(fresh.corners==original(T,s.corner_grid,window.x,window.z,window.w,window.h))
  window.scene=fresh.scene
  assert(not assert(A.snapshots({window}).value)[1].corners and encoded==2)
  runtime.terrain_projection.corners=original
  print("PASS warm sector reuses corner bytes; actual shared-corner edit invalidates the packet")
end
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
local pose=runtime.road_coordinates
local counted={}
runtime.road_coordinates=function(v,f)
  counted[v]=(counted[v] or 0)+1
  return pose(v,f)
end
assert(A.snapshots({{x=3,z=6,w=24,h=12},{x=35,z=22,w=4,h=3}},.4).ok)
for _,v in pairs(s.fleet) do assert(counted[v]==1) end
print("PASS one authoritative horizontal road sample per vehicle per multi-sector observation")
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
local road_only=A.company_fleet(john,1,"road")
assert(road_only.ok and road_only.value.total==2 and road_only.value.records[1].mode=="road")
for _,mode in ipairs({"rail","ship","air","tram"}) do
  local filtered=A.company_fleet(john,1,mode)
  assert(filtered.ok and filtered.value.total==0,mode)
end
assert(A.company_fleet(john,1,"invalid").why=="UNSUPPORTED_FLEET_FILTER")
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
  local saved_crossing=Packed.encode(s2)
  local shadow={tool="drag",first=crossing_at,axis=1,start_half=false,end_half=true}
  station_worker.road_quote(john,shadow)
  assert(Packed.encode(s2)==saved_crossing,"road drag over a reserved crossing mutated the saved graph")
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
  local before_copy=sea_invalidations
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
  assert(A.command(john,command).ok and sea_invalidations==before_copy)
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
  local placed_resets=0
  rules.invalidate_sea=function() placed_resets=placed_resets+1 end
  local R=dofile(mod.."/campaign_authority_endpoint.lua")(Sim,rules)
  local selected={tool="drag",first=Sim.id(3,9),last=Sim.id(10,9),axis=0,start_half=false,end_half=true}
  assert(R.road_place("Unknown",selected).why=="COMPANY_NOT_OPEN")
  assert(R.command(john,{kind="company_open"}).ok)
  local before_hover=Packed.encode(r)
  local quote=assert(R.road_quote(john,selected).value)
  assert(Packed.encode(r)==before_hover,"road drag hover mutated the saved graph")
  local cash=r.companies[john].cash
  quote.cost=quote.cost-1
  assert(R.road_place(john,selected,quote).why=="ROAD_QUOTE_CHANGED" and cash==r.companies[john].cash)
  quote.cost=quote.cost+1
  r.topology=r.topology+1 -- unrelated owner-side work; the shown price and footprint stay valid
  local before_place=placed_resets
  local accepted=R.road_place(john,selected,quote)
  assert(placed_resets==before_place+1)
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
  local west,east=Sim.id(3,20),Sim.id(5,20)
  local left=#r.sites+1
  r.sites[left]={kind="town",tile=Sim.id(4,18),id=left,name="Near Town"}
  r.sites[left+1]={kind="town",tile=Sim.id(4,22),id=left+1,name="Other Town"}
  for at=west,east do
    local t=r.tiles[at]
    t.build,t.road_bits,t.road_town="road",10,left+1 -- recorded builder isn't the nearest authority
  end
  r.stock_road_town_policy={tolerance=0,extra_dynamite=false}
  budget.cash=240
  local municipal={tool="remove",first=east,last=west,axis=0,start_half=true,end_half=false}
  local pub=assert(R.road_quote(john,municipal).value)
  assert(pub.cost==240 and #pub.tiles==3 and budget.stock_town_authority_ratings==nil)
  budget.stock_town_authority_ratings={[left]=36}
  assert(R.road_place(john,municipal,pub).why=="ROAD_QUOTE_CHANGED")
  assert(budget.cash==240 and budget.stock_town_authority_ratings[left]==36)
  budget.stock_town_authority_ratings=nil
  assert(R.road_place(john,municipal,pub).ok)
  assert(budget.cash==0 and budget.stock_town_authority_ratings[left]==446)
  assert(budget.stock_town_authority_ratings[left+1]==nil)
  assert(r.tiles[west+1].road_town==nil and r.tiles[west+1].build==nil)
  do
    local p=Sim.id(12,25)
    local entrance=Sim.id(13,25)
    budget.cash=5000
    r.tiles[entrance].build,r.tiles[entrance].road_bits,r.tiles[entrance].owner="road",2,john
    local spec={tool="stock_terminal",kind="depot",direction=2,first=p}
    local offer=assert(R.road_quote(john,spec).value)
    assert(offer.cost==615 and #offer.tiles==2,offer.cost)
    assert(R.road_place(john,spec,offer).ok)
    assert(r.tiles[p].depot_dir==2 and Sim.road_bits(r,entrance)==10)
    assert(budget.cash==4385)
    spec.direction=0
    local spin=assert(R.road_quote(john,spec).value)
    assert(spin.cost==500 and #spin.tiles==1)
    assert(R.road_place(john,spec,spin).ok and r.tiles[p].depot_dir==4)
    local stop={tool="stock_terminal",kind="truck",direction=0,through=true,first=entrance}
    local cargo=assert(R.road_quote(john,stop).value)
    assert(cargo.cost==200)
    assert(R.road_place(john,stop,cargo).ok)
    local t=r.tiles[entrance]
    assert(t.stop_axis==10 and r.stations[t.station].stop_type=="truck" and t.road_terminal_level==1)
    local crest=Sim.id(20,24)
    local idx=(24-1)*(Sim.W+1)+21
    r.corner_grid.levels[idx]=2 -- the stock W corner is raised
    local bay={tool="stock_terminal",kind="bus",direction=3,first=crest}
    local hillside=assert(R.road_quote(john,bay).value)
    assert(hillside.cost==660)
    assert(R.road_place(john,bay,hillside).ok)
    local shape,z,foundation=Sim.road_surface(r,crest)
    assert(shape==0 and z==2 and foundation=="leveled")
    assert(r.tiles[crest].road_terminal_level==2 and Sim.road_bits(r,crest)==1)
    local projected=assert(R.snapshot(20,24,1,1,0).value)
    assert(projected.tiles[1].surface.road_terminal_level==2)
    print("PASS stock explicit depot mouth, reciprocal half pricing, rotation, exact through truck, and projected sloped bus foundation")
  end
  print("PASS worker resolves the nearest town by stock tie-break and commits ordered town clearing, matching the visible ledger ticket")
  print("PASS road removal refuses stale occupancy changes, respects the affordable prefix, charges exact pieces, and reports the applied footprint")
  print("PASS one owner turn applies exact visible roads, rejects stale price without spending, and safely quotes a fresh placement")
end

do
  local town=assert(s.sites[1])
  assert(town.kind=="town")
  local c=s.companies[john]
  local earlier=s.authority_revision
  local previous,policy=c.stock_town_authority_ratings,s.stock_road_town_policy
  c.stock_town_authority_ratings=nil
  local initial=A.town_authority(john,town.id)
  assert(initial.ok and initial.value.rating==500 and initial.value.grade=="Very good" and initial.value.road_minimum==16)
  assert(not c.stock_town_authority_ratings and s.authority_revision==earlier)
  c.stock_town_authority_ratings={[town.id]=-200}
  s.stock_road_town_policy={tolerance=2,extra_dynamite=false}
  local strict=A.town_authority(john,town.id)
  assert(strict.value.grade=="Very poor" and strict.value.road_minimum==112 and not strict.value.extra_dynamite)
  assert(A.town_authority("Unknown",town.id).why=="COMPANY_NOT_OPEN")
  assert(A.town_authority(john,2147483647).why=="UNKNOWN_TOWN")
  assert(A.town_authority(john,0).why=="INVALID_REQUEST")
  c.stock_town_authority_ratings,s.stock_road_town_policy=previous,policy
  print("PASS authoritative town panel reads only the current company's rating and exact stock labels without opening an account or modifying the game")
end

do
  local fixture=Sim.new(1751)
  fixture.corner_grid=T.new(Sim.W,Sim.H,function(x) return x>=27 and x<=37 and 4 or 3 end)
  for _,tile in ipairs(fixture.tiles) do
    tile.terrain,tile.h="grass",3
    tile.wood,tile.house,tile.site,tile.build,tile.owner=nil,nil,nil,nil,nil
  end
  local R=dofile(mod.."/campaign_authority_runtime.lua")(Sim,mod,fixture,{
    road={start_year=1950,breakdowns=0,service_interval=150},
  })
  local E=dofile(mod.."/campaign_authority_endpoint.lua")(Sim,R)
  local first,last,roof=Sim.id(26,20),Sim.id(37,20),Sim.id(32,20)
  local surface,tunnel="Surface company","Tunnel company"
  local cash=Sim.company(fixture,surface)
  local t=fixture.tiles[roof]
  t.build,t.road_bits,t.owner,t.h="road",15,surface,4
  assert(Sim.road_tunnel(fixture,tunnel,first))
  local key=assert(fixture.tunnel_below[roof])
  local original=fixture.stock_road_tunnels[key]
  assert(original.start==first and original["end"]==last)
  local function option(menu,layer)
    for _,o in ipairs(assert(menu.value).options) do if o.key==layer then return o end end
  end
  local function clear(menu,company,layer)
    return E.command(company,{kind="demolition",revision=menu.revision,token=menu.value.token,layer=layer})
  end
  local preview=E.demolition(surface,roof)
  assert(option(preview,"surface_road").ok and not option(preview,"road_tunnel").ok)
  assert(t.road_bits==15)
  local other=E.demolition(tunnel,roof)
  assert(not option(other,"surface_road").ok and option(other,"road_tunnel").ok)
  assert(not clear(preview,tunnel,"surface_road").ok)
  -- A vehicle entering between quote and confirm invalidates the row.
  fixture.fleet[50]={id=50,owner=surface,engine="bus",route={roof}}
  assert(not clear(preview,surface,"surface_road").ok and t.road_bits==15)
  fixture.fleet[50]=nil
  local before,terrain_revision=cash.cash,fixture.corner_grid.revision
  preview=E.demolition(surface,roof)
  local committed=clear(preview,surface,"surface_road")
  assert(committed.ok and #committed.value==1 and committed.value[1]==roof,committed.why)
  assert(cash.cash==before-160 and not t.build and not t.road_bits)
  assert(fixture.corner_grid.revision==terrain_revision and t.h==4)
  assert(fixture.stock_road_tunnels[key]==original and fixture.tunnel_below[roof]==key and
    fixture.tiles[first].road_tunnel_id==key and fixture.tiles[last].road_tunnel_id==key)
  assert(not option(E.demolition(surface,roof),"surface_road"))
  print("PASS authoritative Bulldozer independently clears all surface road bits over a rival-owned bore")
end

do
  local start=runtime.transport.start
  local called=0
  runtime.transport.start=function(owner,q)
    assert(owner==john and q.first==1 and q.second==2)
    called=called+1
    return true,"Test dispatcher called."
  end
  local first,last=Sim.id(20,21),Sim.id(25,21)
  local a,b=s.tiles[first],s.tiles[last]
  local prev1,prev2,prev3=a.rail_station_id,b.rail_station_id,s.stock_rail_stations
  a.rail_station_id,b.rail_station_id=1,2
  s.stock_rail_stations={[1]={owner=john},[2]={owner="Another"}}
  local c={kind="transport_start",mode="rail",vehicle=10,depot=first,first=1,second=2,
    first_tile=first,second_tile=last,revision=A.company(john).revision}
  assert(A.command(john,c).why=="DESTINATION_TILE_CHANGED" and called==0)
  s.stock_rail_stations[2].owner=john
  b.rail_station_id=3
  assert(A.command(john,c).why=="DESTINATION_TILE_CHANGED" and called==0)
  b.rail_station_id=2
  assert(A.command(john,c).ok and called==1)
  runtime.transport.start=start
  a.rail_station_id,b.rail_station_id,s.stock_rail_stations=prev1,prev2,prev3
  print("PASS initial map routes reject forged or replaced station tiles before hitting the dispatcher")
end


do
  -- No paid landscape or transport tracker touched: use the same handler
  -- for the actual UI commands and observe only the invalidation hook.
  local rev=A.company(john).revision
  local rolling=sea_invalidations
  local function command(c)
    c.revision=rev
    local r=A.command(john,c)
    assert(r.ok,r.why)
    rev=r.revision
  end
  command({kind="speed",speed=0})
  command({kind="speed",speed=2})
  command({kind="road_order_add",vehicle=purchase.value,station=s.tiles[p].station})
  assert(sea_invalidations==rolling)
  print("PASS the ocean cache is not invalidated by playback or road orders; paid terrain and road edits still invalidate")
end

do
  local company=A.company(john)
  local read={kind="speed",speed=company.value.speed,revision=company.revision}
  assert(A.readonly_speed(read))
  local already=A.command(john,read)
  assert(already.ok and already.revision==company.revision and already.tick==company.tick)
  assert(not A.command("NotChair",read).ok)
  read.revision=company.revision-1
  assert(A.command(john,read).why=="STALE_COMMAND")
  read.revision=company.revision
  read.speed=company.value.speed==2 and 1 or 2
  assert(not A.readonly_speed(read))
  assert(A.command(john,read).revision==company.revision+1)
  print("PASS re-selecting current speed is authorized and idempotent, while real changes retain revision fencing")
end
