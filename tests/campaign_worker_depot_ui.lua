local body,request,done
local core={formspec_escape=function(x)return x end,
  show_formspec=function(_,_,x) body=x end,
  explode_textlist_event=function(x)return {index=tonumber(x)} end,
  explode_scrollbar_event=function(x)return {type="CHG",value=tonumber(x)} end}
local client={query=function(r,cb) request,done=r,cb;return true end}
local purchase
local build={commit=function(name,kind,r,cb) purchase={name,kind,r,cb};return true end}
local mock={get_player_name=function()return "Mine" end}
local D=dofile("mods/luanttd_core/campaign_worker_depot_ui.lua")(core,client,build,function(n)return "$"..n end)
assert(D.open(mock,"rail",69) and request.kind=="depot" and request.player=="Mine")
local data={offers={{name="Kirby",price=12500,request={mode="rail",operation="buy",parts={0,27}}}},
  vehicles={},targets={{id=8,label="Near"},{id=9,label="Far"}}}
done({ok=true,revision=6,value=data})
assert(body:find("Kirby",1,true))
D.fields(mock,{d1_buy=true})
assert(purchase[1]=="Mine" and purchase[2]=="transport" and purchase[3].parts[2]==27)
purchase[4](true)
data.vehicles={{id=4,label="Train 1"}}
done({ok=true,revision=7,value=data})
D.fields(mock,{d2_start=true,d2_from="2",d2_to="1"})
assert(request.command.mode=="rail" and request.command.vehicle==4 and request.command.first==9 and
  request.command.second==8 and request.command.revision==7)
done({ok=true})
done({ok=true,revision=8,value=data})
assert(body:find("Service dispatched.",1,true))
print("PASS worker depot lists actual offers and starts the selected combination through typed commands")

local Help=dofile("mods/luanttd_core/depot_vehicle_help.lua")
data={
  vehicles={{id=1,label="Unit 1",help=Help.describe("road","passenger","MPS Regal Bus",{capacity=31})},
    {id=2,label="Unit 2",help=Help.describe("road","coal","Balogh Coal Truck",{capacity=20})}},
  offers={},
}
for i,cargo in ipairs({"passenger","mail","oil","wood","livestock","goods","grain","steel","iron_ore"}) do
  local engine="Stock vehicle "..i
  data.offers[i]={name=engine,price=10000,request={kind="road_buy",engine=engine,cargo=cargo},
    help=Help.describe("road",cargo,engine,{capacity=20,speed=48})}
end
assert(D.open(mock,"road",10))
done({ok=true,revision=9,value=data})
assert(body:find("tooltip[d4_offer_row3;",1,true) and body:find("tooltip[d4_unit_row2;",1,true))
assert(body:gsub("%s+"," "):find("Oil Refinery",1,true) and body:gsub("%s+"," "):find("Power Station",1,true))
assert(body:find("scroll_container[",1,true) and body:find("scrollbar[",1,true))
assert(not body:find("d4_offer_next",1,true))
D.fields(mock,{d4_offer_scroll="25"})
assert(body:find("tooltip[d4_offer_row6;",1,true) and body:find("tooltip[d4_offer_row9;",1,true))
assert(body:gsub("%s+"," "):find("Iron Ore",1,true) and body:gsub("%s+"," "):find("Steel Mill",1,true))
D.fields(mock,{d4_offer_row7=true,d4_offer_scroll="25"})
assert(body:find("vertical;d4_offer_scroll;25]",1,true))
assert(body:match("textarea[^%]]-Road freight truck / Grain"),"touch selection shows proper guide")
assert(request.kind=="depot","tap/click to read help does not buy")
D.fields(mock,{d4_buy=true})
assert(request.command.engine=="Stock vehicle 7" and request.command.cargo=="grain")
print("PASS native tooltip controls exist for each selectable row; clipped native scrolling, touch fallback and chosen purchase agree")

data.offers[1].name="Balogh Armoured Truck · Valuables"
data.offers[1].price=7929
data.offers[1].help=Help.describe("road","valuables","Balogh Armoured Truck",{capacity=20,speed=48})
D.open(mock,"road",10)
done({ok=true,revision=10,value=data})
assert(body:find("Balogh Armoured Truck\nValuables · $7929",1,true)
  and not body:find("Balogh Armoured Truck · Valuables · $7929",1,true))
assert(Help.fit(string.rep("É",35),25):match("…$"))
D.fields(mock,{d5_unit_row2=true})
D.fields(mock,{d5_copy=true})
assert(request.kind=="depot_order_sources" and request.vehicle==2 and request.depot==10)
done({ok=true,revision=11,value={vehicle=2,label="Receiving truck",count=2,revision="dst",sources={
  {id=8,label="Source A",count=2,revision="src-a",cargo="Coal"},
  {id=12,label="Source B",count=4,revision="src-b",cargo="Coal"}}}})
