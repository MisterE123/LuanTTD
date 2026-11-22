local root="mods/bayline/"
local function load(p) return dofile(root..p..".lua") end
local Sim,Terrain,Track=load("sim"),load("openttd/terrain"),load("openttd/rail_track")
local C=load("openttd/level_crossing")(Track)
local W=load("level_crossing_world")(Sim,Terrain,C,Track)
local F=load("openttd/yapf_road_follow")
local Follow=load("openttd/rail_follow")(Track)
local function copy(t)
  if type(t)~="table" then return t end
  local n={}
  for k,v in pairs(t) do n[k]=copy(v) end
  return n
end
local s=Sim.new(1751)
local id=Sim.id
local owner="Level Co"
local c=Sim.company(s,owner)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function() return 0 end)
local function road(x,z,bits)
  s.tiles[id(x,z)]={build="road",owner=owner,road_bits=bits,terrain="grass",h=0}
  return id(x,z)
end
local function rail(x,z,bits)
  s.tiles[id(x,z)]={build="stock_rail",owner=owner,rail_tracks=bits,terrain="grass",h=0}
  return id(x,z)
end
local a,b,outer,exit=road(6,5,10),rail(7,5,2),road(5,5,10),road(8,5,10)
local approach,destination=rail(6,4,2),rail(6,6,2)
local approach_far,destination_far=rail(7,4,2),rail(7,6,2)
local rto,lto={kind="rail",track=1},{kind="road",pieces=10}
local actors,unknown,claims={},{},{}
local function rail_base(state)
  return {tile=function(i)
    if not i then return end
    local t=state.tiles[i]
    if t and t.rail_tracks then return {kind="rail",owner=t.owner,railtype=0,slope=0,trackbits=t.rail_tracks} end
  end,adjacent=function(i,d)return Sim.adjacent(i,4-d) end,stock_height=function()return 0 end}
