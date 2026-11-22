local root="mods/bayline/"
local function m(n) return dofile(root..n..".lua") end
local Sim,T,H,F=m("sim"),m("openttd/terrain"),m("openttd/town_passengers"),m("openttd/water_flood")
local I=m("openttd/landscape_index")
local D=m("openttd/landscape_dynamic")(I)
local A=m("openttd/landscape_authority")
local Bridge=m("openttd/landscape_bridge_receipts")(Sim,A)
local W=m("water_flood_world")(Sim,T,F)
local K=m("openttd/road_bridge")(m("openttd/slope"))
local xwidth=128
Sim.W,Sim.H=xwidth,xwidth
local function eq(a,b,n) assert(a==b,(n or "")..": "..tostring(a).." != "..tostring(b)) end
local function cp(t,seen)
  if type(t)~="table" then return t end
  seen=seen or {}
  if seen[t] then return seen[t] end
  local out={};seen[t]=out
  for k,v in pairs(t) do out[k]=cp(v,seen) end
  return out
end
local function same(a,b,n,seen)
  n=n or ""
  eq(type(a),type(b),n)
  if type(a)~="table" then eq(a,b,n);return end
  seen=seen or {};if seen[a]==b then return end;seen[a]=b
  for k,v in pairs(a) do same(v,b[k],n.."/"..k,seen) end
  for k in pairs(b) do assert(a[k]~=nil,n.."/"..k) end
end

-- Pick the first physically adjacent water-to-land A→B where stock
-- carried head visits B later in the same tick after A (rank matters,
-- not row-major or native return order). Place a bridge perpendicular.
local IX=I.new(7,7)
local source,target,bank,begin_,end_,foreign,land,ds
for id=1,8192 do
  local x,z=Sim.xy(id)
  if x>6 and x<120 and z>6 then
    for _,d in ipairs{{1,0},{0,1},{-1,0},{0,-1}} do
      local u,v=x+d[1],z+d[2]
      local j=Sim.id(u,v)
      local delta=(IX.index(j-1)-IX.index(id-1))%IX.period
      if delta<62 then
        source,target,bank,ds=id,j,Sim.id(u+d[1],v+d[2]),delta
        local dx,dz=d[2]~=0 and 1 or 0,d[1]~=0 and 1 or 0
        begin_,end_=Sim.id(u-2*dx,v-2*dz),Sim.id(u+2*dx,v+2*dz)
        foreign,land=Sim.id(u-dx,v-dz),Sim.id(u+dx,v+dz)
        break
      end
    end
  end
  if source then break end
end
assert(source and target and begin_ and end_)
local name,other="Timber Co","Other Co"
local function world()
  local s={corner_grid=T.new(xwidth,xwidth),tiles={},companies={},sites={},fleet={},news={},day=0,
    topology=0,road_economy=true,road_stock_house_supply=true,stock_coastal_flood=true,changed={2,11,3,2}}
  for id=1,xwidth*xwidth do s.tiles[id]={h=0,terrain="grass",wood=true} end
  for _,id in ipairs{source,target,bank,begin_,end_,foreign,land} do s.tiles[id].wood=nil end
  s.tiles[source].terrain,s.tiles[source].water_class="water","sea"
  -- Ordinary foreign road is valid underneath a stock bridge; its own
  -- tile record never changes just because an overhead layer does.
  s.tiles[foreign].build,s.tiles[foreign].owner,s.tiles[foreign].road_bits="road",other,5
  s.tiles[land].owner=other -- an ordinary protected dry underlay retains ownership
  Sim.company(s,name);Sim.company(s,other)
  return s
end
local function bind(s)
  local D_=D.new(7,7)
  local B=W.board(s)
  local function candidate(k,x,z,id)
    if s.tiles[id].terrain~="water" then return false end
    return #F.visit(B,x,z)>0
  end
  local function verify(seed)
    local n=0
    for id in ipairs(s.tiles) do
      local x,z=Sim.xy(id)
      if candidate(id-1,x,z,id) then
        if seed then D_.set(id-1,true) else assert(D_.contains(id-1),id) end
        n=n+1
      end
    end
    eq(D_.count(),n)
  end
  verify(true)
  local owner=A.new({world="bridge-tide",width=xwidth,depth=xwidth,log_x=7,log_z=7},D_,candidate)
  return Bridge.bind(s,"bridge-tide",name,owner),owner,D_,B,verify
