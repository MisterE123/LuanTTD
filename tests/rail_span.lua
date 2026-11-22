local root="mods/bayline/openttd/"
local T=dofile(root.."rail_track.lua")
local F=dofile(root.."rail_follow.lua")(T)
local S=dofile(root.."slope.lua")
local Site=dofile(root.."rail_span_site.lua")
local Q=dofile(root.."rail_construction.lua")(T,dofile(root.."rail_signals.lua")(T))
local B=dofile(root.."rail_bridge.lua")(dofile(root.."road_bridge.lua")(S),Q,Site)
local U=dofile(root.."rail_tunnel.lua")(dofile(root.."road_tunnel.lua"),Q,Site,T)
local Terrain=dofile(root.."terrain.lua")
local function id(x,z) if x>=0 and z>=0 and x<=31 and z<=31 then return x+32*z end end
local function xy(i)return i%32,math.floor(i/32) end
local offsets={[0]=-1,32,1,-32}
local map={}
local b={tile=function(i)return map[i] end,xy=xy,tile_at=id,adjacent=function(i,d)return i+offsets[d] end,max_x=31}
local function clear(x,z,base,shape,fields)
  local i=id(x,z)
  local record={kind="clear",base=base,slope=shape or 0,max_z=base+(shape and shape~=0 and 1 or 0),density=0}
  for k,v in pairs(fields or {}) do record[k]=v end
  map[i]=record;return i
end
local function rejection(exp,p,why,...)
  assert(not p and why==exp,tostring(why).." ~= "..exp)
  return ...
end
local function check_follow(plan)
  local h,t=plan.head,plan.tail
  local old_h,old_t=map[h.id],map[t.id]
  map[h.id],map[t.id]=h,t
  local v={owner=plan.owner,railtype=plan.railtype,compatible={[plan.railtype]=true}}
  local f=F.follow(b,v,h.id,T.diagonal_trackdir(h.dir))
  assert(f.ok and f.tile==t.id and f.skip==plan.middle_length)
  local g=F.follow(b,v,t.id,T.diagonal_trackdir(t.dir))
  assert(g.ok and g.tile==h.id and g.skip==plan.middle_length)
  map[h.id],map[t.id]=old_h,old_t
end

-- Build a stock X bridge across ordinary rail, open water and a tunnel.
local h=clear(2,6,2,12,{density=3})
local w=clear(3,6,0,0,{kind="water"})
local rail=clear(4,6,1,0,{kind="signals",owner="rival"})
local sub=clear(5,6,1,0,{kind="tunnel",owner="rival"})
local t=clear(6,6,2,0)
local original={}
for k,v in pairs(map) do original[k]=v end
local p=assert(B.plan(b,t,h,0,{owner="Alice"}))
assert(p.start==h and p["end"]==t and p.deck==3 and p.site_cost==20)
assert(p.middle_length==3 and p.total_length==5 and p.middle_by_tile[sub])
assert(p.rail_cost==500 and p.structure_cost==601 and p.price==1121)
assert(p.head.flat_ramp and not p.tail.flat_ramp and p.infrastructure_delta==20)
assert(p.head.dir==T.SW and p.tail.dir==T.NE)
assert(B.pixel(p,h,8,8)==24 and B.pixel(p,t,14,8)==17 and B.pixel(p,w,8,8)==24)
assert(B.surface(p,h,1,.5)==B.surface(p,w,0,.5))
check_follow(p)
for k,v in pairs(map) do assert(v==original[k],"predicate mutated map") end
local q=assert(B.plan(b,h,t,111,{owner="Alice",query=true}))
assert(q.price==20 and q.rail_cost==0 and q.structure_cost==0)
rejection("BRIDGE_UNAVAILABLE",B.plan(b,h,t,111,{owner="Alice"}))
rejection("BRIDGE_TOO_LONG",B.plan(b,h,t,0,{owner="Alice",max_length=2}))
rejection("NOT_ENOUGH_CASH",B.plan(b,h,t,0,{owner="Alice",budget=1120}))
map[rail].max_z=3
assert(rejection("BRIDGE_TOO_LOW_FOR_TERRAIN",B.plan(b,h,t,0,{owner="Alice"}))==rail)
map[rail].max_z=1;map[rail].overhead={deck=5,axis=1}
assert(rejection("MUST_DEMOLISH_BRIDGE_FIRST",B.plan(b,h,t,0,{owner="Alice"}))==rail)
map[rail].overhead=nil
rejection("BRIDGE_TOO_HIGH_FOR_TERRAIN",B.plan(b,h,t,0,{owner="Alice",max_height=2}))
map[t].kind="depot";map[t].owner="rival"
rejection("AREA_IS_OWNED_BY_ANOTHER",B.plan(b,h,t,0,{owner="Alice"}))
map[t]=original[t];map[t].kind="clear"
for _,k in ipairs({h,t}) do
  local m=map[k]
  m.kind="bridge";m.transport="rail";m.other=k==h and t or h
  m.owner="Alice";m.railtype=0;m.bridge_type=0
  m.reserved_bits=1
