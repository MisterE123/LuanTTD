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

local third=at(8,9)
build("drive_stop",{third},F.SE)
local adapters=dofile(root.."road_vehicle_orders.lua")({s=s,Sim=S,tram={run=Run,
  reason=function(r)return r end,
  facility=function(name,tile,kind)
    local t=s.tiles[tile]
    return t and t.tram and t.tram.owner==name and t.tram.kind==kind
  end}})
local tram=adapters.tram
local function read() return assert(tram.read(company,1)) end
local function edit(op,idx,to) return tram.edit(company,1,read().revision,op,idx,to) end
assert(not tram.read("rival",1))
local orig=read().revision
assert(edit("append",1,third))
assert(not tram.edit(company,1,orig,"remove",1))
assert(edit("skip",3))
assert(Run.frame(run)[4]==second)
for step=1,2000 do
  Run.advance(s,1,observe)
  if run.arrivals>=7 then break end
end
assert(run.arrivals==7 and Run.frame(run)[4]==third)
assert(edit("up",3))
assert(read().items[2].id==third)
assert(edit("remove",3))
assert(read().items[2].id==third)
for step=1,2000 do
  Run.advance(s,1,observe)
  if run.arrivals>=8 then break end
end
assert(run.arrivals==8 and Run.frame(run)[4]==first)
-- A skip while still moving changes the order cursor without recording
-- the obsolete physical approach as a serviced visit.
for step=1,1000 do
  Run.advance(s,1,observe)
  if run.phase=="running" and run.index>2 then break end
end
assert(run.phase=="running" and read().active==2)
assert(edit("skip",1))
for step=1,2000 do
  Run.advance(s,1,observe)
  if run.arrivals>=9 then break end
end
assert(run.arrivals==9 and Run.frame(run)[4]==first)
assert(Run.clear(s,company) and not Run.frame(Run.current(s)))
print("PASS running streetcar accepts insert, move, remove and skip; follows edited stops without snapping in motion")