end

local s=world()
local control=cp(s)
local native,authority,index,B,verify=bind(s)
local original=cp(s)
local fee=5*2*95+math.floor(K.length_factor(5)*275*80/256)
local p=assert(native.quote("build",end_,begin_))
eq(p.price,fee);eq(p.deck,1);same(p.tiles,{begin_,foreign,target,land,end_})
same(p.changes,{{kind="tile",host=begin_},{kind="layer",layer="bridge_above",host=foreign},
  {kind="layer",layer="bridge_above",host=target},{kind="layer",layer="bridge_above",host=land},
  {kind="tile",host=end_}})
same(s,original)
assert(index.contains(source-1))
local function reject(adapter,action,a,b,want,mode)
  local prior=cp(s)
  local rev=authority.revision()
  local ok,why,room=adapter.run(action,a,b)
  eq(ok,nil);eq(why,want);eq(room,mode)
  eq(authority.revision(),rev);same(s,prior)
end
s.aqueduct_above={[target]=8}
reject(native,"build",begin_,end_,"PROTECTED_LAYER","unsupported")
s.aqueduct_above=nil
s.tiles[target].level_crossing={}
reject(native,"build",begin_,end_,"UNREVIEWED_TILE","unsupported")
s.tiles[target].level_crossing=nil
local cash=s.companies[name].cash
s.companies[name].cash=fee-1
reject(native,"build",begin_,end_,"NOT_ENOUGH_CASH","denied")
s.companies[name].cash=cash
s.tiles[begin_].owner=other
reject(native,"build",begin_,end_,"UNREVIEWED_HEAD","unsupported")
s.tiles[begin_].owner=nil
local flagged=Bridge.bind(s,"bridge-tide",name,authority,function() return true end)
reject(flagged,"build",begin_,end_,"UNREVIEWED_LAYER_OR_ACTOR","unsupported")
same(s,original)

local yes,put=assert(native.run("build",end_,begin_))
local result,msg,ids,deck=Sim.road_bridge(control,name,end_,begin_,0)
assert(result,msg);same(put.dirty,ids);eq(put.deck,deck);eq(put.price,fee)
same(put.changes,{{kind="tile",host=begin_},{kind="tile",host=end_},
  {kind="layer",layer="bridge_above",host=foreign},{kind="layer",layer="bridge_above",host=target},
  {kind="layer",layer="bridge_above",host=land}})
same(s,control);verify(false)
eq(authority.revision(),1);eq(put.membership_updates,1);eq(index.contains(source-1),false)
eq(table.concat(s.changed,","),"2,11,3,2")
same(s.tiles[foreign],original.tiles[foreign])

-- Refuse either stealing the bridgeheads or colliding with its
-- protected middle. The perpendicular line goes over a different
-- potential bridge deck but the host has only one overhead slot.
local thieves=Bridge.bind(s,"bridge-tide",other,authority)
reject(thieves,"remove",end_,nil,"SELECT_OWN_BRIDGE","denied")
local a,b=Sim.xy(source)
local u,v=Sim.xy(target)
local perpendicular_start=Sim.id(a-(u-a),b-(v-b))
local c,d=Sim.xy(bank)
local perpendicular_end=Sim.id(c+(u-a),d+(v-b))
local pr1,pr2=s.tiles[perpendicular_start],s.tiles[perpendicular_end]
pr1.wood,pr2.wood=nil,nil
reject(native,"build",perpendicular_start,perpendicular_end,"PROTECTED_OVERHEAD","unsupported")
local raw,reason=Sim.road_bridge(s,name,perpendicular_start,perpendicular_end,0,true)
assert(not raw and reason:match("MUST_DEMOLISH_BRIDGE_FIRST"))
pr1.wood,pr2.wood=true,true
local qok,qfee,foot=Sim.remove_wood_bridge(s,name,end_,true)
assert(qok);eq(qfee,0);eq(foot.middle[2],target)
foot.middle[2]=1 -- no live registry reference escapes the quote
eq(s.stock_road_bridges[put.bridge].middle[2],target)
s.fleet[71]={route={end_}}
local blocked=Sim.remove_wood_bridge(s,name,end_,true)
eq(blocked,false)
reject(native,"remove",end_,nil,"Wait for the current vehicle route to clear the bridge.","denied")
s.fleet[71]=nil
same(s,control)

