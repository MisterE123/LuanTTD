local R=dofile("mods/luanttd_core/openttd/road_reconstruction.lua")
local function shallow(t)
  local d={}
  for k,v in pairs(t) do d[k]=v end
  return d
end
assert(R.cost==136718 and R.months==6)
local town={}
R.fund(town)
assert(town.road_build_months==6)
local accepted=0
for rand=0,65535 do
  if R.chance(rand) then accepted=accepted+1 end
  assert(R.chance(rand)==R.chance(rand+65536))
end
assert(accepted==1638 and R.chance(1637) and not R.chance(1638))

local used,probes=0,0
local function random() used=used+1;return 1637 end
local function clear() probes=probes+1;return true end
local s={kind="road",grade=0,roadside="trees",road_bits=2,tram_bits=8}
assert(not R.visit(s,town,8,0,clear,random))
assert(used==0 and probes==0)
assert(not R.visit({kind="depot"},town,0,4,clear,random))
assert(not R.visit({kind="road",grade=0,road_bits=2,tram_bits=2},town,0,0,clear,random))
assert(not R.visit({kind="road",grade=3,road_bits=10},town,0,0,clear,random))
assert(not R.visit(s,town,7,0,function() return false end,random))
assert(used==0 and probes==0)
local new=assert(R.visit(s,town,7,0,clear,random))
assert(new.effect=="start" and new.works=="paved" and new.counter==0)
assert(used==1 and probes==1 and not s.works)
local other=shallow(s)
other.roadside="grass"
local grass=assert(R.visit(other,town,30,2,clear,random))
assert(grass.works=="grass")
town.road_build_months=0
assert(not R.visit(s,town,0,4,clear,random))
for i=1,14 do
  s.works,s.counter=new.works,new.counter
  new=assert(R.visit(s,town,0,4,nil,nil))
  assert(new.effect=="progress" and new.counter==i)
end
s.works,s.counter=new.works,new.counter
local finish=assert(R.visit(s,nil,nil,nil,nil,nil))
assert(finish.effect=="complete" and finish.roadside=="paved" and finish.counter==0 and not finish.works)
print("PASS RC1 municipal road reconstruction funding, exact eligibility/random admission and 15 stock landscape visits")
local around={{kind="trees"},{kind="station",tram_bits=8},
  {kind="rail",normal=true,track_bits=1,grade=0},{kind="water",real_water=true}}
assert(R.cleanup(15,function(d) return around[d] end)==7)
around[1]={kind="rail",normal=true,track_bits=1,grade=3}
around[2]={kind="structure",road_bits=1}
around[3]={kind="water",real_water=false}
around[4]={kind="road",road_bits=0}
assert(R.cleanup(15,function(d) return around[d] end)==12)
around[1]={kind="clear"}
around[2]={kind="rail",normal=true,track_bits=2,grade=0}
around[3]={kind="void"};around[4]=nil
assert(R.cleanup(15,function(d) return around[d] end)==3)
print("PASS stock CleanUpRoadBits preserves natural and future connects, but not nonreciprocal structures, junction rails, or open water")

