local m="mods/luanttd_core"
local Sim=dofile(m.."/sim.lua")
local Terrain=dofile(m.."/openttd/terrain.lua")
local F=dofile(m.."/openttd/yapf_road_follow.lua")
local Pack=dofile(m.."/packed_campaign.lua")
local Runtime=dofile(m.."/campaign_authority_runtime.lua")
local Endpoint=dofile(m.."/campaign_authority_endpoint.lua")
local Resolve=dofile(m.."/campaign_order_target.lua")
local s=Sim.new(1751)
local at=Sim.id
local owner="Electric QA"
local cap={road={start_year=1950,breakdowns=0,service_interval=150},seconds_per_day=1.25}
local function bind() local r=Runtime(Sim,m,s,cap); return r,Endpoint(Sim,r) end
dofile(m.."/town_layout.lua")(Sim,s)
s.corner_grid=Terrain.new(Sim.W,Sim.H)
local west,east,depot,road_depot=at(11,12),at(17,12),at(12,11),at(13,13)
for _,i in ipairs(Sim.line(at(8,12),at(20,12))) do
  local t=s.tiles[i]
  t.h,t.terrain,t.build,t.owner,t.house,t.wood,t.site=0,"grass",nil,nil,nil,nil,nil
end
for _,i in ipairs{depot,road_depot} do
  local t=s.tiles[i]
  t.h,t.terrain,t.build,t.owner,t.house,t.wood,t.site=0,"grass",nil,nil,nil,nil,nil
end
s.tram_enabled,s.road_stock_clock,s.road_stock_loading,s.road_economy,s.road_stock_house_supply=
  true,true,true,true,true
local R,A=bind()
local c=Sim.company(s,owner)
local mixed=os.getenv("LUANTTD_TEST_TRAM_MIXED")=="1"
-- First build a dedicated stop and only half a public corridor. In the
-- mixed fixture, the other stop is an existing bus terminal on pavement.
if mixed then
  assert(Sim.build(s,owner,"road",Sim.line(at(13,12),at(20,12))))
  local req={tool="stock_stop_area",kind="bus",direction=0,axis=0,through=true,first=east,last=east}
  local put=A.road_place(owner,req)
  assert(put.ok,put.why)
  local q=A.road_place(owner,{tool="tram_lay",first=east,axis=0,start_half=false,end_half=false})
  assert(q.ok,q.why)
end
assert(R.tram.net.construct(s,owner,"road",Sim.line(at(10,12),at(18,12))))
if not mixed then assert(R.tram.net.construct(s,owner,"drive_stop",{east},0)) end
local stations_before=s.next_station
local request={tool="tram_facility",kind="drive_stop",first=west,direction=0}
local q=A.road_quote(owner,request)
assert(q.ok and s.next_station==stations_before and not s.tiles[west].tram.tram_station)
local placed=A.road_place(owner,request,q.value)
assert(placed.ok,placed.why)
local st=assert(Sim.tram_stop_station(s,west,owner))
local st2=assert(Sim.tram_stop_station(s,east,owner))
assert(st.id==stations_before and st.tram_only and not s.tiles[west].station and st.id~=st2.id)
assert(not not st2.tram_only~=mixed)
assert(not Sim.tram_stop_station(s,west,"Rival"))
assert(Sim.road_stop_catchment(s,st,3)[at(10,13)])
assert(R.tram.net.construct(s,owner,"depot",{depot},F.SE))
if not mixed then assert(Sim.build(s,owner,"road",Sim.line(at(13,12),at(15,12)))) end
assert(Sim.build(s,owner,"road_depot",{road_depot}))
local bus=assert(Sim.purchase(s,owner,"bus","passenger",nil,road_depot))
assert(not Sim.add_order(s,owner,bus,st.id) and not Sim.path(s,st,st2,"road",owner))
local function record(which,id) return s[which] and s[which][id] end
assert(not Resolve("road",bus,owner,west,s.tiles[west],record))
local id,title=Resolve("tram",1,owner,west,s.tiles[west],record)
assert(id==west and title==st.name)
local req={kind="transport_start",mode="tram",depot=depot,first=west,second=east,
  paid=true,cost=R.tram.run.offer().price}
local function command(sender,r)
  r.revision=s.authority_revision or 0
  return A.command(sender,r)
end
local cash=c.cash
assert(not command("Rival",req).ok and c.cash==cash)
local started=command(owner,req)
assert(started.ok and c.cash==cash-req.cost,started.why)
local p=assert(R.tram.run.current(s))
local function demolish()
  local modal=assert(A.demolition(owner,west).value)
  for _,row in ipairs(modal.options) do if row.key=="tram_facility" then return modal,row end end
end
local _,active=demolish()
assert(active and not active.ok,"an in-service station must not be removable")
local x,z=Sim.xy(west)
local visible=assert(A.snapshots({{x=x-2,z=z-2,w=12,h=8}},1).value[1])
assert(visible.registries.stations[st.id].tram_only and visible.passengers["road:"..st.id]~=nil)
local info=assert(A.orders(owner,"tram",1).value)
assert(info.items[1].id==west and info.items[1].label==st.name)
local sid,second=st.id,st2.id
for _=1,120 do
  if p.carrier.delivered>0 then break end
  assert(A.advance(1).ok)
