local opened,request,callback,form
local core={get_us_time=function()return 1234 end,formspec_escape=function(x)return x end,
  show_formspec=function(_,_,s)form=s end}
local client={query=function(q,done)request,callback=q,done;return true end}
local pointed=8133
local ui=dofile("mods/luanttd_core/town_founding_ui.lua")(core,client,tostring,
  function()return pointed,68,63 end,function()opened=true;return true end)
local p={get_player_name=function()return "Builder" end}
assert(ui.open(p,2,"original"))
assert(form:find("Site: tile 68, 63",1,true) and form:find("Custom layout",1,true)==nil)
assert(ui.fields(p,{t1_name="Rivermark",t1_size="2",t1_city="true",t1_layout="5"}))
assert(not request,"Options must not invoke the authority before review")
pointed=9012
assert(ui.fields(p,{t1_review=true}))
assert(request.kind=="town_found_quote" and request.request.tile==8133 and request.request.layout=="random")
callback({ok=true,revision=9,value={name="Rivermark",city=true,cost=26250000,affordable=true,resolved_layout="grid2"}})
assert(form:find("Founding cost: 26250000",1,true))
assert(ui.fields(p,{t0_confirm=true}) and request.kind=="town_found_quote")
assert(ui.fields(p,{t1_confirm=true,t1_size="1"}))
assert(request.kind=="command" and request.command.request.tile==8133 and request.command.request.size=="medium"
  and request.command.cost==26250000 and request.command.revision==9)
callback({ok=true,value={name="Rivermark",cost=26250000,population=804}})
assert(form:find("Starting population: 804",1,true))
assert(ui.fields(p,{t1_back=true}) and opened)
assert(ui.open(p,1,"better"))
assert(form:find("Street layout: Better roads",1,true) and not form:find("t2_layout",1,true))
print("PASS Found Town UI binds the selected tile, reviews price and keeps confirmation options immutable")