local head=IX.jump(source-1,-IX.tiles_per_tick)
local slow,fast=H.new_clock(7,7,head,254),H.new_clock(7,7,head,254)
local function dense_step()
  H.advance_houses(slow,1,function() end,{},function() error("no RNG in flood fixture") end,function() end,nil,
    function(x,z) W.visit(control,x+1,z+1) end)
end
local run_events={}
local function sparse_step()
  index.advance(fast,1,function(id,tick,slot,x,z)
    local predicted=F.visit(B,x+1,z+1)
    local mutations={}
    for i,r in ipairs(predicted) do mutations[i]={kind="tile",x=r.x,z=r.z} end
    local token=assert(authority.preflight({schema=A.SCHEMA,world="bridge-tide",revision=authority.revision(),
      changes=mutations},"slot"))
    assert(authority.run(token,"slot",function()
      local start=#s.changed
      eq(W.visit(s,x+1,z+1,B),#predicted)
      local actual={}
      -- Capture the physical class delta by native typed flood geometry.
      -- Deliberately do not get its IDs from the visual s.changed buffer.
      for i,r in ipairs(predicted) do
        local id=Sim.id(r.x,r.z)
        local t=s.tiles[id]
        eq(t.terrain,r.kind=="clear" and "grass" or "water")
        actual[i]={kind="tile",host=id}
        run_events[#run_events+1]={tick,id,slot}
      end
      assert(#s.changed>=start)
      return actual
    end))
  end)
end
dense_step();sparse_step();same(slow,fast);same(s,control)
eq(fast.counter,255);eq(fast.head,source-1);eq(#run_events,0)
eq(s.tiles[target].terrain,"grass")

local removed,rec=assert(native.run("remove",end_))
local ok,rmsg,rdirty,rdeck=Sim.remove_wood_bridge(control,name,end_)
assert(ok,rmsg);same(rec.dirty,rdirty);eq(rec.deck,rdeck);eq(rec.price,0)
same(rec.changes,put.changes);same(s,control);verify(false)
eq(rec.membership_updates,1);eq(authority.revision(),2)
assert(index.contains(source-1))
assert(next(s.bridge_above)==nil and next(s.stock_road_bridges)==nil)
same(s.tiles[foreign],original.tiles[foreign]);same(s.corner_grid,original.corner_grid)
dense_step();sparse_step();same(slow,fast);same(s,control);verify(false)
same(run_events,{{256,target,1},{256,bank,ds+1}})
eq(authority.revision(),4)
print(("128² actual bridge: $%d build, $%d free native removal, heads %d/%d, bridge_above %d/%d/%d; foreign road preserved")
  :format(fee,rec.price,begin_,end_,foreign,target,land))
print(("dense/sparse tick differential: protection keeps %d dry at tick 255; removal admits %d then %d in tick 256 (slots 1/%d)")
  :format(target,target,bank,ds+1))

-- If an attempted native writer returns an incomplete dirty receipt,
-- the typed owner never claims success or falsely rolls back reality.
do
  local bad=world()
  local _,owner,scheduler=bind(bad)
  local Broken=setmetatable({},{__index=Sim})
  function Broken.road_bridge(g,n,a,b,style,quote)
    local ok,text,rows,deck=Sim.road_bridge(g,n,a,b,style,quote)
    if ok and not quote then rows[#rows]=nil end
    return ok,text,rows,deck
  end
  local badNative=m("openttd/landscape_bridge_receipts")(Broken,A).bind(bad,"bridge-tide",name,owner)
  local good,reason,mode=badNative.run("build",begin_,end_)
  eq(good,nil);eq(reason,"WRITER_FAILED");eq(mode,"abort");assert(not owner.ready())
  eq(owner.revision(),0);assert(scheduler.contains(source-1))
  assert(bad.bridge_above[target],"post-write uncertainty must not replay/roll back a completed native command")
end
print("ownership, budget, occupied route, overlayer and tampered-receipt gates passed")
