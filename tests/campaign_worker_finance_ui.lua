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
print("PASS finance is read from the owner; native borrow/speed actions carry the current revision")
