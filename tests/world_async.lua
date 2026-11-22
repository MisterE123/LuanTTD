local path="mods/luanttd_core"
local function load(name) return dofile(path.."/"..name..".lua") end
local W,P,S,T=load("world_storage"),load("world_async_protocol"),load("openttd/slope"),load("openttd/terrain")
local Worker=load("world_async_worker")(P,S,T)
local Broker=load("world_async")
local function eq(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local function zero() return 0 end
local function hill(x,z)
  return math.max(0,9-math.abs(x-29)-math.abs(z-31),6-math.abs(x-13)-math.abs(z-21))
end
local base_opts={seed=1751,base_id="plain.world-test/1",corner=function(_,x,z)return hill(x,z) end,tile=zero}
local world=W.new(64,64,base_opts)
local grid=T.new(64,64,hill)
local s=assert(W.snapshot(world,18,18,44,44))
local compared=0
for z=24,38,2 do for x=24,38,2 do for mask=1,15 do for op=0,1 do
  local up=op==1
  local j=P.job(s,{kind="corner",x=x,z=z,mask=mask,up=up,max_height=12})
  local expected,err=T.plan(grid,x,z,mask,up,{max_height=12})
  local report,why,patch=P.result(s,j,1,Worker(s,j,1))
  if not expected then
    assert(not report and why==err)
  else
    assert(report,why)
    eq(report.cost,expected.cost)
    eq(#patch,#expected.changes)
    for n,entry in ipairs(patch) do
      local q=expected.changes[n]
      eq(entry.x,q.x);eq(entry.z,q.z);eq(entry.value,q.height)
    end
  end
  compared=compared+1
end end end end
local small=assert(W.snapshot(world,28,30,30,32))
local too_small=P.job(small,{kind="corner",x=29,z=31,mask=8,up=true})
local bad,why=P.result(small,too_small,2,Worker(small,too_small,2))
assert(not bad and why=="NEED_WIDER_REGION")
local top=assert(W.snapshot(world,1,1,7,7))
local edge=P.job(top,{kind="corner",x=2,z=2,mask=8,up=true,freeform_edges=false})
bad,why=P.result(top,edge,3,Worker(top,edge,3))
assert(not bad and why=="TOO_CLOSE_TO_EDGE")
local raster_job={kind="raster"}
local raster=assert(P.result(s,raster_job,4,Worker(s,raster_job,4)))
assert(not P.profile(raster,17,18) and not P.profile(raster,45,18))
for z=18,44 do for x=18,44 do
  local m,b,h=T.tile(grid,x,z)
  local u,v,w=P.profile(raster,x,z)
  eq(u,m);eq(v,b);eq(w,h)
end end

assert(not Broker.new({},path,W))
local slots={}
local reg=0
local fake={register_async_dofile=function(filename)
  reg=reg+1
  eq(filename,path.."/world_async_worker.lua")
end,handle_async=function(fn,cb,ss,j,id)
  assert(type(fn)=="function")
  assert(type(ss.corners)=="string" and type(ss.tiles)=="string")
  assert(#ss.corners+#ss.tiles<=5185)
  assert(not ss.ticket and not ss.handle and not j.authorize)
  slots[id]={s=ss,j=j,callback=cb}
  return true
end}
local Q=assert(Broker.new(fake,path,W,{inflight=1,proposals=1}))
assert(Broker.new(fake,path,W))
eq(reg,1)
local function release(id,modify)
  local slot=assert(slots[id]);slots[id]=nil
  local r=Worker(slot.s,slot.j,id)
  if modify then modify(r) end
  slot.callback(r)
end
local function reject(expect)
  return function(r,err) assert(r==nil);eq(err,expect) end
end
local function queue(job,cb)
  return assert(Q.submit(world,18,18,44,44,job,cb))
end
local function yes() return true end
assert(not Q.submit(world,18,18,62,44,raster_job,yes))
local id=queue(raster_job,reject("invalid worker reply context"))
assert(not Q.submit(world,18,18,44,44,raster_job,yes))
release(id,function(r) r.base_id="foreign" end)
id=queue(raster_job,reject("invalid worker raster size"))
release(id,function(r) r.profiles=r.profiles.."x" end)
id=queue(raster_job,reject("invalid worker raster record"))
release(id,function(r) r.profiles=string.char(15,0,0)..r.profiles:sub(4) end)
id=queue(raster_job,function() error("cancelled callback delivered") end)
assert(Q.cancel(id) and not Q.cancel(id))
eq(Q.stats().inflight,1)
release(id)
eq(Q.stats().inflight,0)

local job={kind="corner",x=29,z=31,mask=8,up=true,max_height=12}
id=queue(job,reject("invalid worker patch format"))
release(id,function(r) r.patch=P.encode(18,18,1) end)
id=queue(job,reject("invalid worker patch format"))
release(id,function(r) r.patch=P.encode(29,31,10)..P.encode(29,31,10);r.cost=2 end)
local function quote()
  local result
  local n=queue(job,function(r,err) result=assert(r,err) end)
  release(n)
  return result
end
local candidate=quote()
assert(not Q.apply(world,candidate,nil))
eq(Q.stats().proposals,1)
id=queue(job,reject("owner terrain proposal queue full"))
release(id)
assert(not Q.apply(W.new(64,64,base_opts),candidate,yes))
local rev,msg=Q.apply(world,candidate,function(_,record)
  eq(record.revision,0)
  return false,"Protected yard"
end)
assert(not rev and msg=="Protected yard" and W.stats(world).revision==0)
assert(not Q.apply(world,candidate,yes))
candidate=quote()
assert(W.commit(world,0,{{kind="tile",x=29,z=31,value=4}})==1)
rev,msg=Q.apply(world,candidate,yes)
assert(not rev and msg=="stale world revision" and W.get_corner(world,29,31)==9)
candidate=quote()
rev,msg=Q.apply(world,candidate,function()
  assert(W.commit(world,1,{{kind="tile",x=29,z=31,value=2}})==2)
  return true
end)
assert(not rev and msg=="stale world revision" and W.get_corner(world,29,31)==9)
assert(Q.apply(world,quote(),yes)==3 and W.get_corner(world,29,31)==10)
assert(not Q.apply(world,{kind="corner",cost=1},yes))
print(("PASS %d stock-plan comparisons and owner bounds, malformed output, back-pressure, authorization, replay and revision tests")
  :format(compared))