end
assert(p.carrier.delivered>0 and p.carrier.revenue>0)
assert(c.paid_units==p.carrier.delivered)
assert(p.carrier.last_fare.tile==west or p.carrier.last_fare.tile==east)
local prev=p.carrier.delivered
s=assert(Pack.decode(Pack.encode(s)))
R,A=bind()
assert(Sim.tram_stop_station(s,west,owner).id==sid and Sim.tram_stop_station(s,east,owner).id==second)
p=assert(R.tram.run.current(s))
for _=1,100 do
  if p.carrier.delivered>prev then break end
  assert(A.advance(1).ok)
end
assert(p.carrier.delivered>prev)
assert(command(owner,{kind="transport_start",mode="tram",clear=true,vehicle=1,retirement=R.tram.run.retirement_key(p)}).ok)
local modal,can=demolish()
assert(can and can.ok)
assert(command(owner,{kind="demolition",layer=can.key,token=modal.token}).ok)
assert(not s.stations[sid] and s.tiles[west].tram.kind=="road" and s.stations[second])
assert(Sim.road_station_retirement().get(s,"station",sid).tram_only)
local rebuilt=A.road_place(owner,request)
assert(rebuilt.ok and Sim.tram_stop_station(s,west,owner).id==sid,rebuilt.why)
print("PASS paid "..(mixed and "mixed tram and bus-platform" or "tram-only")..
  " itineraries: canonical catching/loading, bus exclusion, fares, projection, save/reload and safe removal/rebuild")

if os.getenv("LUANTTD_TEST_TRAM_ROAD_ACCESS")=="1" then
  local street_owner="Paving QA"
  local street=Sim.company(s,street_owner)
  local owned=assert(s.stations[sid])
  local wrong={tool="drag",first=west,last=west,axis=1,start_half=false,end_half=false}
  assert(not A.road_quote(street_owner,wrong).ok)
  local pave={tool="drag",first=west,last=west,axis=0,start_half=false,end_half=false}
  local before=street.cash
  local next_id=s.next_station
  local quote=A.road_quote(street_owner,pave)
  assert(quote.ok and quote.value.cost==190,quote.why)
  assert(s.stations[sid].tram_only and not s.tiles[west].station)
  local paved=A.road_place(street_owner,pave,quote.value)
  assert(paved.ok,paved.why)
  local t=s.tiles[west]
  assert(street.cash==before-190 and s.next_station==next_id and t.owner==street_owner and t.tram.tram_owner==owner)
  assert(t.tram.kind=="drive_stop" and t.tram.tram_shelter and t.tram.shared_station==sid and t.station==sid)
  assert(owned==s.stations[sid] and not owned.tram_only and owned.owner==owner and Sim.tram_stop_station(s,west,owner)==owned)
  assert(Sim.add_order(s,owner,bus,sid),"station owner can now order its bus to the same pavement")
  assert(not A.road_quote(street_owner,pave).ok,"stock already built is not an extra charge")
  local remove={tool="remove",first=west,last=west,axis=0,start_half=false,end_half=true}
  assert(not A.road_quote(street_owner,remove).ok,"cannot strand an existing road order")
  if mixed then
    for _,x in ipairs({10,12,13}) do
      local plan={tool="drag",first=at(x,12),axis=0,start_half=false,end_half=true}
      local put=A.road_place(owner,plan)
      assert(put.ok,put.why)
    end
    assert(Sim.add_order(s,owner,bus,second))
    assert(Sim.toggle(s,owner,bus))
    assert(command(owner,req).ok)
    local active=assert(R.tram.run.current(s)).carrier
    for _=1,100 do
      if active.delivered>0 and s.fleet[bus].delivered>0 then break end
      assert(A.advance(1).ok)
    end
    assert(active.delivered>0 and s.fleet[bus].delivered>0,"both modes must earn live fares on the same platform ID")
  else
    assert(Sim.edit_order(s,owner,bus,1,"remove"))
    assert(not A.road_quote(owner,remove).ok,"station ownership does not grant the separately owned pavement")
    local cash_remove=street.cash
    local menu=assert(A.demolition(street_owner,west).value)
    local layer
    for _,row in ipairs(menu.options) do if row.key=="tram_platform_pavement" then layer=row end end
    assert(layer and layer.ok)
    assert(command(street_owner,{kind="demolition",layer=layer.key,token=menu.token}).ok)
    assert(street.cash==cash_remove-80 and not t.station and Sim.road_bits(s,west)==0)
    assert(owned==s.stations[sid] and owned.tram_only and t.tram.tram_station==sid and t.tram.tram_owner==owner)
    assert(A.road_place(street_owner,pave).ok)
    local m2=assert(A.demolition(owner,west).value)
    local platform
    for _,row in ipairs(m2.options) do if row.key=="tram_combined_facility" then platform=row end end
    assert(platform and platform.ok)
    assert(command(owner,{kind="demolition",layer=platform.key,token=m2.token}).ok)
    assert(not s.stations[sid] and t.build=="road" and t.owner==street_owner and Sim.road_bits(s,west)==10)
    assert(t.tram.kind=="road" and t.tram.tram_owner==owner)
  end
  print("PASS RC1 station axis road addition buys two bits, keeps station identity, and connects or removes bus access without deleting the tram stop")
end
