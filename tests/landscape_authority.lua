local p="mods/luanttd_core/"
local function m(n) return dofile(p..n..".lua") end
local A,H,IX=m("openttd/landscape_authority"),m("openttd/town_passengers"),m("openttd/landscape_index")
local Dyn=m("openttd/landscape_dynamic")(IX)
local Sim,T,F=m("sim"),m("openttd/terrain"),m("openttd/water_flood")
local L=m("openttd/landscaping")(T)

local function eq(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local function hex(list) return table.concat(list,",") end
local function cp(t)
  if type(t)~="table" then return t end
  local o={}
  for k,v in pairs(t) do o[k]=cp(v) end
  return o
end
local function tx(o,world,list)
  return {schema=A.SCHEMA,world=world,revision=o.revision(),changes=list}
end
local function new_fake()
  local active,log={},{}
  return {
    contains=function(k) return active[k]==true end,
    count=function() local n=0;for _ in pairs(active) do n=n+1 end;return n end,
    set=function(k,b)
      active[k]=b or nil
      log[#log+1]={k,b}
    end,
  },log
end
local function fail(t,reason,mode)
  eq(t[1],nil);eq(t[2],reason);eq(t[3],mode)
end

-- Edge clipping and rectangle conversion: authored host stride 48,
-- stock stride 64; no aliases into adjacent rows or inert padding.
do
  local cfg={world="rect",revision=13,log_x=6,log_z=7,width=48,depth=36}
  local sched,log=new_fake()
  local seen,physical={},false
  local O=A.new(cfg,sched,function(k,x,z,host)
    eq(host,(z-1)*48+x);eq(k,(z-1)*64+x-1)
    seen[#seen+1]=k
    return physical and x==48 and z==36
  end)
  local entries={{kind="corner",x=49,z=37},{kind="layer",x=48,z=36,layer="rail_bridge_above"},
    {kind="tile",host=48*36},{kind="field",x=1,z=2},{kind="tile",x=48,z=36}}
  local plan=assert(O.preflight(tx(O,"rect",entries),"boundary"))
  local a=O.affected(plan)
  eq(hex(a),"64,2222,2223,2286,2287")
  a[1]=77;entries[1].x=1 -- returned records and staged inputs cannot alter token
  local observed={{kind="field",host=49},{kind="tile",host=48*36},
    {kind="layer",host=48*36,layer="rail_bridge_above"}}
  local ok,changed=O.run(plan,"boundary",function() physical=true;return observed end)
  assert(ok);eq(changed,1);eq(O.revision(),14);eq(hex(seen),"64,2222,2223,2286,2287,64,2222,2223,2286,2287,64,2222,2223,2286,2287")
  eq(#log,1);eq(log[1][1],2287);eq(log[1][2],true)

  local function check(list,reason,phase)
    fail({O.preflight(tx(O,"rect",list),phase or "boundary")},reason,phase=="slot" and "abort" or "dense")
  end
  check({},"MISSING_CHANGES")
  check({[2]={kind="tile",host=1}},"INVALID_CHANGE_RECORD")
  check(setmetatable({},{__index={}}),"MISSING_CHANGES")
  check({{kind="field",host=1,x=1,z=1}},"INVALID_TILE")
  check({{kind="tile",host=1729}},"INVALID_TILE")
  check({{kind="tile",x=49,z=36}},"INVALID_TILE")
  check({{kind="corner",x=50,z=36}},"INVALID_CORNER")
  check({{kind="corner",x=1,z=1,host=1}},"INVALID_CORNER")
  check({{kind="layer",host=1,layer="unknown"}},"INVALID_LAYER")
  check({{kind="house",host=1}},"UNSUPPORTED_CHANGE_KIND","slot")
  check({[A.MAX_ENTRIES+1]={kind="tile",host=1}},"INVALID_CHANGE_ARRAY")
  fail({O.preflight(tx(O,"other",observed),"boundary")},"WRONG_WORLD","abort")
  fail({O.preflight(nil,"boundary")},"INVALID_TRANSACTION","dense")
  fail({O.preflight(tx(O,"rect",observed),"unknown")},"INVALID_PHASE","abort")
  local future=tx(O,"rect",{{kind="field",host=1}})
  local mismatch=assert(O.preflight(future,"boundary"))
  fail({O.run(mismatch,"slot",function() error("wrong-phase writer called") end)},"PHASE_CHANGED","abort")
  local old=assert(O.preflight(future,"boundary"))
  local later=assert(O.preflight(future,"boundary"))
  assert(O.run(later,"boundary",function() return future.changes end))
  fail({O.run(old,"boundary",function() error("stale writer called") end)},"STALE_REVISION","dense")
  fail({O.preflight(future,"boundary")},"STALE_REVISION","dense")
  eq(O.revision(),15)
  O.abandon()
  fail({O.preflight(future,"boundary")},"OWNER_NOT_READY","dense")
end
do
  local function setup(lim)
    local s=new_fake()
    local O=A.new({world="limit",log_x=12,log_z=12,width=4096,depth=4096,active_limit=lim},s,
      function() return false end)
    return O,s
  end
  local O=setup(3)
  local at={{kind="tile",x=2048,z=2048}}
  fail({O.preflight(tx(O,"limit",at),"boundary")},"UNRESERVED_ACTIVE_CAPACITY","dense")
  fail({O.preflight(tx(O,"limit",at),"slot")},"UNRESERVED_ACTIVE_CAPACITY","abort")
  local calls=0
  for _,phase in ipairs{"boundary","slot"} do
    local O2=setup(64)
    local plan=assert(O2.preflight(tx(O2,"limit",at),phase))
    fail({O2.run(plan,phase,function()
      calls=calls+1
      -- This can look identical to a visual dirty cell; it is not
      -- a matching protected-layer attestation.
      return {{kind="layer",x=2048,z=2048,layer="bridge_above"}}
    end)},"UNATTESTED_WRITES","abort")
    eq(O2.ready(),false);eq(O2.revision(),0)
  end
  eq(calls,2)
  local O3=setup(16)
  local corner={{kind="corner",x=4097,z=4097}}
  local p3=assert(O3.preflight(tx(O3,"limit",corner),"boundary"))
  eq(hex(O3.affected(p3)), "16773118,16773119,16777214,16777215")
  assert(O3.run(p3,"boundary",function() return {{kind="tile",host=16777216}} end))
  eq(O3.revision(),1)
  local O4,s4=setup(8)
  local unit={{kind="field",x=1,z=1}}
  local p4=assert(O4.preflight(tx(O4,"limit",unit),"boundary"))
  for k=1,8 do s4.set(k,true) end -- adversarial stale capacity
  fail({O4.run(p4,"boundary",function() error("unreserved writer called") end)},"UNRESERVED_ACTIVE_CAPACITY","dense")
end
do
  local s,log=new_fake()
  local available,writing,physical=true,false,false
  local O=A.new({world="missing",width=128,depth=128,log_x=7,log_z=7},s,
    function(k)
      if available then return physical end
      return nil
    end)
  local entries={{kind="tile",host=1}}
  local planned=assert(O.preflight(tx(O,"missing",entries),"boundary"))
  available=false
  fail({O.preflight(tx(O,"missing",entries),"boundary")},"MISSING_MEMBERSHIP_INPUT","dense")
  fail({O.preflight(tx(O,"missing",entries),"slot")},"MISSING_MEMBERSHIP_INPUT","abort")
  fail({O.run(planned,"boundary",function() writing=true;return entries end)},"MISSING_MEMBERSHIP_INPUT","dense")
  assert(not writing and O.ready());eq(#log,0);eq(O.revision(),0)
  available,physical=true,true
  fail({O.preflight(tx(O,"missing",entries),"boundary")},"STALE_MEMBERSHIP","dense")
  fail({O.preflight(tx(O,"missing",entries),"slot")},"STALE_MEMBERSHIP","abort")
  physical=false
  local p2=assert(O.preflight(tx(O,"missing",entries),"boundary"))
  fail({O.run(p2,"boundary",function() available=false;return entries end)},"UNPROVED_MEMBERSHIP","abort")
  eq(O.revision(),0);eq(O.ready(),false);eq(#log,0)
end

Sim.W,Sim.H=128,128
local World=m("water_flood_world")(Sim,T,F)
local function world(height)
  local s={tiles={},companies={},news={},topology=0,road_economy=true,road_stock_house_supply=true,stock_coastal_flood=true,
    corner_grid=T.new(Sim.W,Sim.H,height),changed={}}
  for z=1,Sim.H do for x=1,Sim.W do
    local _,h=T.tile(s.corner_grid,x,z)
    s.tiles[Sim.id(x,z)]={terrain=h>0 and "hill" or "grass",h=h,wood=true}
  end end
  return s
end
local function candidate(s,board,host)
  local t=s.tiles[host]
  if not t or t.terrain~="water" or (not t.coastal_water and (t.stock_canal or t.water_class=="river" or
      t.water_class=="canal" or t.build=="canal")) then return false end
  local x,z=Sim.xy(host)
  return #F.visit(board,x,z)>0
end
local function all_candidates(s,board)
  local set={}
  for id=1,#s.tiles do if candidate(s,board,id) then set[id-1]=true end end
  return set
end
local function same_set(a,b)
  for k in pairs(a) do assert(b[k],"missing "..k) end
  for k in pairs(b) do assert(a[k],"unexpected "..k) end
end
local function setup(s)
  local D=Dyn.new(7,7)
  local B=World.board(s)
  local touches={}
  local O=A.new({world="tested-128",log_x=7,log_z=7,width=128,depth=128},D,function(k,x,z,host)
    touches[#touches+1]=k
    return candidate(s,B,host)
  end)
  for k in pairs(all_candidates(s,B)) do D.set(k,true) end
  return O,D,B,touches
end
local function prove(s,B,D)
  local dense=all_candidates(s,B)
  local count=0
  for i in pairs(dense) do assert(D.contains(i),"missing membership "..i);count=count+1 end
  eq(D.count(),count)
end
local function tiles(ids)
  local a={}
  for i,id in ipairs(ids) do a[i]={kind="tile",host=id} end
  return a
end

-- Player-visible real landscaping callback. With this controlled
-- ground, the exact query is one stock corner change and four dirty
-- tiles. Its command emits these IDs instead of appending s.changed.
do
  local X,Z=41,31
  local s=world(function(x,z) return z==Z-1 and (x==X-1 or x==X) and 1 or 0 end)
  local target=Sim.id(X-1,Z-1)
  for z=Z-1,Z do for x=X-1,X do
    local id=Sim.id(x,z)
    s.tiles[id].wood=nil
    if id~=target then s.tiles[id].owner="AuthorityQA" end
  end end
  local wet=Sim.id(X-2,Z)
  s.tiles[wet]={terrain="water",water_class="sea",h=0}
  local O,D,B,touches=setup(s)
  local before=all_candidates(s,B)
  local layout=assert(L.corner(s.corner_grid,X,Z,true,{cash=100000,max_height=32}))
  eq(#layout.changes,1);eq(#layout.dirty,4);eq(T.corner(s.corner_grid,X,Z),0)
  eq(D.count(),0)
  local change=layout.changes[1]
  local plan=assert(O.preflight(tx(O,"tested-128",{{kind="corner",x=change.x,z=change.z}}),"boundary"))
  local expect=O.affected(plan)
  eq(#expect,16)
  local paid
  local ok,count=O.run(plan,"boundary",function()
    local success,msg,dirty=Sim.landscape(s,"AuthorityQA","raise",X,Z)
    assert(success,msg)
    eq(#dirty,4)
    paid=s.companies.AuthorityQA.expense
    return tiles(dirty)
  end)
  assert(ok);eq(count,1);eq(T.corner(s.corner_grid,X,Z),1);eq(paid,250)
  eq(#s.changed,0);eq(O.revision(),1);eq(hex(touches),hex(expect)..","..hex(expect)..","..hex(expect))
  assert(D.contains(wet-1))
  prove(s,B,D)
  local after=all_candidates(s,B)
  same_set(before,{})
  same_set(after,{[wet-1]=true})

  -- Real coastal predicate sees a protective topology layer EVEN when
  -- no tile record changes. Add the layer over the exposed flat target.
  local layer={{kind="layer",layer="aqueduct_above",host=target}}
  local barrier=assert(O.preflight(tx(O,"tested-128",layer),"boundary"))
  assert(O.run(barrier,"boundary",function()
    s.aqueduct_above={[target]=42}
    return layer
  end))
  eq(#s.changed,0);eq(O.revision(),2)
  assert(not D.contains(wet-1))
  prove(s,B,D)
  assert(O.run(assert(O.preflight(tx(O,"tested-128",layer),"boundary")),"boundary",function()
    s.aqueduct_above=nil
    return layer
  end))
  assert(D.contains(wet-1))
  prove(s,B,D)
  print("128² real paid landscape command returned 4 dirty tiles; 16 distinct invalidated tiles with no visual journal; aqueduct layer alone invalidates adjacent sea")
end

-- Actual source-order coastline; writer's reported list comes from the
-- typed source Flood.visit output (not the rendered s.changed append).
local index=IX.new(7,7)
local a,b,c
for i=1,8192 do
  local x,z=Sim.xy(i)
  if x>2 and x<126 and z>2 then
    for _,d in ipairs{{1,0},{0,1},{-1,0},{0,-1}} do
      local n=Sim.id(x+d[1],z+d[2])
      if (index.index(n-1)-index.index(i-1))%index.period<62 then
        a,b,c=i,n,Sim.id(x+2*d[1],z+2*d[2]);break
      end
    end
  end
  if a then break end
end
assert(a)
local s=world(function() return 0 end)
for _,id in ipairs{a,b,c} do s.tiles[id].wood=nil end
s.tiles[a]={terrain="water",h=0,water_class="sea"}
local dense=cp(s)
local O,D,B,touches=setup(s)
local cs,cd=H.new_clock(7,7,a-1,255),H.new_clock(7,7,a-1,255)
local count=D.advance(cs,1,function(k,tick,slot,x,z)
  local quote=F.visit(B,x+1,z+1)
  local changes={}
  for i,e in ipairs(quote) do changes[i]={kind="tile",x=e.x,z=e.z} end
  local plan=assert(O.preflight(tx(O,"tested-128",changes),"slot"))
  assert(O.run(plan,"slot",function()
    -- Re-read the same source result immediately at authoritative
    -- dispatch; no command or worker can intervene inside this owner.
    local reported=F.visit(B,x+1,z+1)
    eq(World.visit(s,x+1,z+1,B),#reported)
    local actual={}
    for i,e in ipairs(reported) do actual[i]={kind="tile",host=Sim.id(e.x,e.z)} end
    -- Deliberately erase visual dirtiness. It has no authority here.
    s.changed={}
    return actual
  end))
  eq(tick,256);assert(k~=0 and slot>0)
  prove(s,B,D)
end)
H.advance_houses(cd,1,function() end,{},function() error("no RNG here") end,function() end,nil,
  function(x,z) World.visit(dense,x+1,z+1) end)
eq(count,2);eq(#touches,54);eq(O.revision(),2);eq(s.topology,dense.topology)
eq(cs.head,cd.head);eq(cs.counter,cd.counter)
eq(s.tiles[b].terrain,"water");eq(s.tiles[c].terrain,"water")
eq(dense.tiles[b].terrain,"water");eq(dense.tiles[c].terrain,"water")
eq(#s.changed,0);eq(D.count(),0)
for host,t in ipairs(s.tiles) do
  local other=dense.tiles[host]
  for k,v in pairs(t) do eq(v,other[k]) end
  for k,v in pairs(other) do eq(v,t[k]) end
end
print("128² source tide transaction: two same-tick writes, two exact subsequent frontiers, no rendered journal; dense state/counter matched")
