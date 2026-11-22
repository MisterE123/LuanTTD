-- SPDX-License-Identifier: GPL-2.0-only
-- Narrow differential fixture; not a save loader or general traffic controller.
local path=core.get_modpath(core.get_current_modname())
local function load(name) return dofile(path.."/"..name..".lua") end
local Motion=load("road_motion")(load("road_motion_data"))
local Speed,Close,Overtake=load("road_speed"),load("road_proximity"),load("road_overtake")
local file=assert(io.open(path.."/input.json","rb"))
local spec=assert(core.parse_json(file:read("*a")));file:close()
local floor,min,max=math.floor,math.min,math.max
local function flat_accel(speed,units)
  -- MPS Regal, flat (mass 10 t plus stock passengers at 1/16 t each,
  -- 90 hp, TE coefficient 76/256);
  -- GroundVehicle::GetAcceleration, identical pinned flat benchmark as
  -- the one-trip checkpoint. Only the measured two-bus envelope is valid.
  speed=floor(speed/2)
  local mass=10+floor(units/16)
  local max_te=floor(9800*mass*76/256)
  local power=90*746
  local resistance=10*mass+mass*floor(75*(128+speed)/128)+floor(6*41*speed*speed/1000)
  local force=speed>0 and min(max_te,floor(power*18/(speed*5))) or max(min(max_te,power),8*mass+resistance)
  local delta=force-resistance
  if delta==0 then return 0 end
  return delta>0 and max(1,floor(delta/(4*mass))) or min(-1,-floor(-delta/(4*mass)))
end
local function actor(src)
  assert(src["vehstatus"]==8 and src["current_order.type"]==97 and src.z_pos==8
    and src.reverse_ctr==0 and src.overtaking==0 and src.overtaking_ctr==0
    and src.onboard>=0 and src.onboard<=31
    and src.breakdown_ctr==0 and src.breakdown_delay==0 and src.order_max_speed==65535
    and (src.gv_flags==0 or src.gv_flags==4) and #src.cached_tiles==#src.cached_td and #src.cached_td<=1,
    "unsupported actors for flat junction oracle")
  local carried={}
  for i,p in ipairs(src.packets) do
    carried[i]={id=p.id,count=p.count,source=p.source,age=p.periods_in_transit}
  end
  return {id=src.id,first=src.id,type="road",direction=src.direction,heading=src.direction,
    state=src.state,frame=src.frame,x=src.x_pos,y=src.y_pos,z=src.z_pos,tile=src.tile,
    speed=src.cur_speed,subspeed=src.subspeed,progress=src.progress,
    blocked_ctr=src.blocked_ctr,ticks=src.tick_counter,order_time=src.current_order_time,
    age=src.cargo_age_counter,reverse_ctr=src.reverse_ctr,dest=src.dest_tile,
    cache_tile=src.cached_tiles[1],cache_td=src.cached_td[1],units=src.onboard,carried=carried}
end
local k=spec.samples[1].clock.tick_counter
local a,b=actor(spec.samples[1].buses[1]),actor(spec.samples[1].buses[2])
local merge=spec.mode=="merge"
assert(merge or spec.mode=="follower")
assert(a.id<b.id and a.dest==spec.east_bay and a.tile==spec.junction and a.state==8
  and a.direction==5 and a.blocked_ctr==0 and b.blocked_ctr==0)
if merge then
  assert(b.dest==spec.east_bay and b.tile==spec.junction and b.state==11 and b.direction==7)
else
  assert(b.dest==spec.branch and b.tile==spec.through and b.state==72 and b.direction==5)
end
local adjacent={[0]=-1,[1]=256,[2]=1,[3]=-256}
local counts={passengers=a.units+b.units,blocked=0,diverging=0,matched=0,changed_heading=0,
  boundary=0,blocked_different_current_heading=0}
