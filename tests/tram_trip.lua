local root="mods/luanttd_core/"
local upstream=root.."openttd/"
local F=dofile(upstream.."yapf_road_follow.lua")
local C=dofile(upstream.."yapf_road_cost.lua")(F)
local Search=dofile(upstream.."yapf_road_search.lua")(F,C)
local Road=dofile(upstream.."road_motion.lua")(dofile(upstream.."road_motion_data.lua"))
local Motion=dofile(upstream.."tram_motion.lua")(dofile(upstream.."tram_motion_data.lua"),Road)
local Trip=dofile(root.."tram_trip.lua")(F,C,Search,Motion)
local E=dofile(upstream.."road_bridge.lua")(dofile(upstream.."slope.lua"))
local Construction=dofile(upstream.."tram_construction.lua")(dofile(upstream.."road_slope.lua"),E.roadtypes)
local vehicle={owner="A",cargo="passenger",tramtype=1,display_max_speed=96}

local function id(x,z) return z*100+x end
local function xy(n) return n%100,math.floor(n/100) end
local delta={[0]=-1,100,1,-100}
local records={}
local B={xy=xy,tile_at=id,
  tile=function(n) return records[n] end,
  adjacent=function(n,d) return n+delta[d] end,
  tram_bits=function(n,inside) return Construction.effective_bits(records[n],inside) end,
  center_z=function(n) return records[n].base*8 end}
function B.station_area(n,kind)
  local t=records[n]
  if t and t.stop_type==kind then return {tile=n,w=1,h=1},n end
end
function B.edge_available(a,b,d)
  if not records[a] or not records[b] or records[a].base~=records[b].base then return false end
  local bit,opp=8/2^d,8/2^F.reverse_direction(d)
  return math.floor(B.tram_bits(a)/bit)%2==1 and math.floor(B.tram_bits(b)/opp)%2==1
end
function B.stop_entry() return 0,16 end
function B.stop_continues() return false end
function B.can_build_tram() return false end
local function road(x,z,bits)
  records[id(x,z)]={kind="road",tramtype=1,tram_bits=bits,base=0}
  return id(x,z)
end
local function through(x,z,axis)
  local n=road(x,z,axis==0 and 10 or 5)
  local t=records[n]
  t.kind,t.dir,t.owner,t.station,t.stop_type="drive_stop",axis,"A",n,"bus"
  return n
end
local function depot(x,z,dir)
  local n=road(x,z,8/2^dir)
  local t=records[n]
  t.kind,t.dir,t.owner="depot",dir,"A"
  return n
