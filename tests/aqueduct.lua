-- Pure command acceptance and ship topology tests. No Luanti world writes.
local S=dofile("mods/bayline/openttd/slope.lua")
local Bridge=dofile("mods/bayline/openttd/road_bridge.lua")(S)
local A=dofile("mods/bayline/openttd/aqueduct.lua")(Bridge)
local Track=dofile("mods/bayline/openttd/rail_track.lua")
local W=dofile("mods/bayline/openttd/ship_follow.lua")(Track)
local function make(axis,middle,base)
  local grid,ids,loc,cleared={},{},{},{}
  local function pos(i) return axis==0 and i or 1,axis==1 and i or 1 end
  local function id(x,z) return ids[tostring(x)..":"..tostring(z)] end
  for i=0,middle+3 do
    local x,z=pos(i)
    loc[i]={x,z}
    ids[tostring(x)..":"..tostring(z)]=i
    grid[i]={base=base,slope=0,max_z=base,kind="clear"}
  end
  local e=middle+2
  grid[1].slope=axis==0 and 12 or 9;grid[1].max_z=base+1
  grid[e].slope=axis==0 and 3 or 6;grid[e].max_z=base+1
  return {tile=function(i) return grid[i] end,id=id,
    xy=function(i) return unpack(loc[i]) end,
    adjacent=function(i,d)
      local x,z=unpack(loc[i])
      local pp=({[0]={-1,0},{0,1},{1,0},{0,-1}})[d]
      return id(x+pp[1],z+pp[2])
    end,
    clear_quote=function(i,t,role,owner)
      cleared[#cleared+1]={i,role,owner}
      if t.bad then return nil,t.bad end
      return t.clear_cost or 0
    end,
  },grid,e,cleared
end

for axis=0,1 do
  for n=0,12 do
    local b,t,e,cleared=make(axis,n,3)
    -- Dry exterior approaches are legal, though ships cannot use them yet.
    local p=assert(A.plan(b,e,1,{owner=0,year=1,catalog={},roadtype=900}))
    assert(p.start==1 and p["end"]==e and p.axis==axis and p.owner==0)
    assert(p.bridge_type==0 and p.spec.name=="Aqueduct" and p.transport=="water")
    assert(p.water_class=="canal" and p.deck==4 and p.terrain_limit==3)
    assert(p.head.flat_ramp and p.tail.flat_ramp and p.head.foundation=="none")
    assert(n==p.middle_length and n==#p.middle and p.total_length==n+2)
    assert(Bridge.length_factor(n+2)*10000==p.price and p.road_cost==0 and p.roadtype==nil)
    assert(p.total_length*4==p.water_infrastructure_delta)
    assert(A.clear_cost(p)==p.total_length*2000)
    assert(p.recheck_docking[1]==1 and p.recheck_docking[2]==e)
    assert(A.surface(p,1)==p.deck and A.surface(p,e)==p.deck and not A.surface(p,0))
    assert(A.head_record(p,0)==nil and #cleared==2)
    assert(cleared[1][1]==1 and cleared[2][1]==e and cleared[1][2]=="head")
    local left,right=A.head_record(p,1),A.head_record(p,e)
    assert(left.dir==(axis==0 and 2 or 1) and right.dir==(axis==0 and 0 or 3))
    assert(left.other==e and right.other==1 and left.skip==n and right.skip==n)
    assert(W.water_class(left)=="canal")
    local dry=t[0]
    t[1],t[e]=left,right
    -- Stock path follower binds the aqueduct to an outward approach, and
    -- crosses the actual wormhole regardless of the ordinary terrain below.
    local forward=axis==0 and 8 or 1
    local backwards=axis==0 and 0 or 9
    local result=W.follow(b,{},1,forward)
    assert(result.ok and result.bridge and result.tile==e and result.skip==n)
    result=W.follow(b,{},e,backwards)
    assert(result.ok and result.bridge and result.tile==1 and result.skip==n)
    assert(not W.follow(b,{},1,backwards).ok and t[0]==dry)
    t[0]={kind="canal",slope=0,base=4,max_z=4}
    t[e+1]={kind="canal",slope=0,base=4,max_z=4}
    assert(W.follow(b,{},1,backwards).ok)
    result=W.follow(b,{},e,forward)
    assert(result.ok and not result.bridge and result.tile==e+1)
  end
end

local function fixture()
  local b,t,e,cleared=make(0,3,3)
  return b,t,e,cleared
end
local function refusal(change,why,opts)
  local b,t,e=fixture()
  change(t,e,b)
  local p,reason=A.plan(b,1,e,opts or {owner=0})
  assert(not p and reason==why,(reason or "accepted").." ~= "..why)
end
refusal(function(t) t[1].slope=0 end,"LAND_SLOPED_IN_WRONG_DIRECTION")
refusal(function(t) t[1].slope=3 end,"LAND_SLOPED_IN_WRONG_DIRECTION")
refusal(function(t) t[1].slope=8 end,"LAND_SLOPED_IN_WRONG_DIRECTION",{build_on_slopes=true})
refusal(function(t) t[1].base=5 end,"BRIDGEHEADS_NOT_SAME_HEIGHT")
refusal(function(t) t[2].max_z=4 end,"BRIDGE_TOO_LOW_FOR_TERRAIN")
refusal(function(t) t[2].base=0 end,"BRIDGE_TOO_HIGH_FOR_TERRAIN",{max_height=3})
refusal(function(t) t[2].overhead={axis=1,deck=2} end,"MUST_DEMOLISH_BRIDGE_FIRST")
refusal(function(t) t[1].overhead={axis=0,deck=2} end,"MUST_DEMOLISH_BRIDGE_FIRST")
refusal(function(t) t[1].overhead={axis=1,deck=4} end,"MUST_DEMOLISH_BRIDGE_FIRST")
refusal(function() end,"BRIDGE_TOO_LONG",{max_length=2})
refusal(function() end,"INVALID_OWNER",{deity=true})
refusal(function() end,"NOT_ENOUGH_CASH",{budget=5})
refusal(function(t) t[1].bad="PERMISSION_TO_CLEAR" end,"PERMISSION_TO_CLEAR")
refusal(function(t) t[3].kind="lock";t[3].bad="LOCK_CANNOT_CLEAR" end,"LOCK_CANNOT_CLEAR")

do
  local b,t,e=fixture()
  t[1].clear_cost=4;t[e].clear_cost=5
  t[2].kind="river";t[2].bad="MUST_NOT_TOUCH"
  t[3].kind="road";t[3].bad="MUST_NOT_TOUCH"
  t[4].kind="lock";t[4].clear_cost=123
  t[1].overhead={axis=1,deck=8}
  local prices={aqueduct=9,clear_aqueduct=14}
  local p=assert(A.plan(b,1,e,{prices=prices}))
  assert(p.site_cost==132 and p.structure_cost==Bridge.length_factor(5)*9 and #p.clears==3)
  assert(A.clear_cost(p,{prices=prices})==70)
  local editor=assert(A.plan(b,1,e,{prices=prices,company=false}))
  assert(editor.structure_cost==45 and editor.water_infrastructure_delta==0)
  local query=assert(A.plan(b,1,e,{prices=prices,query=true,ai=true,local_company=true,budget=1}))
  assert(query.structure_cost==0 and query.price==132)
  local ai=assert(A.plan(b,1,e,{prices=prices,query=true,ai=true}))
  assert(ai.price==p.price)
end

do
  local b,t,e=fixture()
  local p=assert(A.plan(b,1,e,{owner=7}))
  t[1],t[e]=A.head_record(p,1),A.head_record(p,e)
  local _,err=A.plan(b,1,e,{owner=9})
  assert(err=="ALREADY_BUILT")
  local _,quote_err=A.plan(b,1,e,{owner=9,query=true})
  assert(quote_err=="AREA_IS_OWNED_BY_ANOTHER")
  local quote=assert(A.plan(b,1,e,{owner=7,query=true}))
  assert(quote.replacement and quote.price==10000 and quote.water_infrastructure_delta==0)
end
print("PASS: aqueduct heads/costs/clearance across both axes; water topology, underlay preservation, quotes, and ownership")