local board={
  is_station=function(id) return id==spec.through or id==spec.east_bay or id==spec.branch end,
  adjacent=function(id,d) return id+adjacent[d] end,
  tile_status=function(id)
    -- Supported overtake checks should return earlier (station or
    -- identical maximum speed); reject unrelated routes and traffic.
    assert(id>=spec.through and id<spec.east_bay)
    error("overtake reached an unsupported lookahead tile: "..id)
  end,
  vehicles_at=function(tile)
    local r={}
    for _,v in ipairs({a,b}) do if v.tile==tile then r[#r+1]=v end end
    return r
  end,
}
local function motion(v,u)
  local kind,x,y,d,frame=Motion.step(v,1)
  local tx,td=v.tile,v.state
  local px,py=x,y
  if kind=="next_tile" then
    tx=v.tile+assert(adjacent[x])
    assert(tx>=spec.through and tx<spec.east_bay,"route outside junction aperture")
    td=not merge and v==b and tx==spec.junction and 5 or 8
    if v.cache_tile then
      assert(v.cache_tile==tx and v.cache_td==td,"unverified next cached stock segment")
      v.cache_tile,v.cache_td=nil,nil
    end
    kind,x,y,d,frame=Motion.enter(v,tx%256,floor(tx/256),td,1,0)
    px,py=x,y
  elseif kind=="rotate" then
    -- The stock close probe gets the proposed XY, not previous XY,
    -- even when success consumes a rotate-only frame.
    local q,r,s=Motion.sample(v.state,1,v.frame+1)
    assert(q=="position")
    px,py=v.x-v.x%16+r,v.y-v.y%16+s
  else
    assert(kind=="move","unsupported junction turnaround")
  end
  local hx,hy=floor((px-6)/16),floor((py-6)/16)
  local ex,ey=floor((px+6)/16),floor((py+6)/16)
  local ux,uy=u.tile%256,floor(u.tile/256)
  -- The candidate must also be in the stock XY hash search rectangle.
  local candidates=(ux>=hx and ux<=ex and uy>=hy and uy<=ey) and {u} or {}
  if Close.find(v,v,px,py,d,candidates) then
    counts.blocked=counts.blocked+1
    if v.direction~=u.direction then
      assert(merge and v==b and v.direction==6 and d==u.direction and d==5,
        "unexpected change of proposed heading at a wait")
      counts.blocked_different_current_heading=counts.blocked_different_current_heading+1
    end
    if kind=="enter" then
      v.cache_tile,v.cache_td=tx,td
      Overtake.entry_blocked(v,u)
    else
      for _,m in ipairs({v,u}) do
        m.acceleration=flat_accel(m.speed,m.units)
        m.max_speed=m.direction%2==0 and 84 or 112
      end
      local _,started=Overtake.within_blocked(board,v,u,false)
      assert(not started,"fixture does not support an overtake")
    end
    return false
  end
  if kind=="enter" then counts.boundary=counts.boundary+1 end
  if v.direction~=d then counts.changed_heading=counts.changed_heading+1 end
  v.tile,v.state,v.x,v.y,v.direction,v.heading,v.frame=tx,td,x,y,d,d,frame
  return true
end
local function tick(v,u)
  v.ticks=(v.ticks+1)%256
  v.order_time=v.order_time+1
  local budget=Speed.update(v,flat_accel(v.speed,v.units),4,v.direction%2==0 and 84 or 112)
  local need=Speed.advance_distance(v.direction)
  local blocked=false
  while budget>=need do
    budget=budget-need
    if not motion(v,u) then blocked=true;break end
    need=Speed.advance_distance(v.direction)
  end
  if v.progress==0 then v.progress=blocked and need-1 or budget end
  if v.age==1 then
    v.age=185
    for _,p in ipairs(v.carried) do p.age=min(65535,p.age+1) end
  else
    v.age=v.age-1
  end
end
local fields={x="x_pos",y="y_pos",z="z_pos",tile="tile",direction="direction",
  state="state",frame="frame",speed="cur_speed",subspeed="subspeed",progress="progress",
  blocked_ctr="blocked_ctr",ticks="tick_counter",order_time="current_order_time",age="cargo_age_counter",
  dest="dest_tile"}
for i,row in ipairs(spec.samples) do
  local target=row.clock.tick_counter
  assert(row.clock.pause_mode==1 and target>=k and target-k<=6)
  while k<target do
    -- Native road vehicle pool iterates ascending ID.
    tick(a,b);tick(b,a);k=k+1
  end
  for j,v in ipairs({a,b}) do
    local stock=row.buses[j]
    assert(stock.id==v.id and stock.z_pos==8 and stock.onboard==v.units and stock.breakdown_ctr==0
      and stock.breakdown_delay==0 and stock.reverse_ctr==0 and stock.overtaking==0
      and stock.overtaking_ctr==0 and stock["current_order.type"]==97)
    assert(#stock.packets==#v.carried,"stock packet chain changed")
    for n,p in ipairs(stock.packets) do
      local c=v.carried[n]
      assert(c.id==p.id and c.count==p.count and c.source==p.source and c.age==p.periods_in_transit,
        "stock active passenger packet mismatch")
    end
    assert(#stock.cached_tiles==#stock.cached_td and #stock.cached_td<=1
      and v.cache_tile==stock.cached_tiles[1] and v.cache_td==stock.cached_td[1],
      "next-segment cache mismatch at "..k.." in vehicle "..v.id)
    for lua,key in pairs(fields) do
      assert(v[lua]==stock[key],("stock tick %d vehicle %d %s: predicted %s vs %s"):format(
        k,v.id,key,tostring(v[lua]),tostring(stock[key])))
    end
  end
  if spec.author and k==spec.author.tick then
    local auth=spec.author
    assert(merge and auth.id==a.id and b.id~=auth.id and auth.current==0
      and auth.old==1 and auth.new==2 and auth.order==0 and auth.list==0
      and auth.active_index==1 and auth.next_index==0 and a.dest==spec.east_bay
      and b.dest==spec.east_bay and a.tile==spec.junction and b.tile==spec.junction
      and a.units>0 and b.units==0 and a.direction==5 and b.direction==6
      and a.blocked_ctr==0 and b.blocked_ctr==0,"unsupported dual-active authoring boundary")
    -- Materialize the intent from independently advanced actor values, not
    -- from the later stock row. Python compares this to a fresh exact draft.
    local function cursor(v)
      return {v.id,v.x,v.y,v.z,v.tile,v.direction,v.frame,v.state,v.speed,
        v.subspeed,v.progress,v.blocked_ctr,v.ticks,v.order_time,v.age,v.dest,v.units}
    end
    local body={schema="luanttd-dual-active-destination-intent/1", source_sha256=spec.source_sha256,
      authored_tick=k, edit=auth, actors={cursor(a),cursor(b)}}
    local data=assert(core.write_json(body))
    core.log("action","LuanTTD stock dual-active author intent "..assert(core.write_json(
      {body=data,sha256=core.sha256(data)})))
  end
  if a.tile==spec.junction and b.tile==spec.junction and a.direction~=b.direction then
    counts.diverging=counts.diverging+1
  end
  counts.matched=i
end
assert((counts.blocked_different_current_heading>0)==merge
  and counts.blocked>0 and counts.changed_heading>=2 and counts.diverging>0
  and counts.boundary>=2 and counts.matched>=(merge and 10 or 20),"incomplete traffic coverage")
core.log("action","LuanTTD stock junction differential PASS "..assert(core.write_json(counts)))
core.register_on_mods_loaded(function()
  core.after(.05,function() core.request_shutdown("junction differential completed",false,0) end)
end)
