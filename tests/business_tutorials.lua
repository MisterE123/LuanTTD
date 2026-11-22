-- Lessons read the authoritative state; forms cannot spend cash or dispatch.
local forms,closed,hotbar={},nil,nil
local now=0
core={get_modpath=function()return "mods/luanttd_core" end,formspec_escape=function(x)return x end,
  get_us_time=function()return now end,
  show_formspec=function(n,key,markup) forms[n]={key=key,body=markup} end,
  close_formspec=function(n,key)closed={n,key} end}
local meta={}
local function player(name)
  return {get_player_name=function()return name end,
    get_meta=function()return {get_string=function(_,k)return (meta[name] or {})[k] or "" end,
      set_string=function(_,k,v) meta[name]=meta[name] or {};meta[name][k]=v end} end,
    set_inventory_formspec=function(_,form) forms[name]={body=form} end}
end
local p,bob=player("Alex"),player("Bob")
local Sim={W=8,H=4,vehicles={bus={mode="road"}}}
function Sim.id(x,z) if x>=1 and x<=8 and z>=1 and z<=4 then return x+8*(z-1) end end
function Sim.xy(id) return (id-1)%8+1,math.floor((id-1)/8)+1 end
local S={tiles={},stations={},fleet={},stock_rail_stations={},stock_ship_stations={},stock_ship_depots={},
  companies={Alex={cash=999}}}
for i=1,32 do S.tiles[i]={} end
local api={s=S,Sim=Sim,road_first=true,rail_owned={list=function()return S.owned or {} end},
  save=function()error("tutorial may not save the economy")end,
  world={go_menu=function(_,key)hotbar=key;return true end}}
function Sim.ferry_paid_status() return S.paid_ferry end
function Sim.rail_paid_status(_,id) return S.paid_rail and S.paid_rail[id] end
local U=dofile("mods/luanttd_core/ui.lua")(api)
local form="luanttd_core:business_tutorials"
local function has(needle) assert(forms.Alex.body:find(needle,1,true),needle) end
local function submit(f) assert(U.fields(p,form,f)) end
local function advance()
  now=now+1500000
  return U.tutorial_hint(p)
end
assert(U.tutorial_hint(p)=="")
U.inventory(p);has("bl_tutorials;Tutorials")
assert(U.fields(p,"",{bl_tutorials=true}) and forms.Alex.key==form)
for _,key in ipairs({"road","rail","boat"}) do has("lesson_"..key) end
submit({lesson_road=true});has("Build a bus corridor")
submit({lesson_tools=true});assert(hotbar=="roads" and closed[2]==form)
submit({lesson_rail=true});assert(advance():find("Road business",1,true)) -- stale form ignored
S.stations={{owner="Alex",mode="road",stop_type="bus"},{owner="Bob",mode="road",stop_type="bus"}}
assert(advance():find("Build a bus corridor",1,true))
S.stations[2].owner="Alex";assert(advance():find("Build a road depot",1,true))
S.tiles[1]={owner="Alex",build="road_depot"};assert(advance():find("Buy a bus",1,true))
S.fleet[1]={owner="Alex",engine="bus",cargo="passenger"}
assert(advance():find("Add stops and start",1,true))
S.fleet[1].running=true;assert(advance():find("Earn a passenger fare",1,true))
S.fleet[1].delivered=24;S.fleet[1].revenue=43
assert(advance():find("First fare earned",1,true))
U.fields(p,"",{bl_tutorials=true});has("$43")
submit({lesson_rail=true});has("Lay a straight passenger line")
submit({lesson_next=true});has("Connect the rail depot")
submit({lesson_next=true});has("[← PBS]");has("not One-way or Block")
submit({lesson_current=true});has("Lay a straight passenger line")
S.stock_rail_stations={{owner="Alex"},{owner="Alex"}}
assert(advance():find("Connect the rail depot",1,true))
S.tiles[9]={owner="Alex",rail_depot_dir=2,rail_tracks=1}
for x=2,7 do S.tiles[8+x]={owner="Alex",rail_tracks=1} end
S.tiles[12].rail_station_id=1;S.tiles[15].rail_station_id=2
local r={upper_signal_type=5,present_signals=8}
S.stock_rail_dispatch={owner="Alex",signals={records={[11]=r}}}
assert(advance():find("Place the return-direction signal",1,true))
U.fields(p,"",{bl_tutorials=true});has("different signal type")
r.upper_signal_type=4;r.present_signals=4
assert(advance():find("Place the return-direction signal",1,true))
U.fields(p,"",{bl_tutorials=true});has("faces the wrong way");has("facing west")
r.present_signals=8
assert(advance():find("Buy a passenger train",1,true))
S.owned={{id=14,stock_ids={0,27}}};assert(advance():find("Order Far first",1,true))
S.paid_rail={[14]={owner="Alex",delivered=0,fare=0}}
assert(advance():find("Earn your first rail fare",1,true))
S.paid_rail[14]={owner="Alex",delivered=9,fare=12}
assert(advance():find("First fare earned",1,true))
submit({lesson_boat=true});has("Build two passenger docks");has("straight shoreline slope")
S.stock_ship_stations={{owner="Alex"},{owner="Alex"}};assert(advance():find("Build a ship depot",1,true))
S.stock_ship_depots={{owner="Alex"}};assert(advance():find("Buy a passenger ferry",1,true))
S.stock_owned_ferry={owner="Alex"};assert(advance():find("Order the ferry",1,true))
S.paid_ferry={owner="Bob",delivered=20,fare=90};assert(advance():find("Order the ferry",1,true))
S.paid_ferry={owner="Alex",delivered=20,fare=0};assert(advance():find("Earn a passenger fare",1,true))
S.paid_ferry.fare=90;assert(advance():find("First fare earned",1,true))
assert(U.tutorial_hint(bob)=="")
U.leave("Alex");assert(advance():find("Boat business",1,true))
U.fields(p,"",{bl_tutorials=true});has("$90")
submit({lesson_stop=true});assert(U.tutorial_hint(p)=="" and meta.Alex.luanttd_tutorial=="")
assert(S.companies.Alex.cash==999)
print("PASS three live checklists, correct and wrong-facing rail heads, per-owner paid milestones, no simulation writes")
