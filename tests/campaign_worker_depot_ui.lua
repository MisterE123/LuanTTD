local body,request,done
local core={formspec_escape=function(x)return x end,
  show_formspec=function(_,_,x) body=x end,
  explode_textlist_event=function(x)return {index=tonumber(x)} end}
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
