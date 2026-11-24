local m="mods/luanttd_core"
local Sim=dofile(m.."/sim.lua")
local T=dofile(m.."/openttd/terrain.lua")
local F=dofile(m.."/openttd/yapf_road_follow.lua")
local Pack=dofile(m.."/packed_campaign.lua")
local Runtime=dofile(m.."/campaign_authority_runtime.lua")
local Endpoint=dofile(m.."/campaign_authority_endpoint.lua")
local cap={road={start_year=1950,breakdowns=0,service_interval=150},seconds_per_day=1.25}
local owner="Shared lane QA"
local s=Sim.new(1751)
local function at(x,z) return Sim.id(x,z) end
dofile(m.."/town_layout.lua")(Sim,s)
s.corner_grid=T.new(Sim.W,Sim.H)
local function clear(x,z)
  local tile=s.tiles[at(x,z)]
  tile.h,tile.terrain,tile.build,tile.owner,tile.house,tile.wood,tile.site=0,"grass",nil,nil,nil,nil,nil
end
for x=8,20 do clear(x,12) end
clear(12,11)
clear(13,13)
s.tram_enabled,s.road_stock_clock,s.road_stock_loading,s.road_economy,s.road_stock_house_supply=
  true,true,true,true,true
local runtime=Runtime(Sim,m,s,cap)
local A=Endpoint(Sim,runtime)
assert(Sim.shared_road_tram_active(s))
local tram=at(12,11)
local west,east,depot=at(11,12),at(17,12),at(13,13)
assert(Sim.build(s,owner,"road",Sim.line(at(8,12),at(20,12))))
for _,tile in ipairs({west,east}) do
  local put=A.road_place(owner,{tool="stock_stop_area",kind="bus",direction=0,axis=0,through=true,first=tile,last=tile})
  assert(put.ok,put.why)
end
local company=Sim.company(s,owner)
assert(Sim.build(s,owner,"road_depot",{depot}))
local old_west,old_east=s.tiles[west].station,s.tiles[east].station
assert(old_west~=old_east)
local left,right=s.stations[old_west],s.stations[old_east]
local N=runtime.tram.net
assert(N.construct(s,owner,"depot",{tram},F.SE))
for _,tile in ipairs({west,east}) do
  local wrong={tool="tram_lay",first=tile,axis=1,start_half=false,end_half=true}
  assert(not A.road_place(owner,wrong).ok,"perpendicular overlay would obliterate the existing station")
  local request={tool="tram_lay",first=tile,axis=0,start_half=false,end_half=false}
  local cash=company.cash
  local q=assert(A.road_quote(owner,request).value)
  assert(q.cost==380 and A.road_place(owner,request,q).ok and company.cash==cash-380)
end
assert(s.tiles[west].tram.shared_station==old_west and s.tiles[east].tram.shared_station==old_east)
assert(s.tiles[west].station==old_west and s.stations[old_west]==left and s.stations[old_east]==right)
assert(not Sim.stock_road_stop_remove_plan(s,owner,west,west),"do not strand a shared tram stop through the road-only tool")
assert(N.construct(s,owner,"road",Sim.line(at(10,12),at(18,12))))
assert(N.construct(s,owner,"road",{at(12,12)},1))
local cost=runtime.tram.run.offer().price
local cash=company.cash
local req={kind="transport_start",mode="tram",paid=true,depot=tram,first=west,second=east,
  cost=cost-1,revision=s.authority_revision or 0}
