-- Compare detached mutable owner with real H.advance_houses stock walk.
local p="mods/luanttd_core/"
local function m(n) return dofile(p..n..".lua") end
local H,I=m("openttd/town_passengers"),m("openttd/landscape_index")
local D=m("openttd/landscape_dynamic")(I)
local F,T=m("openttd/water_flood"),m("openttd/terrain")
local function eq(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local function cp(t)
  if type(t)~="table" then return t end
  local out={}
  for k,v in pairs(t) do out[k]=cp(v) end
  return out
end
local function same(a,b,k)
  k=k or "root"
  assert(type(a)==type(b),k)
  if type(a)~="table" then assert(a==b,k..": "..tostring(a).." != "..tostring(b));return end
  for i,v in pairs(a) do same(v,b[i],k.."."..i) end
  for i in pairs(b) do assert(a[i]~=nil,k.." missing "..i) end
end

-- Exercise priority queue exactness, including remove arbitrary middle
-- entry, reinsertion of the current slot, tile 0, same tick pre/post,
-- empty ticks, previous-rank hints, and restored noncanonical heads.
do
  local total=0
  for _,case in ipairs{{6,6,105,1,279},{7,7,252,6090,767},{6,8,512,16383,527},{8,6,255,6923,259},
      {7,8,249,3305,387},{8,7,1,555,382},{7,7,9007199254740722,6090,269}} do
    local a,b,c,h,n=unpack(case)
    local clock=H.new_clock(a,b,h,c)
    local S=H.new_clock(a,b,h,c)
    local state,baseline={},{}
    local dyn=D.new(a,b)
    local area=2^(a+b)
    local function action(set,base,tile,tick,tag)
      -- A deterministic selection made by the owner independently on
      -- both walks, deliberately perturbing pending heap entries.
      local u=(tile*31+(tick%997)*129+tag*397)%area
      local v=dyn.index.step(u==0 and 1 or u)
      set(u,true);set(v,false)
      if base and tag==1 then set(tile,false);set(tile,true) end
      if tick%11==0 then set(0,tick%22==0) end
    end
    local function add(tile,on) state[tile]=on or nil end
    for j=0,511 do local id=j*793%area;add(id,true);dyn.set(id,true) end
    local function stat()
      local n=0
      for k in pairs(state) do n=n+1;eq(dyn.contains(k),true) end
      eq(n,dyn.count())
    end
    local refcount=0
    local function ref(before)
      local slot=-1
      H.advance(S,1,function(id,tick)
        slot=slot+1
        if state[id] then
          baseline[#baseline+1]={id,tick,slot,S.head,S.counter}
          action(add,true,id,tick,1);refcount=refcount+1
        end
      end,before)
    end
    for i=1,n do
      ref(function(tick) action(add,false,3,tick,2) end)
      action(add,false,7,S.counter,3)
    end
    local visited=0
    for _,n2 in ipairs{19,n-19} do
      local calls=dyn.advance(clock,n2,function(id,tick,slot)
        visited=visited+1
        same({id,tick,slot,clock.head,clock.counter},baseline[visited])
        action(dyn.set,true,id,tick,1)
      end,function(tick) action(dyn.set,false,3,tick,2) end,
      function(tick) action(dyn.set,false,7,tick,3) end)
      assert(calls>0)
    end
    eq(visited,refcount);same(clock,S);stat();total=total+visited
  end
  -- Batch clock snapshots versus interactive phase above.
  local d=D.new(7,7)
  local c=H.new_clock(7,7,1,255)
  d.set(0,true)
  local n=d.advance(c,300,function(id,tick,slot)
    eq(c.counter,255);eq(id,0);eq(slot,0)
    if tick==256 then d.set(0,false);d.set(0,true) end
  end)
  eq(n,2);eq(c.counter,555)
  print(("mutable owner vs dense 7 shape/resume fixtures: %d live events; tile 0 and same-slot reinsertion exact"):format(total))
end

-- One real 128×128 source-order coast fixture, using the exact source
-- flood kernel and current conservative W.visit, not a mock event list.
-- Find a chain A→B→C where the carried head puts A and B in the same
-- tick in source order. A and C must not be direct flood neighbors.
local size=128
local Sim={W=size,H=size}
function Sim.id(x,z) if x>=1 and z>=1 and x<=size and z<=size then return (z-1)*size+x end end
function Sim.xy(id) return (id-1)%size+1,math.floor((id-1)/size)+1 end
local W=m("water_flood_world")(Sim,T,F)
local IX=I.new(7,7)
local A,B,C,rank_distance
for i=1,8192 do
  local ax,az=Sim.xy(i)
  if ax>2 and ax<size-2 and az>2 then
    for _,pair in ipairs{{1,0},{0,1},{-1,0},{0,-1}} do
      local bx,bz=ax+pair[1],az+pair[2]
      local b=Sim.id(bx,bz)
      local delta=(IX.index(b-1)-IX.index(i-1))%IX.period
      if delta<62 then
        A,B,C,rank_distance=i,b,Sim.id(bx+pair[1],bz+pair[2]),delta
        break
      end
    end
  end
  if A then break end
end
assert(A and B and C)
local function physical()
  local s={corner_grid=T.new(size,size,function() return 0 end),tiles={},topology=0,changed={}}
  for i=1,size*size do s.tiles[i]={h=0,terrain="grass",wood=true} end
  for _,i in ipairs{A,B,C} do s.tiles[i].wood=nil end
  s.tiles[A].terrain,s.tiles[A].water_class="water","sea"
  return s
end
local function quote(w,s,id)
  local t=s.tiles[id]
  if not t or t.terrain~="water" or t.water_class=="river" or t.water_class=="canal" then return false end
  local x,z=Sim.xy(id)
  return #F.visit(w,x,z)>0
end
local function coast(s,sparse,head,n,start,replace)
  local times,called={},0
  local board=W.board(s)
  local clock=H.new_clock(7,7,head,start)
  local d=sparse and D.new(7,7)
  local function assign(id)
    d.set(id-1,quote(board,s,id))
  end
  if d then for id in ipairs(s.tiles) do if quote(board,s,id) then d.set(id-1,true) end end end
  local function near(id)
    local x,z=Sim.xy(id)
    for dz=-1,1 do for dx=-1,1 do
      local other=Sim.id(x+dx,z+dz)
      if other then assign(other) end
    end end
  end
  local function visit(id,tick,_,x,z)
    local count=#s.changed
    local out=W.visit(s,x+1,z+1,board)
    called=called+1
    if out>0 then
      for k=count+1,#s.changed do
        local changed=s.changed[k]
        times[#times+1]={changed,tick,id+1}
        if d and not replace then near(changed) end
      end
    end
  end
  local function before() if d and replace then for _,i in ipairs{A,B,C} do assign(i) end end end
  if d then d.advance(clock,n,visit,before)
  else H.advance_houses(clock,n,function() end,{},function() error("RNG on plain coast") end, function() end,nil,
    function(x,z,tick) visit(z*size+x,tick,nil,x,z) end) end
  return times,called,clock
end
local ground=physical()
local ref,full,cl=coast(cp(ground),false,A-1,259,255)
local sparse,sparse_n,cl2=coast(cp(ground),true,A-1,259,255)
same(sparse,ref);same(cl,cl2);eq(#sparse,2)
same(sparse[1],{B,256,A});same(sparse[2],{C,256,B})
local too_late=coast(cp(ground),true,A-1,259,255,true)
eq(too_late[2][2],512)
-- At opposite ordering (begin with dry B before visiting A), do not
-- retroactively visit a newly wet B. It has to wait for the next cycle.
local reverse_ref=coast(cp(ground),false,B-1,512,253)
local reverse=coast(cp(ground),true,B-1,512,253)
same(reverse,reverse_ref);assert(reverse[1][2]>253 and reverse[2][2]>reverse[1][2])
print(("128² real water flood: %d-slot separation, two effects in tick 256; tick-start-only scheduling delayed second effect until 512; %d physical scans vs %d useful calls"):format(rank_distance,full,sparse_n))

-- A real unsupported two-raised shore dries exactly on that tile's
-- slot; with no remaining effect, do not leave it in the next cycle.
local dry=physical()
for _,i in ipairs{A,B,C} do dry.tiles[i]={h=0,terrain="grass",wood=true} end
local ax,az=Sim.xy(A)
dry.corner_grid=T.new(size,size,function(x,z)
  return z==az and (x==ax or x==ax+1) and 1 or 0
end)
dry.tiles[A]={h=0,terrain="water",water_class="sea",coastal_water=true}
local dr,_,dc=coast(cp(dry),false,A-1,259,255)
local ds,n,sc=coast(cp(dry),true,A-1,259,255)
same(dr,ds);same(dc,sc);same(ds,{{A,256,A}});eq(n,1)
print("128² unsupported graded shore: equal stock slot dry-up, no repeat visit")
