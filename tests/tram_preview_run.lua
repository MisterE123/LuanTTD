local root="mods/luanttd_core/"
local S=dofile(root.."sim.lua")
local function upstream(n) return dofile(root.."openttd/"..n..".lua") end
local Terrain=upstream("terrain")
local Construction=upstream("tram_construction")(upstream("road_slope"),upstream("road_bridge")(upstream("slope")).roadtypes)
local F=upstream("yapf_road_follow")
local C=upstream("yapf_road_cost")(F)
local RoadMotion=upstream("road_motion")(upstream("road_motion_data"))
local Motion=upstream("tram_motion")(upstream("tram_motion_data"),RoadMotion)
local Network=dofile(root.."tram_network.lua")(S,Construction,Terrain)
local Trip=dofile(root.."tram_trip.lua")(F,C,upstream("yapf_road_search")(F,C),Motion)
local Run=dofile(root.."tram_preview_run.lua")(Network,Trip,upstream("road_speed"))
local s=S.new(1751)
s.corner_grid=Terrain.new(S.W,S.H,function() return 0 end)
for _,t in ipairs(s.tiles) do t.h=0;t.terrain="grass";t.wood=nil;t.house=nil;t.site=nil;t.build=nil end
local function at(x,z) return S.id(x,z) end
local company="Municipal Tramways"
local function build(kind,a,arg)
  return assert(Network.construct(s,company,kind,a,arg))
end
local depot,first,second=at(5,10),at(8,8),at(8,13)
build("depot",{depot},F.SW)
build("road",S.line(at(6,10),at(8,10)))
build("road",{at(6,10)},8)
build("road",S.line(at(8,7),at(8,14)))
build("drive_stop",{first},F.SE)
build("drive_stop",{second},F.SE)
assert(not S.build(s,company,"road",{at(8,13),at(9,13)}),"ordinary road altered the tram platform")
local mixed=at(7,10)
s.tiles[mixed].build="road";s.tiles[mixed].road_bits=10
local no,why=Run.start(s,company,depot,first,second)
assert(not no and why=="mixed_traffic_not_enabled")
s.tiles[mixed].build=nil
local run=assert(Run.start(s,company,depot,first,second))
assert(not Run.frame(run) and not Run.clear(s,"not its owner"))
assert(Run.uses(s,at(8,7)) and Run.uses(s,at(8,14)) and not Run.uses(s,at(9,14)))
Run.advance(s,17)
assert(not Run.frame(run) and run.phase=="depot")
Run.advance(s,1)
assert(Run.frame(run)[4]==depot)
local last
local function observe(f)
  if last then assert(math.abs(last[1]-f[1])<=1 and math.abs(last[2]-f[2])<=1) end
  last=f
end
for i=1,1750 do if run.arrivals==1 then break end;Run.advance(s,1,observe) end
assert(run.arrivals==1 and run.phase=="stopped" and Run.frame(run)[4]==first)
local function save(v)
  if type(v)~="table" then
    assert(type(v)=="number" or type(v)=="boolean" or type(v)=="string")
    return v
  end
  assert(not getmetatable(v))
  local t={}
  for k,p in pairs(v) do t[k]=save(p) end
  return t
end
s=save(s);run=Run.current(s)
last=Run.frame(run)
-- Resume at the exact previous stop, pass both turnarounds and finish a
-- second complete circuit on the same persisted plan.
for arrival=2,6 do
  for i=1,1750 do if run.arrivals==arrival then break end;Run.advance(s,1,observe) end
  assert(run.arrivals==arrival and Run.frame(run)[4]==(arrival%2==1 and first or second))
end
assert(Run.clear(s,company) and not Run.frame(Run.current(s)))
print("PASS: saved dedicated streetcar moves at stock rate, makes repeat stops, follows both one-half reversals, and rejects mixed running")
