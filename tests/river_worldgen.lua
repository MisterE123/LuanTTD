local root="mods/bayline/openttd/"
local function m(name)return dofile(root..name..".lua")end
local Slope=m("slope")
local R=m("river_worldgen")(Slope)
local TG=m("terragenesis")(Slope)
local function board(w,h,field)
  local s={}
  local B={width=w,height=h,freeform=true}
  function B.tile(i)
    local x,z=i%w,math.floor(i/w)
    local g=s[i] or field(i,x,z)
    if x==0 or z==0 or x==w-1 or z==h-1 then return {kind="void",base=0,top=0,slope=0,corner_height=0} end
    return g
  end
  function B.set(i,t)s[i]=t end
  return B
end
local function square(h) return {kind="clear",slope=0,base=h,top=h,corner_height=h} end
local function id(x,z,w)return x+z*(w or 64)end
local B=board(64,64,function()return square(3)end)
local c=id(20,20)
assert(not R.find_spring(B,c))
for q,z in ipairs({-1,0,1}) do for _,x in ipairs({-1,0,1}) do
  if x~=0 or z~=0 then
    B.set(c+id(x,z),{kind="clear",slope=3,base=3,top=4,corner_height=3})
  end
end end
assert(R.find_spring(B,c))
B.set(id(34,35),square(6))
assert(not R.find_spring(B,c))
B.set(id(34,35),square(5))
assert(R.find_spring(B,c))
assert(R.flows_down(B,c,c+1))
assert(R.flows_down(B,c+1,c))
assert(not R.flows_down(B,c-1,c-65)) -- slope only continues if lower
B.set(c+1,{kind="clear",slope=3,base=2,top=3,corner_height=2})
assert(R.flows_down(B,c-1,c))
assert(not R.flows_down(B,c+1,c))
B.set(c+1,{kind="clear",slope=2,base=2,top=3,corner_height=2})
assert(not R.flows_down(B,c,c+1))

