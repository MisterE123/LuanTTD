-- SPDX-License-Identifier: GPL-2.0-only
-- Exercise production quote, revalidation and paid geometry persistence.
local mod="mods/luanttd_core"
local source=mod.."/openttd/"
local Sim=dofile(mod.."/sim.lua")
local Terrain=dofile(source.."terrain.lua")
local Slope=dofile(source.."slope.lua")
local Bind=dofile(mod.."/campaign_simulation_bindings.lua")(Sim,mod)
local s=Sim.new(1751)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function() return 0 end)
for i=1,#s.tiles do s.tiles[i]={terrain="grass",h=0} end
local function ground(id) return Terrain.tile(s.corner_grid,Sim.xy(id)) end
local net=Bind.networks(s,Slope,ground)
local signal=dofile(source.."rail_signals.lua")(net.track)
local owner="rail-engineer"
local c=Sim.company(s,owner)
local rights={[2]=true}
local Tools=Bind.rail_build({s=s,Sim=Sim,terrain={tile=ground},
  company_can_build_stock_railtype=function(who,gauge) return who==owner and rights[gauge] end,
  render={update=function() end},save=function() end},net,nil,signal)
local a,b=Sim.id(31,30),Sim.id(33,30)
local X,Y=net.track.X,net.track.Y
assert(not Tools.quote_track(owner,a,b,X,false,3))
local plan=assert(Tools.quote_track(owner,a,b,X,false,2))
assert(plan.gauge==2 and #plan.ids==3 and plan.price==660)
local cash=c.cash
rights[2]=nil
assert(not Tools.build(owner,plan) and c.cash==cash and not s.tiles[a].rail_tracks)
rights[2]=true
assert(Tools.build(owner,plan))
assert(c.cash==cash-660 and s.tiles[a].rail_type==2 and s.tiles[b].rail_type==2)
assert(not Tools.build(owner,plan) and c.cash==cash-660,"stale typed quote spent twice")
assert(not Tools.quote_track(owner,a,a,Y,false,0))
local split=assert(Tools.quote_track(owner,a,a,Y,false,2))
assert(split.price==200)
assert(Tools.build(owner,split) and s.tiles[a].rail_tracks==3 and s.tiles[a].rail_type==2)
assert(Tools.build(owner,assert(Tools.quote_track(owner,a,a,Y,true))))
assert(Tools.build(owner,assert(Tools.quote_track(owner,a,a,X,true))))
assert(not s.tiles[a].rail_type and not s.tiles[a].rail_tracks)
assert(c.cash==cash-660-200+140)
local layout={axis=0,tracks=1,length=1,railtype=2}
local before=c.cash
s.sites={{id=1,kind="town",tile=Sim.id(33,32),name="Station Test"}}
s.stock_road_town_policy={dist_local_authority=3}
c.stock_town_authority_ratings={[1]=-200}
local denied,reason=Tools.quote_station(owner,b,b,layout)
assert(not denied and reason:find("local authority",1,true))
assert(Tools.quote_depot(owner,Sim.id(36,31),2,2),"Depot is not governed by station permission")
assert(Tools.quote_track(owner,Sim.id(32,31),Sim.id(32,31),X,false,2),"Track is independent of station permission")
s.stock_road_town_policy.dist_local_authority=2
local terminal=assert(Tools.quote_station(owner,b,b,layout))
assert(terminal.price==510 and terminal.gauge==2)
s.stock_road_town_policy.dist_local_authority=3
assert(not Tools.build(owner,terminal) and c.cash==before,"An intervening town refusal must invalidate the rail ticket")
s.stock_road_town_policy.dist_local_authority=2
assert(Tools.build(owner,terminal))
assert(s.tiles[b].rail_station_id and s.tiles[b].rail_type==2 and c.cash==before-510)
local engine_shed=Sim.id(36,31)
local depot=assert(Tools.quote_depot(owner,engine_shed,2,2))
before=c.cash
assert(depot.price==820, depot.price)
assert(Tools.build(owner,depot) and c.cash==before-820)
assert(s.tiles[engine_shed].rail_type==2 and s.tiles[engine_shed].rail_depot_dir==2)
assert(Tools.quote_depot(owner,engine_shed,2,2).noop)
assert(not Tools.quote_depot(owner,engine_shed,2,3))
local saved=dofile(mod.."/packed_campaign.lua")
local reopened=saved.decode(saved.encode(s))
assert(reopened.tiles[b].rail_type==2 and reopened.tiles[b].rail_tracks==1)
assert(reopened.companies[owner].cash==c.cash)
print("PASS stock gated monorail quote: type, price, stale protection, mixed-gauge rejection and authoritative roundtrip")