end
local function fits(frames)
  assert(#frames>16)
  local rotates=0
  for i,f in ipairs(frames) do
    local previous=frames[i-1]
    assert(f[4]==id(math.floor(f[1]/16),math.floor(f[2]/16)))
    assert(f[3]>=0 and f[3]<8 and f[5]>=0 and f[5]<=1)
    if previous then
      assert(math.abs(f[1]-previous[1])<=1 and math.abs(f[2]-previous[2])<=1,
        ("jump %d %d,%d -> %d,%d"):format(i,previous[1],previous[2],f[1],f[2]))
      if f[1]==previous[1] and f[2]==previous[2] then
        assert((f[3]-previous[3])%8==1 or (previous[3]-f[3])%8==1)
        rotates=rotates+1
      end
    end
    for flag=10,12 do assert(f[flag]==nil) end -- ground stays ground
  end
  return rotates
end

local west=depot(1,1,F.SW)
local lead=road(2,1,10)
local corner=road(3,1,12) -- -X to +Z
local middle=road(3,2,5)
local platform=through(3,3,1)
local head=road(3,4,1) -- single -Z tram bit; stock big-turn endpoint
local route,td,cost,frames,trace=Trip.route(B,west,platform,vehicle)
assert(route,"no depot-to-stop route: "..tostring(td))
assert(#route==5 and route[2]==lead and route[3]==corner and route[4]==middle)
assert(td==F.direction_trackdir(F.SE) and cost>0 and #trace==5)
assert(fits(frames)>=2)
assert(frames[1][4]==west and frames[1][6]==8)
assert(frames[#frames][4]==platform and frames[#frames][6]==65)
local _,sx,sy=Motion.sample(65,1,11)
assert(frames[#frames][1]==16*3+sx and frames[#frames][2]==16*3+sy)

vehicle.tram_arrival_td=td
local got,back,cost2,ret,return_trace=Trip.route(B,platform,west,vehicle)
assert(got,"no locked-direction return via the one-half track: "..tostring(back))
assert(#got==7 and got[2]==head and got[3]==platform and got[#got]==west)
assert(#return_trace==8 and return_trace[2].tile==head and return_trace[3].tile==head)
assert(return_trace[2].td==1 and return_trace[3].td==9)
assert(cost2>cost and back==0 and fits(ret)>=4)
assert(ret[1][1]==frames[#frames][1] and ret[1][2]==frames[#frames][2] and ret[1][3]==frames[#frames][3])
local count=0
for _,point in ipairs(ret) do
  if point[4]==head then
    assert(point[6]==Motion.reverse_trackdir[F.SE]);count=count+1
  end
end
assert(count>=37, "one-half endpoint did not drive the complete stock turn")
assert(ret[#ret][4]==west and ret[#ret][6]==0)
-- Departing that depot is possible again with the stored opposite inbound td.
vehicle.road_arrival_td=back;vehicle.tram_arrival_td=nil
assert(Trip.route(B,west,platform,vehicle))
-- Articulated units, altered grades, incompatible depot owner, and
-- passenger trams stopping at cargo-only facilities may not teleport.
vehicle.articulated=true;assert(not Trip.route(B,west,platform,vehicle));vehicle.articulated=nil
records[corner].base=1;assert(not Trip.route(B,west,platform,vehicle));records[corner].base=0
records[west].owner="B";assert(not Trip.route(B,west,platform,vehicle));records[west].owner="A"
records[platform].stop_type="truck";assert(not Trip.route(B,west,platform,vehicle));records[platform].stop_type="bus"
records[head]=nil
vehicle.tram_arrival_td=td
assert(not Trip.route(B,platform,west,vehicle),"broken one-half should not allow autonomous short reversing")

-- A supplied live controller reversal request may instead operate on a
-- straight full tile when the next tile cannot be built (here: water).
local first=through(1,6,0)
local second=road(2,6,10)
local last=road(3,6,10)
local reverse=F.direction_trackdir(F.NE)
local forward=F.direction_trackdir(F.SW)
local requested={
  {tile=first,td=forward},{tile=second,td=forward},{tile=last,td=forward},
  {tile=last,td=reverse},{tile=second,td=reverse},{tile=first,td=reverse}}
for side=0,1 do
  local short,err=Trip.compile(B,requested,vehicle,{road_side=side})
  assert(short,err);assert(fits(short)>=2)
  local n=0
  for _,f in ipairs(short) do if f[4]==last and f[6]==Motion.reverse_trackdir[F.SW] then n=n+1 end end
  assert(n>=4 and n<10)
end
function B.can_build_tram(_,n,bit) assert(n==id(4,6) and bit==8);return true end
local denied,why=Trip.compile(B,requested,vehicle)
assert(not denied and why=="awaiting_track")
print("PASS: stock tram depot/stop trip, real junction motion, one-half YAPF reversal, explicit short/wait branches, continuous terminal poses")

-- Same trip through the actual construction and save-tile ingress adapter.
local Sim=dofile(root.."sim.lua")
local Terrain=dofile(upstream.."terrain.lua")
local N=dofile(root.."tram_network.lua")(Sim,Construction,Terrain)
local s=Sim.new(1751)
s.corner_grid=Terrain.new(Sim.W,Sim.H)
for x=8,15 do for z=7,16 do
  local t=s.tiles[Sim.id(x,z)]
  t.terrain="grass";t.h=0;t.house=nil;t.site=nil;t.wood=nil;t.build=nil;t.owner=nil
end end
local a,b,turn=Sim.id(9,8),Sim.id(12,11),Sim.id(12,12)
local function build(kind,ids,value)
  local dirty,why=N.construct(s,"A",kind,ids,value)
  assert(dirty,why)
end
build("depot",{a},F.SW)
build("drive_stop",{b},1)
local approach=Sim.id(10,8)
build("road",{approach},8)
build("road",Sim.line(approach,turn))
local board=N.board(s)
local outbound,out_td,_,out_frames=Trip.route(board,a,b,{owner="A",cargo="passenger"})
assert(outbound and out_td==1 and outbound[1]==a and outbound[#outbound]==b and out_frames[#out_frames][4]==b)
local inbound,back_td,_,back_frames,official_trace=Trip.route(board,b,a,
  {owner="A",cargo="passenger",road_arrival_td=out_td})
assert(inbound and inbound[2]==turn and official_trace[3].tile==turn and back_td==0)
assert(back_frames[#back_frames][4]==a and back_frames[1][4]==b)
assert(back_frames[1][1]==out_frames[#out_frames][1] and back_frames[1][2]==out_frames[#out_frames][2])
print("PASS: exact tram movement and YAPF round trip on the real constructed flat save network")
