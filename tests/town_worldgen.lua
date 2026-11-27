local mod="mods/luanttd_core/"
local function m(n)return dofile(mod..n..".lua")end
local G=m("openttd/town_growth")
local Build=m("openttd/town_growth_build")(G,m("openttd/town_growth_houses"))
local W=m("openttd/town_worldgen")(G,Build)

local function list(values)
  local at=0
  return function()
    at=at+1;assert(values[at]~=nil,"Unexpected random draw "..at)
    return values[at]
  end,function()return at end
end
local function tile(x,z)
  return {kind="clear",slope=0}
end
local board={width=64,height=64,tile=tile}
local roll,draws=list({7})
assert(W.count(board,{difficulty=2},roll)==9 and draws()==1)
assert(W.count(board,{difficulty=4,custom_count=3},roll)==3 and draws()==1)
assert(W.count({width=128,height=64,tile=tile},{difficulty=4,editor=true},function()return 0 end)==1)
assert(W.can_place(board,{},12,12))
assert(not W.can_place(board,{},11,12))
assert(not W.can_place(board,{},52,12))
assert(not W.can_place(board,{{x=12,z=12}},22,21))
assert(W.can_place(board,{{x=12,z=12}},22,22))
local x,z=W.align(29,31,"grid2");assert(x==27 and z==30)
x,z=W.align(29,31,3);assert(x==28 and z==28)
assert(W.resolve_layout(32,16,"random")=="grid3")
assert(W.resolve_layout(0,64,"random")=="grid3") -- unsigned hash decrement
local b={width=64,height=64,freeform=true,tile=function(x,z)
  return {kind=x<=19 and "water" or "clear",slope=(z==26 and 1 or 0)}
end}
assert(W.water_distance(b,23,25)==4)
assert(W.water_distance(b,18,25)==0)
x,z=W.coast(b,16,21,"grid2");assert(x==24 and z==15,(tostring(x)..","..tostring(z)))
-- The first flat position creates no population. It must be rolled back
-- before the next candidate and must not reserve a physical town center.
local rnd,n=list({321,24+64*24,45+64*39})
local names=0
local out=W.generate(board,{difficulty=4,custom_count=1,larger_towns=0,random=rnd,
  name=function(used,r)names=names+1;local p=r();used.Foo=true;return p,"Foo" end,
  create=function(c,r)
    assert(names==1 and c.nameparts==321)
    return {x=c.x,z=c.z,population=c.x>30 and 1 or 0}
  end,
  remove=function(rec)assert(rec.x==24) end})
assert(out.success and out.attempted_positions==2 and out.failed_growth==1 and out.towns[1].x==45 and n()==3)
-- Twenty attempts use one candidate name and permanently reserve it in
-- the first pass. Hard fallback gets only the actually accepted names.
local counters,soft={},true
local function forge(used,r)
  counters[#counters+1]=used.Erroneous and "kept" or "fresh"
  if #counters==2 then assert(used.Exists) end
  used.Erroneous=true
  return 0,"Erroneous"
end
local num=0
local fallback=W.generate({width=64,height=64,tile=tile,towns={{x=12,z=12,name="Exists"}}},{
  difficulty=4,custom_count=1,larger_towns=0,
  random=function()num=num+1;return num<=20 and 0 or 39+64*39 end,name=forge,
  rebuild_index=function()soft=false end,
  create=function(c)assert(not soft and c.x==39);return {x=c.x,z=c.z,population=4} end})
assert(fallback.success and fallback.fallback and fallback.soft_positions==20 and fallback.hard_positions==1)
assert(counters[1]=="fresh" and counters[2]=="fresh")
-- Tiny real board: nondestructive proposal/commit path, not a hand-authored
-- town or a shortcut that stuffs the old population independently of houses.
local Ori=m("openttd/original_terrain")(m("openttd/slope"))
local seed={1751,1751}
local random=function()return Ori.next_random(seed) end
local test_town=G.new(0,23,23,{layout="grid3",larger_town=true})
local map={}
local function key(x,z)return x+64*z end
local c={}
function c.tile(x,z)
  if x<0 or x>62 or z<0 or z>62 then return {kind="void"} end
  return map[key(x,z)] or {kind="clear",slope=0,max_z=8,base=1}
end
function c.road_quote(t,x,z,bits)
  local q=c.tile(x,z)
  return (q.kind=="clear" or q.kind=="road" and q.road_town==t.id) and (q.road_bits or 0)~=bits
end
function c.distance_to_edge(x,z) return math.min(x,z,63-x,63-z) end
function c.clean_road_bits(_,x,z,bits) return bits end
function c.road_allowed() return true end
function c.house_supported(i) return i==0x19 or i==0x18 or i==0x1a or i==0x06 or i==0x0e end
local pop,houses,roads=0,0,0
local function commit(p)
  if p.kind=="road" then
    map[key(p.x,p.z)]={kind="road",slope=0,max_z=8,base=1,road_bits=p.bits,road_town=p.town}
    roads=roads+1
  else
    houses=houses+1
    if p.completed then pop=pop+p.root_population;assert(p.stage==3 and p.counter==0)
    else assert(p.stage<3 and p.counter<4) end
    for _,h in ipairs(p.parts) do map[key(h.x,h.z)]={kind="house",h=h} end
  end
  return true
end
local t,detail=W.initialize(test_town,c,{year=1950,initial_city_size=2,allow_roads=true,commit=commit},random)
assert(detail.attempts==4*detail.mass and detail.mass%2==0 and detail.mass>=16 and detail.mass<=46)
assert(roads>=2 and houses>=3 and pop>=30)
assert(t.num_houses==houses and t.population==pop and t.supplied.passenger.old_max==math.floor(pop/8))
assert(t.supplied.mail.old_max==math.floor(pop/16) and t.time_until_rebuild==10)
local p={parts={{},{}},root_population=18}
local rr,nn=list({13,0})
assert(W.house_stage(p,rr)==0 and p.stage==1 and p.counter==3 and not p.parts[2].completed and nn()==2)
rr,nn=list({3,0})
assert(W.house_stage(p,rr)==18 and p.stage==3 and p.counter==0 and p.parts[2].completed and nn()==2)
print(("TOWN_WORLDGEN_PASS: stock placement/fallback order, real growth (%d houses, %d roads, %d population), construction stages."):format(houses,roads,pop))
