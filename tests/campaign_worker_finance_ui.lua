local req,done,shown
local engine={formspec_escape=function(s)return s end,show_formspec=function(_,_,body)shown=body end}
local ui=dofile("mods/luanttd_core/campaign_worker_finance_ui.lua")(engine,{
  query=function(r,f) req,done=r,f;return true end,
},function()return "10 NOV 1950" end,function(x)return "$"..x end)
local p={get_player_name=function()return "Own" end}
assert(ui.show(p) and req.player=="Own")
done({ok=true,revision=6,value={cash=12345,loan=0,can_speed=true,year=1950}})
assert(shown:find("$12345",1,true))
assert(ui.fields(p,{f1_borrow=true}) and req.command.kind=="company_loan" and req.command.revision==6)
done({ok=true,why="Worker applied loan."})
done({ok=true,revision=7,value={cash=22345,loan=10000,can_speed=true,year=1950}})
assert(shown:find("$22345",1,true) and shown:find("Worker applied loan.",1,true))
assert(ui.fields(p,{f2_speed_0=true}) and req.command.kind=="speed" and req.command.speed==0)
done({ok=true,why="Paused."})
done({ok=true,revision=8,value={cash=22345,loan=10000,can_speed=true,year=1950,world_town_growth=2}})
assert(shown:find(";f3_world_rules;World rules]",1,true))
assert(ui.fields(p,{f3_world_rules=true}))
assert(shown:find("Town growth (all towns)",1,true) and shown:find(";f3_growth;None,Slow,Normal,Fast,Very fast;3;true]",1,true))
assert(ui.fields(p,{f3_growth="1"}) and req.kind=="company","Selecting a choice must not change the world")
assert(ui.fields(p,{f3_apply_growth=true}) and req.kind=="command" and req.command.kind=="town_growth_setting")
assert(req.command.rate==0 and req.command.revision==8)
done({ok=true,why="World town growth set to None."})
done({ok=true,revision=9,value={cash=22345,loan=10000,can_speed=true,year=1950,world_town_growth=0}})
assert(shown:find(";f4_growth;None,Slow,Normal,Fast,Very fast;1;true]",1,true))
local visitor={get_player_name=function()return "Visitor" end}
assert(ui.show(visitor))
done({ok=true,revision=10,value={cash=5000,loan=10000,can_speed=false,year=1950,world_town_growth=0}})
assert(not shown:find("_world_rules",1,true))
assert(ui.fields(visitor,{f5_growth="5",f5_apply_growth=true}) and req.kind=="company")
print("PASS worker finance, playback, stock world-growth selection, stale IDs and role guarding")
