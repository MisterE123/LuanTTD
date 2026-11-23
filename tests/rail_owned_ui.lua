local panel,handler,left
local handlers={}
core={
  formspec_escape=function(s)return s end,
  show_formspec=function(n,k,m)panel={owner=n,key=k,markup=m} end,
  close_formspec=function()panel=nil end,
  register_on_player_receive_fields=function(cb)
    handlers[#handlers+1]=cb
    handler=function(...) for _,fn in ipairs(handlers) do if fn(...) then return true end end end
  end,
  explode_textlist_event=function(v)return {index=tonumber(v)}end,
  register_on_leaveplayer=function(cb)left=cb end,
}
local s={tiles={
  [1]={rail_depot_dir=2,owner="owner"},[2]={rail_depot_dir=2,owner="other"},
  [3]={rail_station_id=8,owner="owner"},[4]={rail_station_id=8,owner="owner"},
  [5]={rail_station_id=9,owner="owner"},[6]={rail_station_id=10,owner="other"},
}}
local saves,last=0
local units,orders,stop={},nil,false
local coal
local function p(name)return {get_player_name=function() return name end} end
local owner,other=p("owner"),p("other")
local host={s=s,save=function()saves=saves+1 end,
  Sim={xy=function(i)return i,10 end,rail_paid_status=function()return {fare=41} end,
    rail_coal_status=function()return coal end}}
host.rail_owned={
  pair_passenger_engine=function(id) return id==0 or id==8 or id==9 end,
  quote=function(s,n,depot,ids)
    assert(n=="owner" and depot==1)
    if ids[1]==8 then assert(ids[2]==27);return {price=22241} end
    if ids[1]==9 then assert(ids[2]==27);return {price=31616} end
    assert(ids[1]==0)
    if ids[2]==29 then return {price=12312} end
    assert(ids[2]==27);return {price=12866} end,
  commit=function(s,n,q)
    assert(n=="owner" and q.price==12866);local u={id=15,unit_number=1,depot=1,status="depot",price=q.price,stock_ids={0,27}}
    assert(not units[1]);units[1]=u;return u end,
  get=function(s,n,id)return id==15 and units[1] or nil end,
  list=function()return units end,
  start=function(s,n,id,a,b)
    assert(id==15 and a==8 and b==9);orders={a,b};units[1].status="dispatched";return true,"Service ordered." end,
  running=function() if orders then return {passengers=11,stopped=stop,running_expense=15} end end,
  toggle=function(s,n,id)assert(id==15);stop=not stop;return true,"Toggled queued consist." end,
}
local ui=dofile("mods/luanttd_core/rail_owned_ui.lua")(host,function(_,text)last=text end)
assert(not ui.open(other,1) and not ui.open(owner,2))
assert(handler(owner,"luanttd_core:rail_fleet",{purchase=true}) and saves==0)
assert(ui.open(owner,1) and panel.markup:find("$12866",1,true))
assert(handler(other,panel.key,{purchase=true}) and saves==0)
assert(handler(owner,panel.key,{purchase=true}) and saves==1 and panel.markup:find("Purchased train",1,true))
assert(handler(owner,panel.key,{unit_15=true}) and ui.active(owner) and not panel)
assert(ui.pick(owner,6) and not orders and last:find("first"))
assert(ui.pick(owner,3) and not orders and last:find("second"))
assert(ui.pick(owner,4) and not orders)
assert(ui.pick(owner,5,true) and ui.active(owner) and ui.ready(owner) and not orders and saves==1)
assert(ui.confirm(owner) and not ui.active(owner) and saves==2 and last=="Service ordered.")
assert(ui.open(owner,1) and panel.markup:find("$41 in fares",1,true))
assert(handler(owner,panel.key,{unit_15=true}) and stop and saves==3)
assert(panel.markup:find("Resume this shuttle",1,true))
assert(panel.markup:find("Stopped   /   $15 operating costs",1,true))

-- Coal that is still in service can be controlled from its real depot.
host.rail_coal_tools=true
units[1].stock_ids={0,29}
coal={fleet_id=15,onboard=14,delivered=30,fare=235}
assert(ui.open(owner,1) and panel.markup:find("14 t aboard",1,true))
assert(panel.markup:find("Resume coal train",1,true))
assert(handler(owner,panel.key,{unit_15=true}) and not stop and saves==4)
assert(panel.markup:find("Stop coal train",1,true))
assert(panel.markup:find("$235 earned",1,true))
coal.repeating=true
host.rail_dispatch_controller={park_coal=function(_,n,id,on)
  assert(n=="owner" and id==15)
  coal.parking=on
  return true,"Orders retained."
end}
assert(ui.open(owner,1) and panel.markup:find("Park after the next",1,true))
assert(handler(owner,panel.key,{park_coal=true}) and coal.parking and saves==5)
assert(panel.markup:find("Keep repeating",1,true))
assert(handler(owner,panel.key,{park_coal=true}) and not coal.parking and saves==6)
coal.finished=true
assert(ui.open(owner,1) and not panel.markup:find("coal train",1,true))
assert(panel.markup:find("Parked",1,true))
coal.finished=false;coal.paused=true
assert(ui.open(owner,1) and not panel.markup:find("Stop coal train",1,true))
assert(panel.markup:find("Service unavailable",1,true))
coal={fleet_id=16,onboard=19,delivered=444,fare=987}
assert(ui.open(owner,1) and not panel.markup:find("444 t delivered",1,true))
local model_ready,a4_ready=false,false
host.rail_owned.catalog=function() return {
  {stock_id=8,name="Chaney 'Jubilee'",speed=112,passenger_model_ready=model_ready},
  {stock_id=9,name="Ginzu 'A4'",speed=128,passenger_model_ready=a4_ready},
} end
assert(ui.open(owner,1) and not panel.markup:find("purchase_jubilee",1,true))
assert(not panel.markup:find("purchase_a4",1,true))
model_ready=true
assert(ui.open(owner,1) and panel.markup:find("purchase_jubilee",1,true) and panel.markup:find("$22241",1,true))
assert(panel.markup:find("112 km/h",1,true) and not panel.markup:find("purchase_a4",1,true))
a4_ready=true
assert(ui.open(owner,1) and panel.markup:find("purchase_a4",1,true) and panel.markup:find("$31616",1,true))
assert(panel.markup:find("128 km/h",1,true) and panel.markup:find("purchase_coal",1,true))

-- A modeled engine on public sale can be selected for freight. Changing
-- the dropdown must re-quote, never debit or start a train.
local passenger_quote=host.rail_owned.quote
host.rail_owned.freight_engine=function(id) return id==0 or id==8 end
host.rail_owned.catalog=function() return {
  {stock_id=8,name="Chaney 'Jubilee'",speed=112,passenger_model_ready=true,availability={public=true}},
  {stock_id=9,name="Ginzu 'A4'",speed=128,passenger_model_ready=true,availability={public=true}},
} end
host.rail_owned.quote=function(state,name,depot,ids)
  if ids[1]==8 and ids[2]==29 then return {price=21687,stock_ids=ids} end
  return passenger_quote(state,name,depot,ids)
end
assert(ui.open(owner,1) and panel.markup:find("Freight locomotive",1,true))
assert(panel.markup:find("Kirby,Jubilee",1,true))
assert(handler(owner,panel.key,{freight_engine="2"}))
assert(panel.markup:find("Jubilee + 30-ton coal wagon",1,true) and panel.markup:find("$21687",1,true))
assert(saves==6)


host.rail_owned_pair_tools=true
s.tiles[7]={rail_depot_dir=1,owner="owner"}
s.tiles[8]={rail_station_id=11,owner="owner"}
s.stock_rail_stations={[8]={owner="owner"},[9]={owner="owner"},[10]={owner="other"},[11]={owner="owner"}}
units[1].stock_ids={0,27};units[1].status="depot"
units[2]={id=44,unit_number=2,depot=7,status="depot",price=12866,stock_ids={0,27}}
local pending
host.rail_owned.start_pair=function(_,name,a,b)
  assert(name=="owner" and a.id==15 and b.id==44)
  assert(a.first==8 and a.second==9 and b.first==8 and b.second==11)
  pending={a,b}
  return true,"Scheduled two owned trains."
end
assert(ui.begin_pair(owner) and last:find("Train 1",1,true))
assert(not select(2,ui.preview(owner,2)))
assert(ui.pick(owner,1) and ui.pick(owner,3) and ui.pick(owner,5))
assert(ui.active(owner) and last:find("Train 2",1,true) and not pending and saves==6)
assert(not select(2,ui.preview(owner,1)))
assert(ui.pick(owner,7) and ui.pick(owner,3))
assert(not select(2,ui.preview(owner,5))) -- distinct terminal park
assert(not select(2,ui.preview(owner,6))) -- foreign platform
assert(ui.pick(owner,8,true) and ui.active(owner) and ui.ready(owner) and not pending)
assert(ui.confirm(owner) and not ui.active(owner) and saves==7 and pending)
left(owner)

-- Oil purchase, route order, station source validation and liters are
-- independent of coal and the passenger runtime.
host.rail_owned_pair_tools=false
host.rail_oil_tools=true
s.tiles[11]={rail_station_id=12,owner="owner"}
s.tiles[12]={rail_station_id=13,owner="owner"}
s.tiles[13]={rail_station_id=14,owner="owner"}
s.stock_rail_stations[8].oil_role="load"
s.stock_rail_stations[9].oil_role="unload"
s.stock_rail_stations[10].oil_role="unload" -- wrong company
s.stock_rail_stations[12]={owner="owner",oil_role="unload"} -- lost refinery acceptance
s.stock_rail_stations[13]={owner="owner",coal_role="load"}
s.stock_rail_stations[14]={owner="owner",oil_role="load"} -- lost well
local accepts=true
host.Sim.rail_oil_stop_status=function(_,id)
  return ({[8]={role="load",sources={41}},[9]={role="unload",accepts=accepts},
    [10]={role="unload",accepts=true},[12]={role="unload",accepts=false},[14]={role="load",sources={}}})[id]
end
local unavailable=true
local oldquote=host.rail_owned.quote
host.rail_owned.quote=function(w,n,depot,ids)
  if ids[2]~=30 then return oldquote(w,n,depot,ids) end
  assert(ids[1]==0 and n=="owner" and depot==1)
  if unavailable then return nil,"RAIL_VEHICLE_NOT_MOUNTED" end
  return {price=12499,stock_ids={0,30}}
end
units={}
local oil_unit,oil_run,order_error
local oil_stop=false
host.rail_owned.commit=function(_,n,receipt)
  assert(n=="owner" and receipt.price==12499 and receipt.stock_ids[2]==30)
  oil_unit={id=70,unit_number=5,depot=1,status="depot",owner="owner",stock_ids={0,30},price=12499}
  units[1]=oil_unit
  return oil_unit
end
host.rail_owned.get=function(_,n,id)
  return n=="owner" and oil_unit and id==oil_unit.id and oil_unit or nil
end
host.rail_owned.start_oil=function(_,n,id,load,unload)
  assert(n=="owner" and id==70 and load==8 and unload==9)
  if order_error then return false,"Rail path unavailable." end
  oil_unit.status="dispatched"
  oil_run={fleet_id=id,onboard=17,delivered=30,fare=211,running_expense=51,loading=true,last_platform=8,mine=8,power=9}
  return true,"Oil service ordered."
end
host.Sim.rail_oil_status=function()return oil_run end
host.rail_owned.running=function()if oil_run then return {stopped=oil_stop} end end
host.rail_owned.toggle=function(_,n,id)
  assert(n=="owner" and id==70)
  oil_stop=not oil_stop;return true,"Oil train toggled."
end
local previous=saves
assert(ui.open(owner,1) and panel.markup:find("Oil: This train is not available",1,true))
assert(not panel.markup:find("purchase_oil",1,true))
unavailable=false
assert(ui.open(owner,1) and panel.markup:find("purchase_oil",1,true))
assert(panel.markup:find("30,000 L Oil Tanker",1,true) and panel.markup:find("$12499",1,true))
assert(panel.markup:find("tooltip[purchase_oil",1,true) and panel.markup:find("purchase_coal",1,true))
host.rail_oil_tools=false
assert(handler(owner,panel.key,{purchase_oil=true}) and saves==previous and not oil_unit)
host.rail_oil_tools=true
assert(handler(owner,panel.key,{purchase_oil=true}) and oil_unit and saves==previous+1)
assert(panel.markup:find("Choose Oil Wells and Oil Refinery orders",1,true))
assert(handler(owner,panel.key,{unit_70=true}) and ui.active(owner) and not panel)
assert(last:find("Oil Wells",1,true))
assert(not select(2,ui.preview(owner,5)) and not select(2,ui.preview(owner,12)))
assert(not select(2,ui.preview(owner,13)))
assert(ui.pick(owner,13) and last:find("no longer covers",1,true))
assert(select(2,ui.preview(owner,3)) and ui.pick(owner,3) and last:find("Oil Refinery",1,true))
assert(not select(2,ui.preview(owner,4)) and not select(2,ui.preview(owner,6)))
assert(ui.pick(owner,11) and last:find("no longer accepts",1,true))
accepts=false
assert(not select(2,ui.preview(owner,5)) and ui.pick(owner,5) and not oil_run and saves==previous+1)
accepts=true;order_error=true
assert(ui.pick(owner,5) and last=="Rail path unavailable." and not oil_run and ui.active(owner))
order_error=false
assert(ui.pick(owner,5) and not ui.active(owner) and saves==previous+2 and oil_run)
assert(ui.open(owner,1) and panel.markup:find("17,000 L aboard",1,true))
assert(panel.markup:find("30,000 L delivered",1,true) and panel.markup:find("$211 earned",1,true))
assert(panel.markup:find("$51 operating costs",1,true) and panel.markup:find("Loading at Oil Wells",1,true))
assert(handler(owner,panel.key,{unit_70=true}) and oil_stop and saves==previous+3)
assert(panel.markup:find("Resume oil train",1,true))
oil_run.finished=true
assert(ui.open(owner,1) and panel.markup:find("Parked at refinery",1,true))
assert(not panel.markup:find("Resume oil train",1,true))
assert(handler(owner,panel.key,{unit_70=true}) and oil_stop and saves==previous+3)
oil_run.finished=false;oil_run.fleet_id=800;oil_run.delivered=900
assert(ui.open(owner,1) and not panel.markup:find("900,000 L delivered",1,true))
assert(panel.markup:find("Oil service status unavailable",1,true))
host.rail_oil_tools=false
assert(ui.open(owner,1) and panel.markup:find("Service unavailable",1,true))
assert(not panel.markup:find("purchase_oil",1,true) and not panel.markup:find("Resume oil train",1,true))
left(owner)
print("PASS: Oil tanker price, real well/refinery stage selection, guarded stop and resume, and liters independent of Coal.")

print("PASS: depot ownership, quotes, individual train controls, scheduled freight parking, and atomic paired world orders")

-- Ordinary passenger orders use the new stock list adapter; the review
-- must not commit until the final dispatch, and must end the modal.
s.stock_rail_stations={
  [8]={owner="owner",tiles={3}},[9]={owner="owner",tiles={5}},
  [11]={owner="owner",tiles={8}},[14]={owner="owner",tiles={13},coal_role="load"},
}
units={{id=15,unit_number=1,depot=1,status="depot",price=12866,stock_ids={0,27}}}
host.rail_owned.get=function(_,n,id) return n=="owner" and id==15 and units[1] end
host.rail_owned.running=function() end
local mode,committed
host.world={
  begin_order_selection=function(_,m) mode=m end,
  end_order_selection=function() mode=nil end,
}
host.rail_owned.start_order_list=function(_,name,id,seq)
  assert(name=="owner" and id==15 and table.concat(seq,",")=="9,8,11")
  committed=true;return true,"Ordered three platforms."
end
local before=saves
assert(ui.open(owner,1) and handler(owner,panel.key,{unit_15=true}) and mode=="rail_sequence")
assert(not select(2,ui.preview(owner,13)))
for _,id in ipairs({3,5,8,5}) do assert(ui.pick(owner,id,true)) end
assert(ui.review(owner) and panel.key=="luanttd_core:rail_order_review")
assert(handler(owner,panel.key,{stops="4",remove=true}))
assert(handler(owner,panel.key,{stops="2",move_up=true}))
assert(panel.markup:find("1. Platform #9",1,true))
assert(saves==before and not committed)
assert(handler(owner,panel.key,{dispatch=true}) and committed and not mode and not panel and saves==before+1)
print("PASS native formspec adapter stages, reorders, deletes and dispatches three passenger orders")