do
  local p="mods/luanttd_core/"
  local S=dofile(p.."sim.lua")
  local Terrain=dofile(p.."openttd/terrain.lua")
  local G=dofile(p.."openttd/town_growth.lua")
  local Slope=dofile(p.."openttd/road_slope.lua")
  local F=dofile(p.."openttd/yapf_road_follow.lua")
  local Board=dofile(p.."road_yapf_board.lua")
  local W=dofile(p.."road_reconstruction_world.lua")(S,Terrain,G,R,Slope)
  local s=S.new(1751)
  s.tiles,s.stations={},{}
  s.corner_grid=Terrain.new(S.W,S.H)
  for i=1,S.W*S.H do s.tiles[i]={terrain="grass",h=0,variant=1} end
  local function at(x,z) return assert(S.id(x,z)) end
  s.sites={{id=1,kind="town",tile=at(12,12),name="Live road works"}}
  s.stock_town_growth={version=1,order={1},towns={[1]=G.new(1,12,12)}}
  local b=dofile(p.."town_growth_runtime.lua")(S,Terrain,G,{},dofile(p.."openttd/town_passengers.lua"))
  s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
  S.mount_stock_town_growth(s,b)
  local finance=S.company(s,"Road owner")
  local q=S.quote_road_reconstruction(s,"Road owner",1)
  assert(q.cost==136718 and not q.affordable and q.months==0)
  finance.cash=200000
  local A=dofile(p.."campaign_authority_endpoint.lua")(S,{world=s})
  local req={kind="town_fund_roads",town=1,cost=q.cost,revision=0}
  assert(A.command("Road owner",req).ok)
  assert(finance.cash==63282 and finance.expense==136718 and s.stock_town_growth.reconstruction.funded==1)
  assert(A.command("Road owner",req).why=="STALE_COMMAND")
  assert(A.town_authority("Road owner",1).value.reconstruction.months==6)

  local site=at(14,12)
  s.tiles[site]={build="road",road_bits=11,road_town=1,terrain="grass",h=0,variant=1}
  s.tiles[at(14,11)].house=true
  local function zero() return 0 end
  local function clear() return true end
  local function visit()
    return W.visit(s,14,12,zero,clear)
  end
  local before=s.topology
  assert(F.status(Board(S,s,F).tile(site),false)~=0)
  assert(visit()=="start")
  assert(s.changed[#s.changed]==site and s.topology==before+1 and s.tiles[site].roadworks=="paved")
  assert(F.status(Board(S,s,F).tile(site),false)==0,"YAPF cannot choose a closing road tile")
  assert(not S.autoroad_plan(s,"Road owner",site,site,0,false,true))
  for i=1,14 do
    assert(visit()=="progress" and s.tiles[site].roadworks_counter==i)
    assert(s.topology==before+1)
  end
  for month=1,6 do
    s.day=month*30
    b.prepare_day(s);b.month(s,b.month_due(s),zero)
    assert(s.stock_town_growth.towns[1].road_build_months==6-month)
  end
  assert(s.stock_town_growth.reconstruction.funded==0 and s.stock_town_growth.reconstruction.active==1)
  local P=dofile(p.."packed_campaign.lua")
  s=assert(P.decode(P.encode(s)))
  assert(s.tiles[site].roadworks_counter==14 and s.stock_town_growth.reconstruction.active==1)
  assert(visit()=="complete")
  assert(s.stock_town_growth.reconstruction.active==0 and s.stock_town_growth.reconstruction.completed==1)
  assert(s.topology==before+2 and not s.tiles[site].roadworks and S.road_bits(s,site)==10)
  assert(F.status(Board(S,s,F).tile(site),false)~=0)
  print("PASS real authority expense, persisted reconstruction clock and closed-route gate, source expiry and blocked stub cleanup")
end

do
  local p="mods/luanttd_core/"
  local F=dofile("tests/road_oneway_live_fixture.lua")(p,dofile("tests/road_overtake_fixture.lua"))
  local S,id,target=F.Sim,F.id,F.target
  local s,car,dest=F.fixture()
  local function roadworks(world,on)
    world.tiles[target].roadworks=on and "paved" or nil
    world.roadworks_revision=(world.roadworks_revision or 0)+1
  end
  roadworks(s,true)
  local held,v
  for _=1,8 do
    S.daily(s)
    v=s.fleet[car]
    if v.road_speed_state and v.road_speed_state.waiting=="roadworks" then
      held=S.road_motion_frame(s,v)
      assert(held[4]==id(11,12) and v.status=="Waiting for roadworks")
      break
    end
  end
  assert(held and not v.last_road_arrival_tick)
  roadworks(s,false)
  for _=1,12 do
    S.daily(s)
    if v.last_road_arrival_tick then break end
  end
  assert(v.last_road_arrival_tick and F.reached(s,car,dest))

  local other,bus,stop=F.fixture()
  local branch={id(10,12)}
  for x=10,16 do branch[#branch+1]=id(x,13) end
  branch[#branch+1]=id(16,12)
  assert(S.build(other,F.owner,"road",branch))
  roadworks(other,true)
  v=other.fleet[bus]
  local old=S.road_motion_frame(other,v)
  S.daily(other)
  assert(v.road_speed_state and v.road_speed_state.oneway_reroutes==1)
  local changed=S.road_motion_timeline(other,bus)
  local first=changed.frames[changed.cursors[1]]
  assert(first[1]==old[1] and first[2]==old[2] and first[3]==old[3] and first[4]==old[4])
  local detour=false
  for _,tile in ipairs(v.route) do
    assert(tile~=target)
    if tile==id(13,13) then detour=true end
  end
  assert(detour)
  for _=1,12 do
    S.daily(other)
    if v.last_road_arrival_tick then break end
  end
  assert(v.last_road_arrival_tick and F.reached(other,bus,stop))
  print("PASS live paid road service waits and safely resumes at temporary works, or takes a genuine stock YAPF bypass from the exact current pose")
end
