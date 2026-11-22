local root="mods/luanttd_core/openttd/"
local function m(n)return dofile(root..n..".lua")end
local P,Rate,Inc=m("passengers"),m("station_rating"),m("income")
local C=m("coal_industry")(P,Rate,m("station_catchment")(P,Rate),Inc)
local Gen=m("industry_worldgen")(C)
local flat={kind="clear",slope=0,base=1}
local function k(x,z)return x+64*z end
local map={}
local board={width=64,height=64,freeform=true,tile=function(x,z)return map[k(x,z)] or flat end,
  towns={{id=4,x=25,z=14},{id=1,x=15,z=14},{id=3,x=49,z=49}},industries={}}
local function count(changes)
  local n=0;for _ in pairs(changes) do n=n+1 end;return n
end
assert(Gen.count(board,{density=4})==4 and Gen.count(board,{density=2})==1)
assert(Gen.count(board,{density=0,editor=true})==1 and Gen.count(board,{density=6,custom_count=18})==18)
local a,b=Gen.probability(board,0,{});assert(a==8 and b)
a,b=Gen.probability(board,1,{});assert(a==5 and b)
a,b=Gen.probability(board,1,{editor=true});assert(a==5 and not b)
assert(Gen.probability(board,0,{density=0})==0 and Gen.probability(board,11,{})==0)
assert(Gen.scale_coast(16*4,64,64)==16)

local mine=assert(Gen.quote(board,0,20,14,0,{}))
assert(mine.level==1 and #mine.cells==6 and mine.town==1 and mine.platform.width==6)
assert(mine.cells[1].x==21 and mine.cells[1].z==15 and mine.cells[1].gfx==0)
local function reject(code,id,x,z,variant,opts,others)
  local p,why=Gen.quote(board,id,x,z,variant,opts,others)
  assert(not p and why==code, tostring(why).." expected "..code)
end
reject("INDUSTRY_TYPE_UNPORTED",2,20,14,0,{})
reject("INDUSTRY_LAYOUT_UNPORTED",0,20,14,1,{})
reject("FOOTPRINT_OFF_MAP",0,62,26,0,{})
reject("PLATFORM_TOO_CLOSE_TO_EDGE",0,2,20,0,{})
assert(Gen.quote(board,0,2,20,0,{terragenesis=false}))
reject("INDUSTRY_TOO_CLOSE",1,34,28,0,{}, {mine})
assert(Gen.quote(board,1,35,29,0,{}, {mine}))
reject("ONLY_ONE_ALLOWED_PER_TOWN",0,19,15,0,{}, {mine})
assert(Gen.quote(board,0,19,15,0,{multiple_per_town=true}, {mine}))
map[k(20,15)]={kind="house",base=1,slope=0} -- true mined-layout hole, never filled
assert(Gen.quote(board,0,20,14,0,{}))
map[k(21,15)]={kind="house",base=1,slope=0}
reject("FOOTPRINT_OCCUPIED",0,20,14,0,{})
map[k(21,15)]={kind="trees",slope=0,base=1}
assert(Gen.quote(board,0,20,14,0,{}))
map[k(20,15)]=nil
map[k(21,15)]={kind="clear",slope=0,base=2}
reject("PLATFORM_TERRAFORM_UNPORTED",0,20,14,0,{})
local queries=0
board.terraform_quote=function(x,z,up)
  assert(x==21 and z==15 and not up);queries=queries+1;return true
end
local surface=assert(Gen.platform(board,20,14,C.mine_layouts[0]))
assert(#surface.changes==1 and queries==1 and map[k(21,15)].base==2)
reject("PLATFORM_TERRAFORM_UNPORTED",0,20,14,0,{}) -- no speculative live changes
board.terraform_quote=nil;map[k(21,15)]=nil

local function source(values)
  local at=0
  return function()
    at=at+1;assert(values[at]~=nil,"Unexpected RNG draw "..at);return values[at]
  end,function()return at end
end
local r,n=source({
  k(15,18),61,0x10123,0xc0000000,     -- unrenderable stock coal layout3: consume exact four draws
  k(16,20),66,0x20456,0,              -- coal layout0 bounded/accepted
    0x10374,1,2,3,4,5,6,               -- colour 4, counter 55, 6 tile seed bytes
  k(30,34),71,0x20101,0,              -- close to coal in Chebyshev metric
  k(47,40),72,0x20345,0,              -- far enough
    0x10786,11,12,13,14,15,16,17,18,   -- actual eight power station cells
  4294967295,                         -- weighted additional type1, not linear modulo
  k(17,42),81,0x101,0,0x4391,21,22,23,24,25,26,27,28,
})
local written={}
local result=Gen.generate(board,{density=6,custom_count=3,random=r,multiple_per_town=true,
  commit=function(p)written[#written+1]=p;return true end})
assert(result.target==3 and result.forced==2 and result.attempted==5 and result.shortfall==0 and n()==46)
assert(written[1].type==0 and written[1].x==16 and written[1].seed==66 and written[1].initial_random==0x456)
assert(written[1].counter==55 and written[1].random_colour==4 and written[1].selected_layout==1)
assert(written[2].type==1 and written[2].cells[8].random_bits==18 and written[3].type==1)
assert(result.failures.INDUSTRY_LAYOUT_UNPORTED==1 and result.failures.INDUSTRY_TOO_CLOSE==1)
local reached=Gen.record(written[1],0,{year=1950})
assert(reached.produced.rate==15 and reached.produced.last.production==120 and reached.counter==55)
assert(reached.town==1 and reached.random==0x456 and reached.tiles[1].random_bits==1)
assert(reached.tiles[1].stage==2 and reached.tiles[1].construction_counter==3 and not reached.tiles[1].completed)
C.tile_loop(reached,reached.tiles[1],{},function()error("Construction visit cannot supply cargo")end)
assert(reached.tiles[1].stage==3 and reached.tiles[1].completed)
assert(Gen.record(written[2],1,{after_first_visit=true}).tiles[8].completed)

local smooth_mine=assert(Gen.quote(board,0,24,24,0,{}))
local smooth={}
for j=1,16 do smooth[j]=j==1 and 4294967295 or 0 end
for j=17,23 do smooth[j]=j end
r,n=source(smooth)
Gen.initialize(smooth_mine,0,0,r,{original=false})
assert(n()==23 and Gen.record(smooth_mine,2,{original=false}).produced.rate==22)

local missed,R=0,0
local fail=Gen.generate(board,{enabled={[1]=true},density=6,custom_count=2,
  random=function()R=R+1;return 0 end,commit=function()error("Do not fabricate a fallback.")end,
  progress=function(a,b)assert(a<=b);missed=missed+1 end})
assert(fail.attempted==12000 and fail.shortfall==2 and fail.wanted_inds==0 and missed==3)
assert(R==48001 and fail.failures.FOOTPRINT_OFF_MAP==12000)
local zero=Gen.generate(board,{density=0,random=function()error("No RNG when funding only")end,
  commit=function()error("No native auto industry when funding only")end,
  reset=function()error("Original branch never resets")end})
assert(zero.target==0 and zero.shortfall==0 and count(zero.placed)==0)
print("INDUSTRY_WORLDGEN_PASS: source weights, accounting, no-wrap layouts, conflicts, nondestructive platforms, true lifecycle stages and exact failure budget.")
