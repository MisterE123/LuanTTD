local root="mods/bayline/"
local src=root.."openttd/"
local Sim=dofile(root.."sim.lua")
local Terrain=dofile(src.."terrain.lua")
local Follow=dofile(src.."yapf_road_follow.lua")
local Slope=dofile(src.."road_slope.lua")
local Cost=dofile(src.."yapf_road_cost.lua")(Follow)
local Search=dofile(src.."yapf_road_search.lua")(Follow,Cost)
local OneWay=dofile(src.."road_oneway.lua")(Slope,Follow)
local World=dofile(root.."road_oneway_world.lua")(Sim,Terrain,Follow,OneWay)
local RouteBoard=dofile(root.."road_yapf_board.lua")
local id=Sim.id
local owner="Traffic Ltd"
local other="Other Ltd"
local function assert_eq(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local function clone(t)
  if type(t)~="table" then return t end
  local out={}
  for k,v in pairs(t) do out[k]=clone(v) end
  return out
end
local function world()
  local s=Sim.new(1751)
  s.road_economy=true;s.road_stock_clock=true;s.road_stock_loading=true
  s.corner_grid=Terrain.new(Sim.W,Sim.H,function() return 0 end)
  for y=11,14 do for x=6,20 do
    s.tiles[id(x,y)]={terrain="grass",h=0,variant=0}
  end end
  Sim.company(s,owner);Sim.company(s,other)
  return s
end
local function section(s,y,x,u,bits)
  for i=x,u do s.tiles[id(i,y)]={terrain="grass",h=0,build="road",owner=owner,road_bits=bits or 10,variant=0} end
end
local function cash(s) return s.companies[owner].cash end
local function step(x,y,td,sub)
  return {x*16+8,y*16+5,td==8 and 5 or 1,id(x,y),1,td,[15]=sub or 8}
end
local function closed(s,previous,wanted,expected)
  local ok,why,at=World.guard(s,previous,wanted)
  assert(not ok and why==expected,tostring(why).." != "..expected)
  return at
end
local whole={start_half=false,end_half=true}

-- Read-only forward and reverse quotations bind the pointer-down endpoint,
-- real direction and exact amount. YAPF's real road board is wrapped, not
-- reimplemented. Quote never creates a company or mutates terrain/finance.
local s=world()
local prev=cash(s)
local fwd=assert(World.quote(s,owner,id(8,12),id(13,12),0))
local rev=assert(World.quote(s,owner,id(13,12),id(8,12),0))
assert_eq(fwd.cost,10*95+6*20)
assert_eq(rev.cost,fwd.cost)
assert_eq(fwd.drag.direction,2);assert_eq(rev.drag.direction,0)
assert(s.tiles[id(9,12)].build==nil and cash(s)==prev and s.topology==0)
fwd.cost=0;fwd.changes[1].road_bits=15 -- client previews are never authority
s.companies[owner].cash=5
local ok,why=World.commit(s,owner,fwd)
assert(not ok and why=="NOT_ENOUGH_CASH" and not s.tiles[id(8,12)].build and s.topology==0)
s.companies[owner].cash=prev
ok,why=World.commit(s,other,fwd)
assert(not ok and why=="STALE_ONEWAY_QUOTE" and s.topology==0)
local cost,dirty
ok,cost,dirty=World.commit(s,owner,fwd)
assert(ok and cost==10*95+6*20 and #dirty==6 and cash(s)==prev-cost)
assert(s.companies[owner].expense==cost and s.companies[owner].month_exp==cost and s.topology==1)
assert(s.road_oneway_revision==1 and Sim.road_bits(s,id(8,12))==2)
assert_eq(World.read(s.tiles[id(9,12)]),1)
assert_eq(s.tiles[id(9,12)].road_disallowed,1)
assert(World.marking(s,id(8,12))==nil)
local mark=World.marking(s,id(9,12))
assert(mark and mark.dir==2 and mark.kind=="arrow" and mark.axis==0 and mark.slope==0 and mark.base==0 and mark.x==9 and mark.z==12)
ok,why=World.commit(s,owner,rev)
assert(not ok and why=="STALE_ONEWAY_QUOTE")
ok,why=World.commit(s,owner,fwd)
assert(not ok and why=="STALE_ONEWAY_QUOTE") -- even replay of zero/known cost
local wrong=s.tiles[id(9,12)]
local noaccess=select(2,World.quote(s,"Unknown",id(9,12),id(9,12),0,whole))
assert(noaccess=="COMPANY_REQUIRED" and s.companies.Unknown==nil and World.read(wrong)==1)

-- A peer on the ground prevents opening into a new direction after
-- quoting. Upper bridge decks and tunnel bores are not that ground.
local v=s.fleet
local q=assert(World.quote(s,owner,id(9,12),id(9,12),0,{start_half=true,end_half=false}))
assert(q.changes[1].disallowed==3)
v[1]={id=1,engine="bus",running=false,owner=other,road_stop_pose=step(9,12,8)}
ok,why=World.commit(s,owner,q)
assert(not ok and why=="VEHICLE_IN_THE_WAY" and World.read(wrong)==1 and s.topology==1)
v[1].road_stop_pose[10],v[1].road_stop_pose[12]=9,true
assert(not World.occupied(s,id(9,12)))
assert(World.commit(s,owner,q))
local m=World.marking(s,id(9,12))
assert(m and m.kind=="no-entry" and m.dir==nil)
assert_eq(World.read(wrong),3)
v[1].road_stop_pose[10],v[1].road_stop_pose[12]=nil,nil
assert(World.occupied(s,id(9,12)))
-- Closing is not contagious onto the neighboring lane/road, and allowing
-- a direction again is safe even while a stopped peer is on that tile.
assert(World.build(s,owner,id(9,12),id(9,12),0,{start_half=true,end_half=false}))
assert_eq(World.read(wrong),1)
assert(World.build(s,owner,id(9,12),id(9,12),0,whole))
assert_eq(World.read(wrong),0)
assert(not World.marking(s,id(9,12)))
assert(cash(s)==prev-cost)

-- Ground fleet fallback and sparse external occupancy share one predicate.
assert(World.occupied(s,id(9,12),{vehicles_at=function() return nil end}))
assert(World.occupied(s,id(9,12),{vehicles_at=function() return {[40]={type="tram"}} end}))
assert(not World.occupied(s,id(9,12),{vehicles_at=function() return {{underground=true},{elevated=true}} end}))
local junction=World.quote(s,owner,id(9,12),id(9,12),0,whole)
assert(not junction)
v[1]=nil
s.tiles[id(9,12)].road_town=1;s.tiles[id(9,12)].owner=nil
local bad,err=World.quote(s,owner,id(9,12),id(9,12),0,whole)
assert(not bad and err=="OWNED_BY")
s.tiles[id(9,12)].road_town=nil;s.tiles[id(9,12)].owner=owner
local terrain_quote=assert(World.quote(s,owner,id(9,12),id(9,12),0,whole))
s.corner_grid.revision=s.corner_grid.revision+1
assert(select(2,World.commit(s,owner,terrain_quote))=="STALE_ONEWAY_QUOTE")

-- Route with a real alternate loop. Reverse an existing sign while a
-- vehicle has a saved eastbound leg, then guard its physical next step.
-- Retrying the same frozen candidate after reopening is immediately legal.
s=world()
section(s,12,7,19)
section(s,13,10,16)
s.tiles[id(10,12)].road_bits=14
s.tiles[id(16,12)].road_bits=14
s.tiles[id(10,13)].road_bits=3
s.tiles[id(16,13)].road_bits=9
assert(Sim.build(s,owner,"road_station",{id(18,12)}))
local stop=s.tiles[id(18,12)].station
local original=RouteBoard(Sim,s,Follow)
local yboard=World.path_board(s,original)
local vehicle={id=3,owner=owner,engine="bus",cargo="passenger",dest=stop,route={id(9,12),id(11,12),id(12,12),id(18,12)},
  road_motion_frames={step(11,12,8),step(12,12,8)},road_speed_state={index=1}}
s.fleet[3]=vehicle
-- This one fixed test actor appears on 11 so operate on 12–14.
assert(World.build(s,owner,id(14,12),id(12,12),0))
local before,wanted=vehicle.road_motion_frames[1],vehicle.road_motion_frames[2]
assert_eq(World.read(s.tiles[wanted[4]]),2)
assert_eq(yboard.tile(wanted[4]).disallowed,2)
assert(original.tile(wanted[4]).disallowed==nil)
assert_eq(closed(s,before,wanted,"WRONG_ONE_WAY_DIRECTION"),wanted[4])
assert(World.guard(s,before,wanted,{tram=true}))
assert(World.guard(s,step(13,12,0),step(12,12,0)))
assert(s.fleet[3].road_speed_state.index==1 and vehicle.route[3]==wanted[4])
local held=clone(s)
assert_eq(World.read(held.tiles[wanted[4]]),2)
assert_eq(closed(held,held.fleet[3].road_motion_frames[1],held.fleet[3].road_motion_frames[2],
  "WRONG_ONE_WAY_DIRECTION"),wanted[4])
local current=step(9,12,8) -- before the junction, so safe path can branch
local reroute=assert(World.reroute(s,vehicle,current,original,Search,Cost,{display_max_speed=112,compatible={[0]=true}}))
assert(reroute.origin_frame[1]==current[1] and reroute.origin_frame[15]==current[15])
assert(reroute.trace[1].tile==id(9,12) and reroute.trace[1].td==8)
local detour=false
for _,n in ipairs(reroute.trace) do
  if n.tile==id(13,13) then detour=true end
  assert(n.tile~=id(13,12),"alternative path used the illegal main lane")
end
assert(detour and reroute.trace[#reroute.trace].tile==id(18,12))
local invalid=step(12,12,8)
assert_eq(closed(s,invalid,step(13,12,8),"ONEWAY_CURRENT_POSE_BLOCKED"),invalid[4])
local reversal=step(12,12,14)
assert_eq(closed(s,step(12,12,0),reversal,"WRONG_ONE_WAY_DIRECTION"),invalid[4])
local bridge=step(12,12,8);bridge[10],bridge[12]=1,true
assert(World.guard(s,before,bridge)) -- elevated road movement is independent
assert(World.build(s,owner,id(14,12),id(12,12),0))
assert(World.guard(s,before,wanted))
assert_eq(held.tiles[wanted[4]].road_disallowed,2) -- restore case didn't share the live mutated record
assert(s.fleet[3].road_speed_state.index==1)

-- Legacy motion cannot sneak across a newly directed tile. Existing
-- unsupported facilities do not acquire markings or alter their finance.
vehicle.road_motion_frames=nil
vehicle.progress=1
assert(select(2,World.quote(s,owner,id(14,12),id(12,12),0))=="LEGACY_ROAD_ROUTE_IN_THE_WAY")
local tile=s.tiles[id(18,12)]
assert(World.marking(s,id(18,12))==nil and World.read(tile)==0)
local b=World.quote(s,owner,id(18,12),id(18,12),0,whole)
assert(not b and tile.build=="road_station")
-- Native vertical markings use Z, not the other diagonal stock axis.
local vertical=world()
for y=10,15 do vertical.tiles[id(17,y)]={terrain="grass",h=0,build="road",owner=owner,road_bits=5} end
local pv=assert(World.quote(vertical,owner,id(17,11),id(17,14),1))
assert(World.commit(vertical,owner,pv))
local north_south=assert(World.marking(vertical,id(17,12)))
assert(north_south.dir==1 and north_south.axis==1 and north_south.x==17 and north_south.z==12)
vertical.tiles[id(17,13)].level_crossing={}
local rejected=World.quote(vertical,owner,id(17,13),id(17,13),1,whole)
assert(not rejected and World.marking(vertical,id(17,13))==nil)
vertical.rail_tunnel_below={[id(17,12)]=1}
rejected=World.quote(vertical,owner,id(17,12),id(17,12),1,whole)
assert(not rejected and World.read(vertical.tiles[id(17,12)])==2)
print("PASS one-way world quote/atomic finance, ground occupancy, save fields, guard and real directed detour")