-- Low flat outlet is found in actual source directional order.
B=board(64,64,function()return square(4)end)
for _,i in ipairs({c-1,c+64,c+1,c-64}) do B.set(i,square(3)) end
local out,count=R.outlet(B,c)
assert(out==c-1 and count==4)
B=board(64,64,function()return square(4)end)
local draws,writes=0,{}
local function zero()draws=draws+1;return 0 end
local function make(i)
  writes[#writes+1]=i;local t=square(4);t.kind,t.class="water","river";B.set(i,t)
end
local dry,reach,visited=R.outlet(B,id(33,33))
assert(dry==nil and reach==62^2-1)
local lake,span=R.lake(B,c,id(33,33),2,reach,visited,zero,make)
assert(lake==id(1,1) and span==3 and draws==2 and writes[1]==lake)
assert(#writes>=6 and B.tile(id(2,2)).kind=="water")

-- Exact widening command branch: flatten three-corners-raised tile
-- only after finding a level neighboring river, not alongside a ramp.
B=board(64,64,function()return square(4)end)
local dry_patch={kind="clear",slope=14,base=3,top=4,corner_height=4}
B.set(c,dry_patch)
local wet=square(4);wet.kind,wet.class="water","river";B.set(c-1,wet)
B.terraform=function(tile,mask,raise)
  assert(tile==c and mask==1 and raise)
  B.set(c,square(4))
end
R.widen(B,c,c-1,make)
assert(B.tile(c).class=="river")
B.set(c,dry_patch)
B.set(c+1,{kind="water",class="river",base=3,top=4,slope=6,corner_height=3})
B.terraform=function()error("Do not modify an existing parallel river ramp")end
local function forbidden_widen()error("Do not widen an existing parallel river ramp")end
R.widen(B,c,c-1,forbidden_widen)
assert(B.tile(c).slope==14)

-- Equal-cost queue verifies no lexicographic or FIFO shortcut. The
-- upstream differential independently checks entire popped path + draws.
B=board(64,64,function()return square(2)end)
local rng=TG.startup_rng(1751)
local function random()return TG.next_random(rng) end
local path,trace=R.route(B,c,id(25,24),random,1)
assert(#path==10 and trace.draws>9 and path[1]==id(25,24) and path[#path]==c)
for i=2,#path do assert(R.flows_down(B,path[i],path[i-1])) end

-- Source fallback does not suppose a failed coastline implies no attempt
-- quota; at this size amount 3 schedules both hard and soft wells.
B=board(64,64,function()return square(0)end)
local runs,reflow,prog=0,0,0
B.make_river=function()error("No springs on a flat board")end
B.reflood=function()reflow=reflow+1 end
B.run_tile_loop=function(i)assert(i==runs);runs=runs+1 end
draws=0
local none=R.create(B,zero,{amount_of_rivers=3,progress=function(i,n)
  assert(i==prog and n==6);prog=prog+1
end})
assert(none.wells==2 and none.long_wells==1 and none.short_wells==1)
assert(none.rivers==0 and none.attempts==640 and draws==640 and runs==256 and reflow==1 and prog==7)
assert(R.create({},function()error("Disabled stage must not use RNG")end,{amount_of_rivers=0}).wells==0)
local opts={width=64,depth=64,seed=1751,freeform_edges=true,
  terrain_type=1,quantity_sea_lakes=0,rng_state=TG.startup_rng(1751)}
local base=TG.generate(opts)
assert(R.generate(base,TG.next_random,{amount_of_rivers=0})==base)
local detached, stats=R.generate(base,TG.next_random,{amount_of_rivers=2,min_river_length=16,
  original=true})
assert(detached~=base and detached.rng_after~=base.rng_after and stats.wells==1)
assert(detached.corner(2,7)==base.corner(2,7))
local visited,maxcount={},0
local f=R.loop_scheduler({width=64,height=64},function(i)
  visited[i]=(visited[i] or 0)+1
  if i~=0 then assert(visited[i]==1);maxcount=maxcount+1 end
end)
local cursor
for _=1,256 do cursor=f() end
assert(visited[0]==256 and maxcount==3840 and cursor==2899,cursor)
assert(detached.river_tileloop_cursor==cursor)
assert(not pcall(R.generate,base,TG.next_random,{}))

-- Actual executable boundary: clear the ordinary wet classes incident
-- to the corner; preserve unrelated water and grass; reject atomically.
local function terrain_board(freeform,h)
  local heights,words,changes={},{},{}
  local Q={width=64,height=64,freeform=freeform}
  function Q.corner(x,z)return heights[id(x,z)] or h end
  function Q.tile(i)
    local x,z=i%64,math.floor(i/64)
    if x==63 or z==63 or freeform and (x==0 or z==0) then local t=square(h);t.kind="void";return t end
    local t=square(h)
    t.kind,t.class=words[i] and "water" or "clear",words[i]
    return t
  end
  function Q.set(i,word)words[i]=word end
  local setter={
    word=function(i,v)assert(v==0);words[i]=nil;changes[#changes+1]="word:"..i end,
    corner=function(x,z,v)heights[id(x,z)]=v;changes[#changes+1]="corner:"..id(x,z) end,
  }
  return Q,setter,changes
end
local Terrain=m("terrain")
local Q,setter,writes=terrain_board(true,1)
for k,class in pairs({[c]="river",[c-1]="sea",[c-64]="coast",[c+1]="river"})do Q.set(k,class) end
local synth=R.terraform_boundary(Q,setter,Terrain,15)
local ok,changed,cleared=synth(c,8,true)
assert(ok and changed==1 and cleared==3 and Q.corner(20,20)==2)
assert(table.concat(writes,",")=="word:"..(c-64)..",word:"..(c-1)..",word:"..c..",corner:"..c)
assert(Q.tile(c+1).class=="river")
ok,changed,cleared=synth(c,0,true)
assert(ok and changed==0 and cleared==0)
local at_edge=id(62,62)
ok,changed,cleared=synth(at_edge,2,true)
assert(ok and changed==1 and cleared==0 and Q.corner(63,63)==2)
Q,setter,writes=terrain_board(false,15)
Q.set(c,"river")
synth=R.terraform_boundary(Q,setter,Terrain,15)
assert(not synth(c,8,true) and #writes==0 and Q.tile(c).class=="river")
assert(not synth(id(1,1),8,false) and #writes==0)
local wide=R.generate(base,TG.next_random,{amount_of_rivers=2,min_river_length=16,original=false,terrain=Terrain})
assert(wide and wide.base_id:find("-tg-cap",1,true))
print("RIVER_WORLDGEN_PASS: spring limits, diagonal FIFO outlets, ordered-set lakes, exact heap branch, widening guards, stock terrain clears and bounded draw schedule.")
