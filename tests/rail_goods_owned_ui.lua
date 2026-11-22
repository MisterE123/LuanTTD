-- SPDX-License-Identifier: GPL-2.0-only
-- Forms and actual callback route typing, separate from native payment QA.
local receive,form,notice
core={
  formspec_escape=function(s)return s end,
  show_formspec=function(_,id,body) assert(id=="luanttd_core:rail_fleet");form=body end,
  close_formspec=function()end,
  register_on_player_receive_fields=function(f)receive=f end,
  register_on_leaveplayer=function()end,
}
local p={get_player_name=function()return "A" end}
local w={
  tiles={
    [1]={rail_depot_dir=0,owner="A"},[3]={rail_station_id=3,owner="A"},
    [4]={rail_station_id=4,owner="A"},[5]={rail_station_id=5,owner="A"},
    [6]={rail_station_id=6,owner="B"},
  },
  stock_rail_stations={
    [3]={goods_role="load",owner="A"},[4]={goods_role="unload",owner="A"},
    [5]={oil_role="load",owner="A"},[6]={goods_role="load",owner="B"},
  },
}
local verdict={
  [3]={sources={20}},[4]={accepts=true,sources={}},[6]={sources={20}},
}
local current
local Sim={xy=function() return 17,20 end,
  rail_goods_stop_status=function(_,id)return verdict[id] end,
  rail_goods_status=function()return current end,
}
local calls,units={quote={},commits=0,saves=0,toggles=0,starts=0},{}
local O={}
function O.quote(s,owner,depot,ids)
  calls.quote[#calls.quote+1]=ids
  return {stock_ids=ids,price=ids[2]==32 and 12421 or 1985}
end
function O.commit(s,owner,q)
  assert(q.stock_ids[1]==0 and q.stock_ids[2]==32)
  calls.commits=calls.commits+1
  units[1]={id=7,unit_number=1,owner="A",depot=1,status="depot",stock_ids={0,32},price=q.price}
  return units[1]
end
function O.list()return units end
function O.get(s,n,id) if id==7 and n=="A" then return units[1] end end
function O.running() return current and {stopped=false} end
function O.start_goods(s,n,id,load,unload)
  assert(load==3 and unload==4 and id==7 and n=="A")
  calls.starts=calls.starts+1;units[1].status="dispatched";return true,"Stock Goods ordered."
end
function O.toggle(s,n,id) assert(id==7 and n=="A");calls.toggles=calls.toggles+1;return true,"Stopped." end
local api={s=w,Sim=Sim,rail_owned=O,rail_goods_tools=true,save=function()calls.saves=calls.saves+1 end}
local U=dofile("mods/luanttd_core/rail_owned_ui.lua")(api,function(_,s)notice=s end)
local function press(key) assert(receive(p,"luanttd_core:rail_fleet",{[key]=true})) end
local function has(str) return form and form:find(str,1,true) end
U.open(p,1)
assert(has("purchase_goods") and has("25-crate Goods Van") and has("$12421") and not has("purchase_oil"))
api.rail_goods_tools=false
press("purchase_goods")
assert(calls.commits==0 and calls.saves==0,"Stale button may not bypass a disabled model or scenario")
api.rail_goods_tools=true
press("purchase_goods")
assert(calls.commits==1 and calls.saves==1 and has("Choose Sawmill and town Goods orders"))
press("unit_7")
assert(U.active(p) and notice:find("Sawmill"))
for _,id in ipairs({4,5,6}) do assert(not select(2,U.preview(p,id)));assert(U.pick(p,id)) end
verdict[3].sources={}
assert(not select(2,U.preview(p,3)));assert(U.pick(p,3))
verdict[3].sources={20}
assert(select(2,U.preview(p,3)));assert(U.pick(p,3));assert(notice:find("town Goods unloading"))
verdict[4].accepts=false
assert(not select(2,U.preview(p,4)));assert(U.pick(p,4));assert(calls.starts==0)
verdict[4].accepts=true
assert(select(2,U.preview(p,4)));assert(U.pick(p,4))
assert(not U.active(p) and calls.starts==1 and calls.saves==2)
current={fleet_id=7,owner="A",onboard=9,delivered=25,loading=true,mine=3,power=4,last_platform=3,fare=131,running_expense=452}
U.open(p,1)
assert(has("Goods train 1") and has("9 crates aboard") and has("25 crates delivered"))
assert(has("Loading at Sawmill") and has("$131 earned") and has("$452 operating costs"))
press("unit_7");assert(calls.toggles==1 and calls.saves==3)
current.paused=true
press("unit_7");assert(calls.toggles==1)
current.paused=false;current.owner="B"
press("unit_7");assert(calls.toggles==1)
print("PASS: Goods depot buy/order form, correct staged tiles/catchments and crate/expense status, no stale or nonowned action")