assert(not A.command(owner,req).ok and company.cash==cash and not s.tram_pilot)
req.cost=cost
local bought=A.command(owner,req)
assert(bought.ok and company.cash==cash-cost,bought.why)
assert(not A.command(owner,req).ok and company.cash==cash-cost)
local p=assert(runtime.tram.run.current(s))
assert(p.carrier and p.carrier.delivered==0 and not s.fleet[p.carrier.id])
local fleet_case=os.getenv("LUANTTD_TEST_TRAM_FLEET")=="1"
local alternate
if fleet_case then
  req.revision=s.authority_revision
  assert(A.command(owner,req).ok)
  local all=runtime.tram.run.all(s)
  assert(#all==2)
  alternate=all[2]
  assert(alternate.carrier.id~=p.carrier.id and alternate.carrier.id==p.carrier.id+1)
  assert(company.cash==cash-2*cost and not s.fleet[alternate.carrier.id])
end
local bus=assert(Sim.purchase(s,owner,"bus","passenger",nil,depot))
for _,stop in ipairs({west,east}) do
  assert(Sim.add_order(s,owner,bus,s.tiles[stop].station))
end
assert(Sim.toggle(s,owner,bus))
assert(A.advance(1).ok and p.ticks==74,"separate tram clock must not double tick")
if alternate then
  assert(alternate.ticks==74 and p.steps>alternate.steps,"second tram must queue behind first leaving shared depot")
end
local function completed()
  return p.arrivals>=4 and s.fleet[bus].delivered>0 and p.carrier.delivered>0 and
    (not alternate or alternate.carrier.delivered>0)
end
for _=1,90 do
  if completed() then break end
  local before=p.ticks
  assert(A.advance(1).ok and p.ticks-before==74)
end
assert(completed(),("arrivals %s, bus %s, waits %s %s"):format(p.arrivals,s.fleet[bus].delivered,tostring(p.traffic_wait),tostring(p.crossing_wait)))
local v=s.fleet[bus]
local saved_ticks,arrivals,paid,tram_paid=p.ticks,p.arrivals,v.delivered,p.carrier.delivered
local alternate_id=alternate and alternate.carrier.id
local alternate_paid=alternate and alternate.carrier.delivered
s=assert(Pack.decode(Pack.encode(s)))
runtime=Runtime(Sim,m,s,cap)
A=Endpoint(Sim,runtime)
p=assert(runtime.tram.run.current(s))
alternate=alternate_id and assert(runtime.tram.run.current(s,alternate_id))
assert(p.ticks==saved_ticks and (not alternate or alternate.ticks==saved_ticks))
for _=1,65 do
  if p.arrivals>=arrivals+2 and s.fleet[bus].delivered>paid and p.carrier.delivered>tram_paid then break end
  assert(A.advance(1).ok)
end
assert(p.arrivals>=arrivals+2 and s.fleet[bus].delivered>paid and p.carrier.delivered>tram_paid)
assert(p.carrier.revenue>0 and p.carrier.last_fare.amount>0)
assert(s.companies[owner].paid_units==p.carrier.delivered+s.fleet[bus].delivered+
  (alternate and alternate.carrier.delivered or 0))
assert(p.carrier.stock_aged_tick==s.stock_load_tick)
if alternate then
  local id=runtime.tram.run.ui_id(s,alternate)
  assert(id>1 and A.orders(owner,"tram",id).ok and not A.orders("Rival","tram",id).ok)
  local rows=dofile(m.."/campaign_company_fleet.lua")(Sim,runtime).page(owner,1).records
  local tram_count=0
  for _,row in ipairs(rows) do if row.mode=="tram" then tram_count=tram_count+1 end end
  assert(tram_count==2)
  local a0,b0=Sim.xy(west)
  local visible=assert(A.snapshots({{x=a0-4,z=b0-5,w=18,h=14}},1).value[1])
  local actors={}
  for _,row in ipairs(visible.actors) do if row.mode=="tram" then actors[row.id]=row end end
  assert(actors[1] and actors[id] and actors[1]~=actors[id])
  local rev=p.order_revision
  local orders=A.orders(owner,"tram",id).value
  local edit=A.command(owner,{kind="vehicle_order",mode="tram",vehicle=id,operation="up",
    row=2,order_revision=orders.revision,revision=s.authority_revision or 0})
  assert(edit.ok,edit.why)
  assert(alternate.orders[1]==east and p.orders[1]==west and p.order_revision==rev)
end
local function retire(n,id,key)
  return A.command(n,{kind="transport_start",mode="tram",clear=true,vehicle=id,retirement=key,
    revision=s.authority_revision or 0})
end
if alternate then
  assert(not retire(owner).ok and #runtime.tram.run.all(s)==2)
  assert(not retire(owner,1,runtime.tram.run.retirement_key(alternate)).ok)
  local roster=A.company_fleet(owner,1,"tram").value.records
  assert(#roster==2 and roster[1].id==1 and roster[2].id==alternate_id)
  assert(not retire("Rival",1,roster[1].retirement).ok)
  assert(retire(owner,1,roster[1].retirement).ok)
else
  assert(runtime.tram.run.clear(s,owner))
end
if alternate then
  assert(alternate.carrier.delivered>alternate_paid)
  assert(runtime.tram.run.uses(s,west) and Sim.road_piece_occupancy(s)(west,true))
  assert(not runtime.tram.run.clear(s,"Rival",alternate_id))
  assert(retire(owner,alternate_id,runtime.tram.run.retirement_key(alternate)).ok)
  assert(not runtime.tram.run.uses(s,west))
end
for _,station in pairs(s.stations) do
  for _,id in ipairs(station.loading_order or {}) do assert(id~=p.carrier.id and id~=alternate_id) end
end
local function option()
  local modal=assert(A.demolition(owner,west).value)
  for _,row in ipairs(modal.options) do
    if row.key=="tram_shared_stop" then return modal,row end
  end
end
for _=1,40 do
  local modal,row=option()
  if row and row.ok then
    assert(row.detail=="Refund: $204")
    local old=s.companies[owner].cash
    local check=A.command(owner,{kind="demolition",layer=row.key,token=modal.token,revision=s.authority_revision or 0})
    assert(check.ok and s.companies[owner].cash==old+204,check.why)
    break
  end
  assert(A.advance(1).ok)
end
assert(s.tiles[west].tram==nil and s.tiles[west].station==old_west and
  s.stations[old_west].owner==owner and s.tiles[west].build=="road_station")
print("PASS actual paid bus and passenger tram stop on the same two through platforms, reload, then remove only ELRL while preserving canonical platform IDs")

if fleet_case then print("PASS two paid trams queue out of one depot, share real buses and cargo, and retain distinct serials, fares and orders across save/reload") end