assert(body:find("Copy selected orders",1,true) and body:find("independent list",1,true))
D.fields(mock,{dc6_source_row2=true})
D.fields(mock,{dc6_apply=true})
local command=request.command
assert(command.kind=="depot_copy_orders" and command.vehicle==2 and command.depot==10 and command.source==12)
assert(command.source_revision=="src-b" and command.target_revision=="dst" and command.revision==11)
local armed=done
D.fields(mock,{dc6_apply=true})
assert(armed==done,"duplicate native click must not repeat the mutation")
done({ok=false,why="STALE_COMMAND",revision=12})
assert(request.kind=="depot_order_sources")
done({ok=true,revision=12,value={vehicle=2,label="Receiving truck",count=2,revision="dst",sources={
  {id=8,label="Source A",count=2,revision="src-a",cargo="Coal"},
  {id=12,label="Source B",count=4,revision="src-c",cargo="Coal"}}}})
assert(body:find("campaign changed",1,true))
D.fields(mock,{dc6_apply=true})
assert(request.command.source==12 and request.command.source_revision=="src-c")
done({ok=true,revision=13,why="Orders copied."})
assert(body:find("Orders copied.",1,true) and body:find("d5_unit_row2",1,true))
print("PASS long-name row separates price and cargo, full width scroll; independent Copy Orders targets the selected owned vehicle")

local receives={}
_G.core=core
core.register_on_player_receive_fields=function(fn) receives[#receives+1]=fn end
core.register_on_leaveplayer=function()end
local A=dofile("mods/luanttd_core/rail_owned_ui.lua")({authority_handoff=true,s={},
  worker_rail_assembly=client},function()end)
local engine={id=0,name="Kirby",quote={price=5000},help=Help.describe("rail",nil,"Kirby",{},"engine")}
local coach={id=27,name="Coach",quote={price=500},help=Help.describe("rail","passenger","Coach",{},"wagon")}
local oil={id=30,name="Oil Tanker",quote={price=800},help=Help.describe("rail","oil","Oil Tanker",{},"wagon")}
assert(A.assemble(mock,69,nil,nil,{revision=10,value={token=12,revision=1,engines={engine},
  wagons={coach,oil},bodies={},destinations={},units={}}}))
local function assembly(fields) return receives[2](mock,"luanttd_core:rail_fleet",fields) end
assert(body:find("tooltip[assembly_1_pick_wagon;",1,true))
assembly({assembly_1_pick_wagon=true})
assert(body:find("tooltip[assembly_2_pick_row2;",1,true) and body:gsub("%s+"," "):find("Oil Refinery",1,true))
assembly({assembly_2_pick_row2=true})
assert(body:match("textarea[^%]]-Freight wagon / Oil"),"tap/click picker selection displays wagon help")
assembly({assembly_3_buy_wagon=true})
assert(request.command.operation=="wagon" and request.command.stock==30 and request.command.token==12)
_G.core=nil
print("PASS assembly picker rows have their own tooltip and selection, even for unowned wagons")

local picked=nil
assert(D.open(mock,"rail",69,nil,function(mode,id,back) picked={mode,id,back} end))
local rail_depot={offers={},targets={{id=8,label="Near"},{id=9,label="Far"}},vehicles={
  {id=21,label="Train 1"}, {id=22,label="Train 2",order_copy=true}}}
done({ok=true,revision=21,value=rail_depot})
assert(not body:find("Copy orders…",1,true),"Only the parked train exposes Copy Orders.")
local prefix=assert(body:match("(d%d+_)unit_row2"))
D.fields(mock,{[prefix.."unit_row2"]=true})
assert(body:find("Copy orders…",1,true))
D.fields(mock,{[prefix.."copy"]=true})
assert(request.kind=="depot_order_sources" and request.mode=="rail" and request.vehicle==22)
done({ok=true,revision=21,value={vehicle=22,count=0,revision="rail-parked:0",
  sources={{id=21,label="Train 1",count=3,revision="rail-active:4",cargo="Town rail"}}}})
local cp=assert(body:match("(dc%d+_)apply"))
D.fields(mock,{[cp.."apply"]=true})
assert(request.command.source==21 and request.command.vehicle==22 and request.command.source_revision=="rail-active:4")
done({ok=true,revision=22,why="Copied 3 orders."})
assert(request.kind=="depot" and request.depot==69)
rail_depot.vehicles[2].copied=3
rail_depot.vehicles[2].draft_revision="rail-parked:1"
done({ok=true,revision=22,value=rail_depot})
local start=assert(body:match("(d%d+_)start_copied"))
assert(body:find("Copied 3 orders.",1,true) and body:find("Review orders",1,true) and
  not body:find("Start service",1,true))
D.fields(mock,{[start.."orders"]=true})
assert(picked[1]=="rail" and picked[2]==22)
assert(picked[3].depot==69 and not picked[3].initial)
D.fields(mock,{[start.."start_copied"]=true}) -- retired on opening the vehicle screen
assert(request.kind=="depot")
picked[3].return_()
assert(request.kind=="depot" and request.depot==69)
done({ok=true,revision=22,value=rail_depot})
local restored=assert(body:match("(d%d+_)start_copied"))
assert(restored~=start)
D.fields(mock,{[restored.."start_copied"]=true})
assert(request.command.mode=="rail" and request.command.copied and request.command.vehicle==22
  and request.command.draft_revision=="rail-parked:1" and request.command.first==nil)
print("PASS railway depot keeps the parked destination selected and can review/start its independent copied orders")