end
local ctx={vehicles_at=function(i)
  if unknown[i] then return nil end
  local at={}
  for _,v in pairs(actors) do if v.tile==i then at[#at+1]=v end end
  return at
end,reserved=function(i) return not not claims[i] end,rail_board=rail_base(s)}
local function reject(propose,reason)
  local ok,why=propose()
  assert(not ok and why==reason,tostring(ok)..":"..tostring(why).." expected "..reason)
end
reject(function()return W.quote(s,owner,a,rto,ctx)end,"LEVEL_CROSSING_DISABLED")
s.level_crossing_enabled=true
reject(function()return W.quote(s,"Other",a,rto,ctx)end,"OWNED_BY_ANOTHER")
reject(function()return W.quote(s,owner,a,rto)end,"OCCUPANCY_UNKNOWN")
reject(function()return W.quote(s,owner,a,{kind="rail",track=0},ctx)end,"FALLBACK_CLEAR")
s.tiles[a].road_disallowed=1
reject(function()return W.quote(s,owner,a,rto,ctx)end,"CROSSING_ON_ONEWAY_ROAD")
s.tiles[a].road_disallowed=nil
s.tiles[a].wood=true
reject(function()return W.quote(s,owner,a,rto,ctx)end,"PROTECTED_TILE")
s.tiles[a].wood=nil
local initial=c.cash
local p=assert(W.quote(s,owner,a,rto,ctx))
assert(p.price==100 and c.cash==initial and not W.protected(s,a))
local saved=copy(p)
actors.bus={type="road",id="bus",tile=a}
reject(function()return W.commit(s,owner,p,ctx)end,"VEHICLE_IN_THE_WAY")
assert(c.cash==initial and not W.protected(s,a))
actors.bus.tile=outer
assert(W.commit(s,owner,p,ctx))
assert(c.cash==initial-100 and c.expense==100 and W.protected(s,a) and not W.protected(s,outer))
reject(function()return W.commit(s,owner,saved,ctx)end,"STALE_QUOTE")
claims[b]=true
local q=assert(W.quote(s,owner,b,lto,ctx))
assert(q.price==190 and q.crossing.reserved)
assert(W.commit(s,owner,q,ctx))
assert(c.cash==initial-290 and c.expense==290 and c.month_exp==290 and claims[b] and s.tiles[b].rail_tracks==nil)
assert(W.record(s,a).road_owner==owner and W.record(s,a).rail_owner==owner)
-- Both source boards see the same native ID, retain independent direction
-- masks, and can route through the infrastructure without modeling gates.
local rb=W.rail_board(s,rail_base(s),ctx)
assert(rb.tile(b).reserved and rb.tile(b).reserved_bits==2)
local roadboard=W.road_board(s,load("road_yapf_board")(Sim,s,F))
assert(roadboard.tile(a).kind=="crossing" and F.status(roadboard.tile(a),false)==257)
assert(F.status(roadboard.tile(b),false)==257 and roadboard.center_z(a)==0)
assert(F.status(roadboard.tile(outer),false)==257 and F.status(roadboard.tile(exit),false)==257)
for i,start in ipairs({outer,a,b}) do
  local next_=F.follow(roadboard,{owner=owner,compatible={[0]=true}},start,8)
  assert(next_.ok and next_.tile==({a,b,exit})[i])
end
local v={owner=owner,compatible={[0]=true}}
local src=Follow.follow(rb,v,approach,1)
assert(src.ok and src.tile==a)
local dst=Follow.follow(rb,v,a,1)
assert(dst.ok and dst.tile==destination)
assert(Track.status(rb.tile(b))==514)
claims[b]=nil
assert(not rb.tile(b).reserved and rb.tile(b).reserved_bits==0)
local phase,events=W.refresh(s,a,ctx)
assert(phase=="open" and #events==2 and not events[1].barred)
local function step(mode,key,from,to,td)
  local v=assert(actors[key]);assert(v.tile==from)
  local commit=function() v.tile=to;return true end
  if mode=="road" then return W.road_step(s,ctx,from,to,td,false,commit) end
  return W.train_step(s,ctx,from,to,td,owner,commit)
end
assert(step("road","bus",outer,a,8))
actors.bus_tail={type="road",id="bus_tail",tile=a}
actors.wait={type="road",id="wait",tile=outer}
actors.train={type="train",front=true,owner=owner,compatible={[0]=true},tile=approach,td=1}
actors.wagon={type="train",owner=owner,compatible={[0]=true},tile=approach,td=1}
assert(W.refresh(s,a,ctx)=="road_draining" and W.record(s,b).barred)
reject(function()return step("train","train",approach,a,1)end,"ROAD_DRAINING")
reject(function()return step("road","wait",outer,a,8)end,"CROSSING_BARRED")
assert(W.record(s,a).phase=="road_draining" and actors.train.tile==approach)

-- Save after admission, reload physical parts, and invalidate old visual
-- phase. A missing probe fails closed, but after authoritative restoration
-- the previously admitted road can always clear the contiguous group.
s=copy(s);actors=copy(actors);ctx.rail_board=rail_base(s)
s.level_crossing_tiles=nil
unknown[a]=true
assert(W.refresh(s,b,ctx)=="unobserved")
reject(function()return step("train","train",approach,a,1)end,"unobserved")
reject(function()return step("road","wait",outer,a,8)end,"unobserved")
unknown[a]=nil
assert(W.refresh(s,a,ctx)=="road_draining")
assert(step("road","bus",a,b,8))
assert(step("road","bus",b,exit,8))
reject(function()return step("train","train",approach,a,1)end,"ROAD_DRAINING")
assert(step("road","bus_tail",a,b,8))
assert(step("road","bus_tail",b,exit,8))
-- Reentrant road test occurs between the train's probe and physical commit;
-- no entrant can slip in even if it would otherwise observe a stale pose.
assert(W.train_step(s,ctx,approach,a,1,owner,function()
  reject(function()return step("road","wait",outer,a,8)end,"REENTRANT_STEP")
  actors.train.tile=a
  return true
end))
assert(W.record(s,a).phase=="rail_occupied")
assert(W.train_batch(s,ctx,{{from=a,to=a,td=1},{from=approach,to=a,td=1}},owner,function()
  actors.wagon.tile=a
  return true
end))
assert(step("train","train",a,destination,1))
claims[a]=nil
assert(W.refresh(s,b,ctx)=="rail_occupied")
reject(function()return step("road","wait",outer,a,8)end,"TRAIN_ON_CROSSING")
assert(step("train","wagon",a,destination,1))
assert(W.record(s,b).phase=="open" and not W.record(s,a).barred)
assert(step("road","wait",outer,a,8))

-- Reverse/orthogonal frame, crashed train and failed callback handling.
reject(function()return W.road_step(s,ctx,a,b,0,false,function()error("wrong entry")end)end,"WRONG_ROAD_TRACK")
reject(function()return W.train_step(s,ctx,approach_far,b,1,"Other",function()error("foreign train")end)end,"WRONG_RAIL_TRACK")
assert(step("road","wait",a,b,8) and step("road","wait",b,exit,8))
reject(function()return W.train_step(s,ctx,approach_far,b,1,owner,function()return false,"HOST_BLOCKED" end)end,"HOST_BLOCKED")
assert(W.record(s,b).phase=="open")
actors.crashed={type="train",tile=b,crashed=true}
assert(W.refresh(s,b,ctx)=="rail_occupied")
reject(function()return step("road","wait",exit,b,0)end,"TRAIN_ON_CROSSING")
actors.crashed=nil
assert(W.refresh(s,b,ctx)=="open")
assert(step("road","wait",exit,b,0))
assert(#W.refresh_all(s,ctx)==0 and s.level_crossing_tiles[a] and s.level_crossing_tiles[b])
-- Native dispatch adapter can report held head, wagon, and under-bridge
-- distinction without ever consulting fake route or screen interpolation.
s.stock_rail_dispatch={runs={{id=3,owner=owner,consist={parts={
  {tile=a,pose={td=1,x=86,y=70,direction=3},z=0},
  {tile=approach,pose={td=1,x=86,y=63,direction=3},hidden=true},
}}}}}
local h=W.dispatch_parts(s,a)
local w=W.dispatch_parts(s,approach)
assert(#h==1 and h[1].id==3 and h[1].front and h[1].compatible[0])
assert(#w==1 and w[1].part==2 and not w[1].front and w[1].hidden)
print("stock level crossing host: transactional bidirectional construction, both source boards, group drainage, train tail and save/reload")