end
map[rail].max_z=10
q=assert(B.plan(b,h,t,2,{owner="Alice",year=1950}))
assert(q.replacement and q.preserve_reservation and q.head.reserved_bits==1 and q.tail.reserved_bits==1)
assert(q.site_cost==-100 and q.rail_cost==500 and q.infrastructure_delta==0)
assert(#q.clears==0)
rejection("ALREADY_BUILT",B.plan(b,h,t,0,{owner="Alice"}))
map[h].owner="rival"
rejection("AREA_IS_OWNED_BY_ANOTHER",B.plan(b,h,t,2,{owner="Alice"}))
map[h].owner=nil
q=assert(B.plan(b,h,t,2,{owner="Alice"}));assert(q.owner=="Alice" and q.infrastructure_delta==20)
map[h].owner="town";map[h].bridge_type=2
rejection("LOCAL_AUTHORITY_REFUSES_TO_ALLOW_THIS",B.plan(b,h,t,0,{owner="Alice"}))
assert(B.plan(b,h,t,0,{owner="Alice",editor=true}))
map[h].owner="Alice";map[h].railtype=1
rejection("MUST_DEMOLISH_BRIDGE_FIRST",B.plan(b,h,t,2,{owner="Alice"}))
local allowed=assert(B.plan(b,h,t,0,{owner="Alice",railtype=1,can_build_railtype=function(r)return r==1 end}))
assert(allowed.rail_cost==750)

-- Shared-corner terrain: first same-base tunnel exit needs one actual
-- TerraformLand corner lowering, no change to the original grid.
local grid=Terrain.new(12,12,function(x,z)
  if x<3 or x>5 then
    return (x==6 and z==4) and 1 or 0
  end
  return 1
end)
map={}
for x=1,8 do
  local shape,base,top=Terrain.tile(grid,x,4)
  clear(x,4,base,shape,{max_z=top})
end
local entrance,exit=id(2,4),id(5,4)
assert(map[entrance].slope==3 and map[exit].slope==13)
local did_excavate=0
b.terraform_quote=function(i,mask,up,excluded)
  assert(i==exit and mask==1 and up==false and excluded[entrance] and excluded[exit])
  did_excavate=did_excavate+1
  local x,z=xy(i)
  local plan=assert(Terrain.plan(grid,x,z,mask,up,{unit_cost=250}))
  local slope=Terrain.tile(grid,x,z,plan)
  return {cost=plan.cost,plan=plan,slope=slope}
end
p=assert(U.plan(b,entrance,{owner="Alice"}))
assert(p.start==entrance and p["end"]==exit and p.middle_length==2 and p.axis==T.X)
assert(p.excavation_mask==1 and did_excavate==1 and p.excavation_cost==250 and p.tail.slope==12)
assert(p.structure_cost==1975 and p.rail_cost==400 and p.price==2625)
assert(p.head.dir==T.SW and p.tail.dir==T.NE and p.head.other==exit)
assert(map[exit].slope==13 and Terrain.tile(grid,5,4)==13)
assert(U.pixel(p,entrance)==0 and U.pixel(p,id(3,4))==0)
check_follow(p)
assert(Terrain.apply(grid,p.excavation.plan))
assert(Terrain.tile(grid,5,4)==12)

local traversals={}
b.tunnel_in_way=function(i,z,dir)
  assert(z==0 and dir==T.SE)
  traversals[#traversals+1]=i
  return i==id(4,4)
end
rejection("ANOTHER_TUNNEL_IN_THE_WAY",U.plan(b,entrance,{owner="Alice",max_length=1}))
assert(#traversals==2)
map[exit].slope=0 -- stock first equal-base search still terminates here
local fast=assert(U.plan(b,entrance,{owner="Alice",crossing_tunnels=true}))
assert(fast.excavation.noop and fast.tail.slope==0 and fast.excavation_cost==0)
assert(rejection("TUNNEL_TOO_LONG",U.plan(b,entrance,{owner="Alice",max_length=1,crossing_tunnels=true}))==exit)
map[exit].kind="water"
assert(rejection("CANT_BUILD_ON_WATER",U.plan(b,entrance,{owner="Alice",crossing_tunnels=true}))==exit)
map[exit].kind="station"
local bad,cause=rejection("UNABLE_TO_EXCAVATE_LAND",U.plan(b,entrance,{owner="Alice",crossing_tunnels=true}))
assert(bad==exit and cause=="BUILDING_MUST_BE_DEMOLISHED")
print("PASS: stock rail bridge geometry/upgrades/reservations and rail tunnel first exit, exact excavation and path metadata")
