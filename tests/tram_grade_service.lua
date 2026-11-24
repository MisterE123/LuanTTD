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
s.corner_grid=Terrain.new(S.W,S.H,function(x,z)
  if x==5 and z==10 then return 0 end -- depot: one low corner away from its door
  if x==9 and z==13 then return 1 end -- stop: flatten the three raised corners
  return z>=12 and 2 or 1
end)
for i=1,S.W*S.H do
  local x,z=S.xy(i)
  local _,base=Terrain.tile(s.corner_grid,x,z)
  s.tiles[i]={terrain="grass",h=base,variant=1}
end
local function at(x,z) return assert(S.id(x,z)) end
local owner="Hillside Tram Service"
local function build(kind,where,arg) return assert(Network.construct(s,owner,kind,where,arg)) end
local depot,lower,upper,ramp=at(5,10),at(8,8),at(8,13),at(8,11)
local Transport=dofile(root.."campaign_transport_commands.lua")(S,{world=s,tram={net=Network}})
local function command(kind,id,direction,cost)
  local q=assert(Transport.quote(owner,{mode="tram",operation="build",kind=kind,cells={id},direction=direction}))
  assert(q.price==cost and q.tiles[1]==id)
  local ok,receipt,applied=Transport.commit(owner,q)
  assert(ok,receipt)
  assert(applied.tiles[1]==id)
end
local depot_q=assert(Network.plan(s,owner,"depot",{depot},F.SW))
assert(depot_q[1].record.terminal_level==1)
local _,depot_cost=Network.plan(s,owner,"depot",{depot},F.SW)
assert(depot_cost==750)
command("depot",depot,F.SW,750)
s.stock_road_town_policy={build_on_slopes=false}
local blocked,why=Network.plan(s,owner,"drive_stop",{upper},F.SE)
assert(not blocked and why=="FLAT_LAND_REQUIRED")
s.stock_road_town_policy=nil
build("road",S.line(at(6,10),at(8,10)))
build("road",{at(6,10)},8)
build("road",S.line(at(8,7),at(8,14)))
build("drive_stop",{lower},F.SE)
local _,stop_cost=Network.plan(s,owner,"drive_stop",{upper},F.SE)
assert(stop_cost==450)
command("drive_stop",upper,F.SE,450)
assert(s.tiles[upper].tram.terminal_level==2)
local top=assert(Network.surface(s,upper))
assert(top.base==2 and top.grade==0 and top.foundation=="leveled")
s.tiles[upper].tram.terminal_level=nil -- equivalent legacy/imported field
assert(Network.surface(s,upper).base==2)
s.tiles[upper].tram.terminal_level=2
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
local bad,err=Network.plan(s,owner,"drive_stop",{at(19,11)},F.SE)
assert(not bad and err=="FLAT_LAND_REQUIRED" and not s.tiles[at(19,11)].tram)
local shared=at(8,12)
local t=s.tiles[shared]
-- Existing through pavement of the same height must not be replaced or
-- charged as new track. This fixture is away from the city allocator.
local r=at(9,12)
local rt=s.tiles[r]
rt.build,rt.road_bits,rt.owner="road",5,owner
local _,level=S.road_surface(s,r)
assert(level==2)
command("drive_stop",r,F.SE,830)
assert(rt.build=="road" and rt.road_bits==5 and rt.owner==owner)
assert(Network.surface(s,r).base==2)
assert(t.tram and t.tram.kind=="road")
print("PASS stock graded depot and platform levels; live tram route crosses a real source incline both ways with continuous sampled elevation and opposite chassis pitch")

-- RC1 GUI frontage: spend only on missing opposite half-pieces at
-- immediate normal neighbors with an existing compatible tram layer.
local function frontage_sites(x)
  local terminal,west,east=at(x,16),at(x-1,16),at(x+1,16)
  build("road",{west},8)
  build("road",{east},2)
  return terminal,west,east
end
local a,w,e=frontage_sites(24)
local q,cost=Network.plan(s,owner,"drive_stop",{a},0)
assert(#q==3 and q[2].id==w and q[3].id==e and cost==960)
command("drive_stop",a,0,960)
assert(s.tiles[w].tram.tram_bits==10 and s.tiles[e].tram.tram_bits==10)

local b,_,outside=frontage_sites(28)
local c=S.company(s,owner)
c.cash=500
local pts,amount=Network.plan(s,owner,"depot",{b},F.SW)
assert(#pts==1 and amount==500)
command("depot",b,F.SW,500)
assert(s.tiles[outside].tram.tram_bits==2)
c.cash=10000
local third,_,rside=frontage_sites(32)
local blocked,price=Network.plan(s,owner,"depot",{third},F.SW,function(id) return id==rside end)
assert(#blocked==1 and price==500)
local fix,fee=Network.plan(s,owner,"depot",{third},F.SW)
assert(#fix==2 and fix[2].id==rside and fix[2].record.tram_bits==10 and fee==690)
command("depot",third,F.SW,690)
local fourth,road=at(36,16),at(37,16)
s.tiles[road].build,s.tiles[road].road_bits="road",10
command("depot",fourth,F.SW,500)
assert(not s.tiles[road].tram and s.tiles[road].road_bits==10)
print("PASS stock tram frontage: both platform ends and depot opening, untouched road-only mouth, and blocked or unaffordable optional track")

local War=dofile(root.."campaign_road_construction.lua")(S,s,nil,nil,{tram={net=Network}})
local one,side=at(39,16),at(40,16)
build("road",{side},2)
local req={tool="tram_facility",kind="depot",first=one,direction=F.SW}
local visible=assert(War.quote(owner,req))
assert(visible.cost==690 and #visible.tiles==2)
local cash=c.cash
s.tiles[side].roadworks=true
local valid,stale=War.commit(owner,req,visible,true)
assert(not valid and stale=="ROAD_QUOTE_CHANGED" and not s.tiles[one].tram and c.cash==cash)
s.tiles[side].roadworks=nil
local placed,message,tiles=War.commit(owner,req,visible,true)
assert(placed and message=="Tram depot built for $690." and tiles[1]==one and tiles[2]==side)
assert(s.tiles[one].tram.kind=="depot" and s.tiles[side].tram.tram_bits==10 and c.cash==cash-690)
local two=at(43,16)
local quick={tool="tram_facility",kind="drive_stop",first=two,direction=F.NE}
assert(War.commit(owner,quick,nil,true) and s.tiles[two].tram.kind=="drive_stop")
print("PASS tram facility click uses the normal one-turn road placement result, rejects withdrawn frontage, and permits quick clicks without a hover quote")
