local mod="mods/luanttd_core/"
local S=dofile(mod.."sim.lua")
local T=dofile(mod.."openttd/terrain.lua")
local A=dofile(mod.."campaign_road_construction.lua")
local s=S.new(1751)
dofile(mod.."town_layout.lua")(S,s)
s.corner_grid=dofile(mod.."terrain_preview.lua")(S,T,s)
s.road_economy,s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply=true,true,true,true
local owner="Road Company"
local a,b,depot,mark=S.id(11,12),S.id(17,12),S.id(12,13),S.id(14,12)
assert(S.build(s,owner,"road",S.line(a,b)))
assert(S.build(s,owner,"road_station",{a,b}))
assert(S.build(s,owner,"road_depot",{depot}))
local command=A(S,s)
local request={tool="road_waypoint",first=mark,axis=0}
local quote=assert(command.quote(owner,request))
assert(quote.cost==200 and #quote.tiles==1)
assert(command.commit(owner,request,quote))
assert(s.tiles[mark].road_waypoint_id==1 and not s.tiles[mark].station)
assert(s.stock_road_waypoints[1].area.tile==mark)
local source,destination=s.stations[s.tiles[a].station],s.stations[s.tiles[b].station]
local v={owner=owner,engine="bus",cargo="passenger"}
local path,td,cost,frames=S.path(s,source,destination,"road",owner,nil,v,{1})
assert(path and frames and cost>0 and td and path[1]==a and path[#path]==b)
local visits,enter=0,0
for i,f in ipairs(frames) do
  if f[4]==mark then
    assert(f[6]<16 and i<#frames,"waypoint must have continuous running state, not a terminal turn")
    visits=visits+1
    if f[9] then enter=enter+1 end
  end
end
assert(visits>2 and enter==1)
assert(not S.path(s,source,destination,"road",owner,nil,v,{99}),"unresolved waypoint is not silently skipped")
local vehicle=assert(S.purchase(s,owner,"bus","passenger",nil,depot))
assert(S.add_order(s,owner,vehicle,source.id,"full"))
assert(S.add_order(s,owner,vehicle,"waypoint:1"))
assert(S.add_order(s,owner,vehicle,destination.id))
assert(S.toggle(s,owner,vehicle))
local seen=false
for _=1,110 do
  local q=s.fleet[vehicle]
  S.daily(s)
  if q.last_road_waypoint==1 then seen=true end
  if seen and (q.delivered or 0)>0 then break end
end
local actor=s.fleet[vehicle]
assert(seen and actor.delivered>0 and actor.revenue>0)
assert(actor.orders[2].action=="via")
assert(select(2,command.quote(owner,{tool="road_waypoint",first=mark,remove=true}))=="Remove the waypoint from vehicle orders before removing its last tile.")
assert(S.edit_order(s,owner,vehicle,2,"remove"))
s.fleet[vehicle]=nil
local pack=dofile(mod.."packed_campaign.lua")
s=assert(pack.decode(pack.encode(s)))
command=A(S,s)
assert(s.tiles[mark].road_waypoint_id==1)
local clear={tool="road_waypoint",first=mark,remove=true}
local price=assert(command.quote(owner,clear))
assert(price.cost==50)
s.fleet[111]={id=111,owner=owner,engine="bus",road_stop_pose={[4]=mark}}
assert(not command.commit(owner,clear,price) and s.tiles[mark].road_waypoint_id==1)
s.fleet[111]=nil
assert(command.commit(owner,clear,price))
assert(not s.tiles[mark].road_waypoint_id and s.tiles[mark].road_bits==10 and not s.stock_road_waypoints[1])
print("PASS authoritative waypoint placement, stock through movement, saved registry, physical occupancy and pavement-preserving removal")

-- The waypoint has to route traffic somewhere it would not otherwise go.
local detour=S.new(1751)
detour.sites={}
detour.tiles={}
detour.corner_grid=T.new(S.W,S.H,function()return 1 end)
detour.road_stock_clock,detour.road_economy,detour.road_stock_loading,detour.road_stock_house_supply=true,true,true,true
for i=1,S.W*S.H do detour.tiles[i]={h=1,terrain="grass",variant=1} end
S.company(detour,owner)
local anchor=S.id(9,12)
local goal=S.id(19,12)
local off=S.id(14,14)
assert(S.build(detour,owner,"road",S.line(anchor,goal)))
assert(S.build(detour,owner,"road",S.line(S.id(12,12),S.id(12,14))))
assert(S.build(detour,owner,"road",S.line(S.id(12,14),S.id(16,14))))
assert(S.build(detour,owner,"road",S.line(S.id(16,14),S.id(16,12))))
assert(S.build(detour,owner,"road_station",{anchor,goal}))
local anchor_stop=detour.stations[detour.tiles[anchor].station]
local goal_stop=detour.stations[detour.tiles[goal].station]
command=A(S,detour)
assert(command.commit(owner,{tool="road_waypoint",first=off},nil,true))
local base=assert(S.path(detour,anchor_stop,goal_stop,"road",owner,nil,v))
for _,id in ipairs(base) do assert(id~=off,"ordinary direct route needs no waypoint") end
local path,_,_,pos=S.path(detour,anchor_stop,goal_stop,"road",owner,nil,v,{1})
assert(pos and #path>#base)
local touched
for _,id in ipairs(path) do if id==off then touched=true end end
assert(touched,"Go via must select the detour rather than merely label the shortest route")
print("PASS Go via forces the longer route through an actual off-route waypoint")
