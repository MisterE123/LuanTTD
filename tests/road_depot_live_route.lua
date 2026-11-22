-- The proposal begins at the existing exact traveled sub-tile frame.
local root="mods/luanttd_core/"
local function m(n) return dofile(root..n..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local F=m("openttd/yapf_road_follow")
local C=m("openttd/yapf_road_cost")(F)
local Search=m("openttd/yapf_road_search")(F,C)
local Motion=m("openttd/road_motion")(m("openttd/road_motion_data"))
local R=m("road_yapf_route")(Sim,F,C,Search,m("road_yapf_board"),Motion,m("road_motion_leg"))
local s=Sim.new(1751)
s.road_economy,s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply=true,true,true,true
dofile(root.."town_layout.lua")(Sim,s)
s.corner_grid=dofile(root.."terrain_preview.lua")(Sim,T,s)
local at=Sim.id
local a,b,e=at(9,12),at(18,12),at(17,13)
assert(Sim.build(s,"A","road",Sim.line(a,b)))
assert(Sim.build(s,"A","road_station",{a,b}))
assert(Sim.build(s,"A","road_depot",{e}))
local sa=s.tiles[a].station;local sb=s.tiles[b].station
local v={engine="bus",owner="A",cargo="passenger"}
local _,_,_,normal=R.route(s,s.stations[sa],s.stations[sb],"A",v)
assert(normal)
local checked=0
for _,f in ipairs(normal) do
  if f[4]==at(15,12) and f[15]>3 and f[15]<12 then
    local path,tile,td,cost,frames=R.from_live_frame(s,v,f,nil)
    assert(path and path[1]==f[4] and tile==e and cost>0 and cost<=2000)
    assert(frames[#frames][4]==e and frames[#frames][15]==Motion.DEPOT_STOP)
    assert(frames[1][1]==f[1] and frames[1][2]==f[2] and frames[1][3]==f[3])
    local route,dest,_,_,resume=R.from_live_frame(s,v,f,sb)
    assert(route and dest==b and resume[1][1]==f[1] and resume[1][2]==f[2])
    v.road_speed_state={lane_pose=f}
    assert(not R.from_live_frame(s,v,f,nil))
    v.road_speed_state=nil
    local corrupt={unpack(f)}
    corrupt[1]=f[1]+1
    assert(not R.from_live_frame(s,v,corrupt,nil))
    checked=checked+1
  end
end
assert(checked>=6)
print("PASS: actual directed mid-road pose, owned depot with no snap and planned station resume, in "..checked.." subtile samples")
