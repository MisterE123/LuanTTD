local root="mods/luanttd_core/"
local S=dofile(root.."sim.lua")
local function upstream(n) return dofile(root.."openttd/"..n..".lua") end
local Terrain=upstream("terrain")
local Construction=upstream("tram_construction")(upstream("road_slope"),upstream("road_bridge")(upstream("slope")).roadtypes)
local F=upstream("yapf_road_follow")
local C=upstream("yapf_road_cost")(F)
local Motion=upstream("tram_motion")(upstream("tram_motion_data"),upstream("road_motion")(upstream("road_motion_data")))
local Network=dofile(root.."tram_network.lua")(S,Construction,Terrain)
local Trip=dofile(root.."tram_trip.lua")(F,C,upstream("yapf_road_search")(F,C),Motion)
local Run=dofile(root.."tram_preview_run.lua")(Network,Trip,upstream("road_speed"))
local Pose=dofile(root.."road_source_pose.lua")(S,dofile(root.."road_motion_presentation.lua")(dofile(root.."road_lanes.lua")))
local s=S.new(1751)
s.sites,s.tiles={},{}
s.corner_grid=Terrain.new(S.W,S.H,function(_,z) return z>=12 and 2 or 1 end)
for i=1,S.W*S.H do
  local x,z=S.xy(i)
  local _,base=Terrain.tile(s.corner_grid,x,z)
  s.tiles[i]={terrain="grass",h=base,variant=1}
end
local function at(x,z) return assert(S.id(x,z)) end
local owner="Hillside Tram Service"
local function build(kind,where,arg) return assert(Network.construct(s,owner,kind,where,arg)) end
local depot,lower,upper,ramp=at(5,10),at(8,8),at(8,13),at(8,11)
build("depot",{depot},F.SW)
build("road",S.line(at(6,10),at(8,10)))
build("road",{at(6,10)},8)
build("road",S.line(at(8,7),at(8,14)))
build("drive_stop",{lower},F.SE)
build("drive_stop",{upper},F.SE)
local q=assert(Network.surface(s,ramp))
assert(q.grade==6 and q.base==1)
local pilot=assert(Run.start(s,owner,depot,lower,upper))
local previous,up,down,min,max=nil,false,false,1000,0
for i=1,3500 do
  Run.advance(s,1,function(f)
    local p,_,pitch=Pose.sample(s,{f},1,1,function(id,x,z)
      return (Network.surface_at(s,id,x,z) or s.tiles[id].h)+.512
    end)
    min,max=math.min(min,p.y),math.max(max,p.y)
    if previous then assert(math.abs(previous-p.y)<.17) end
    previous=p.y
    if f[4]==ramp and pitch<-.3 then up=true end
    if f[4]==ramp and pitch>.3 then down=true end
  end)
  if pilot.arrivals>=4 then break end
end
assert(pilot.arrivals>=4 and up and down and math.abs(min-1.512)<.001 and math.abs(max-2.512)<.001)
print("PASS stock tram route crosses a real source incline both ways with continuous sampled elevation and opposite chassis pitch")
