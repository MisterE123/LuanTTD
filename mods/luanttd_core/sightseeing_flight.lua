-- Pure, real-time sightseeing physics at the campaign's compressed scale.
-- This deliberately has no reference to the stock commercial air fleet.
local F={}
local pi,abs,min,max,sin,cos=math.pi,math.abs,math.min,math.max,math.sin,math.cos
local function clamp(v,l,h) return min(h,max(l,v)) end
local function wrap(v) return (v+pi)%(2*pi)-pi end
local function approach(v,t,d) return v+clamp(t-v,-d,d) end
local function offset(r,p)
  local x,z=p.x-r.x,p.z-r.z
  return x*r.dx+z*r.dz,x*r.dz-z*r.dx
end
local function point(r,n)
  return {x=r.x+r.dx*n,y=r.y,z=r.z+r.dz*n}
end

-- FTA takeoff points are stock pixels relative to the northwest tile.
-- Their runway centerline and normal airport render gear datum transfer
-- unchanged; these are not artificial invisible launch pads.
function F.runway(field,id,origin_x,origin_z,ground,city)
  local i=city and 10 or 7
  local x,z=field.point(i)
  local u,v=field.point(i+1)
  local dx,dz=u-x,v-z
  local length=math.sqrt(dx*dx+dz*dz)
  assert(length>0)
  return {id=id,x=origin_x*2+x/8-.5,z=origin_z*2+z/8-.5,dx=dx/length,dz=dz/length,
    y=ground+.52,length=length/8,heading=math.atan2(dx,dz),name=city and "City Airport" or "Country Airport"}
end
function F.on_runway(r,p)
  if not r then return end
  local along,side=offset(r,p)
  if along>=0 and along<=r.length and abs(side)<=.52 then return along end
end
function F.start(r)
  return {runway=r,pos=point(r,.52),heading=r.heading,throttle=0,speed=0,
    pitch=0,bank=0,vertical=0,mode="ready"}
end
function F.distance(q,r)
  local x,z=q.pos.x-(r.x+r.dx*r.length/2),q.pos.z-(r.z+r.dz*r.length/2)
  return math.sqrt(x*x+z*z)
end
-- The original autopilot-like strip roll cannot recover once a wheel
-- leaves the centerline. The sightseeing aircraft now drives on a
-- sampled surface, with a forward roll and a slow reverse at idle.
local function taxi(q,k,dt,world)
  local old=q.pos
  local rollout=q.mode=="rollout"
  local steer=(k.right and 1 or 0)-(k.left and 1 or 0)
  local power=(k.up and 1 or 0)-(k.down and 1 or 0)
  q.throttle=rollout and 0 or clamp(q.throttle+power*dt*1.45,0,1)
  local reversing=not rollout and k.down and not k.up and q.throttle==0 and q.speed<=.13
  local target=rollout and 0 or reversing and -1.05 or q.throttle*8
  local rate=rollout and 4.8 or k.down and 5.8 or 3.9
  q.speed=approach(q.speed,target,dt*rate)
  local pivot=abs(q.speed)<.13 and .64 or clamp(1.3-abs(q.speed)*.14,.25,1.3)
  local heading=wrap(q.heading+(rollout and 0 or steer*pivot*dt*(reversing and -1 or 1)))
  local pitch,bank=q.pitch,q.bank
  local elevator=approach(q.elevator or 0,k.jump and .18 or 0,dt*.8)
  local nextpos={x=old.x+sin(heading)*q.speed*dt,y=old.y,z=old.z+cos(heading)*q.speed*dt}
  local takeoff=q.speed>=4.05 and elevator>=.08 and not rollout
  local lift=0
  if takeoff then
    pitch,bank=max(pitch,elevator),0
    lift=max(.32,q.speed*sin(pitch))
    nextpos.y=old.y+lift*dt
  else
    local next_y,why,slope,camber=world.ground(nextpos,heading)
    if not next_y then return 0,why end
    -- Differences within a normal slope are continuous across steps;
    -- don't pop wheels up a retaining wall or drop off a ledge.
    if abs(next_y-old.y)>.105+abs(q.speed)*dt*.58 then
      return 0,"Slope or ledge too steep. S to reverse, E to return."
    end
    nextpos.y=next_y
    pitch,bank=(slope or 0)+elevator*.40,camber or 0
  end
  local clear,why=world.clear(nextpos,heading,nil,pitch,bank,not takeoff)
  if not clear then return 0,why end
  local turn=wrap(heading-q.heading)
  q.pos,q.heading,q.pitch,q.bank,q.vertical,q.elevator=nextpos,heading,pitch,bank,lift,elevator
  if takeoff then q.departure_y=old.y end
  q.mode=takeoff and "air" or rollout and abs(q.speed)>.02 and "rollout"
    or abs(q.speed)>.02 and "taxi" or "ready"
  return turn
end

local function advance(q,k,dt,world)
  if world.ground and q.mode~="air" then return taxi(q,k,dt,world) end
  local landing_roll=q.mode=="rollout"
  local airborne=q.mode=="air"
  local pitch_input=(k.jump and 1 or 0)-(k.sneak and 1 or 0)
  local steer=(k.right and 1 or 0)-(k.left and 1 or 0)
  local power=(k.up and 1 or 0)-(k.down and 1 or 0)
  if landing_roll then
    q.throttle=0
    q.speed=max(0,q.speed-dt*4.8)
    q.pitch=approach(q.pitch,0,dt*.6)
  else
    q.throttle=clamp(q.throttle+power*dt*1.45,0,1)
    local target=airborne and (2+q.throttle*10) or q.throttle*8
    local rate=k.down and 5.8 or airborne and 2.4 or 3.9
    q.speed=approach(q.speed,target,rate*dt)
    local pitch_range=airborne and .32 or .18
    -- Terrain is vertically compressed much less than the runways are
    -- shortened. Use a brief obstacle-climb setting near liftoff, not
    -- a geometry bypass or a teleport over the neighboring buildings.
    if airborne and q.departure_y and q.pos.y-q.departure_y<3 and pitch_input>0 then pitch_range=.44 end
    -- Slower final approaches use a gentler elevator throw. Avoid putting
    -- the nose through the runway before the landing gear reaches it.
    if airborne and pitch_input<0 and q.speed<6.6 then pitch_range=.19 end
    q.pitch=approach(q.pitch,pitch_input*pitch_range,dt*.8)
  end
  local old_heading=q.heading
  if airborne then
    q.bank=approach(q.bank,steer*.58,dt*1.7)
    q.heading=wrap(q.heading+q.bank*7/max(4,q.speed)*dt)
    local sink=max(0,4.5-q.speed)*1.30
    q.vertical=q.speed*sin(q.pitch)-sink
  else
    q.bank,q.vertical=0,0
    if q.speed<.001 and landing_roll then q.mode="ready";return 0 end
    if not landing_roll and q.speed>=4.05 and q.pitch>=.08 then
      q.mode="air";airborne=true
      q.vertical=max(.32,q.speed*sin(q.pitch))
    end
  end
  local old=q.pos
  local speed=q.speed*(airborne and cos(q.pitch) or 1)
  local nextpos={x=old.x+sin(q.heading)*speed*dt,y=old.y+q.vertical*dt,z=old.z+cos(q.heading)*speed*dt}
  local r=q.runway
  if not airborne then
    local live=world.runway_at(old)
    if not live or live.id~=r.id then return 0,"The runway is no longer available. E to recover." end
    local n=F.on_runway(r,nextpos)
    if not n then
      q.throttle,q.speed,q.pitch=0,0,0
      q.mode="short"
      return 0,"Ran out of runway. E to reset; hold Space as you accelerate."
    end
    nextpos=point(r,n)
    if not landing_roll and q.speed>.02 then q.mode="takeoff" end
  else
    local strip=world.runway_at(nextpos)
    local distance=F.on_runway(strip,nextpos)
    if distance and old.y>strip.y and nextpos.y<=strip.y and q.vertical<0 then
      local direction=cos(wrap(q.heading-strip.heading))
      local remaining=direction>0 and strip.length-distance or distance
      -- Touchdown requires a clear, aligned runway with enough pavement
      -- left to decelerate. A fast/steep attempt isn't snapped to safety.
      if abs(direction)>.94 and abs(q.bank)<.27 and q.vertical>=-2.1 and
          q.speed>=2.4 and q.speed<=6.6 and remaining>=q.speed*q.speed/9.6+.2 then
        nextpos=point(strip,distance)
        local clear,why=world.clear(nextpos,q.heading,strip,0,0)
        if not clear then return 0,why or "Runway obstructed." end
        q.pos,q.runway,q.mode=nextpos,strip,"rollout"
        q.throttle,q.vertical,q.bank=0,0,0
        q.heading=wrap(strip.heading+(direction>0 and 0 or pi))
        return wrap(q.heading-old_heading)
      end
      return 0,"Landing missed: line up, slow down and touch down earlier."
    end
    -- An airport strip still uses its alignment and stopping-distance
    -- rules. A controlled landing can also put wheels on open dry land.
    if world.ground and not distance and q.vertical<0 then
      local y=world.ground(nextpos,q.heading)
      if y and old.y>y and nextpos.y<=y and abs(q.bank)<.25 and
          q.vertical>=-1.4 and q.speed>=2.4 and q.speed<=5.7 then
        nextpos.y=y
        local clear,why=world.clear(nextpos,q.heading,nil,0,0,true)
        if not clear then return 0,why end
        q.pos,q.mode=nextpos,"rollout"
        q.throttle,q.vertical,q.bank,q.pitch=0,0,0,0
        return wrap(q.heading-old_heading)
      end
    end
  end
  local clear,why=world.clear(nextpos,q.heading,not airborne and r or nil,q.pitch,q.bank)
  if not clear then return 0,why or "Terrain or obstacle ahead." end
  q.pos=nextpos
  if q.departure_y and q.pos.y-q.departure_y>=3 then q.departure_y=nil end
  return wrap(q.heading-old_heading)
end
function F.step(q,keys,dt,world)
  local turned=0
  -- At 12 nodes/s each sweep is <= .24 node, preventing tunneling
  -- through narrow scenery between engine callbacks.
  dt=clamp(dt,0,.12)
  while dt>1e-6 do
    local step=min(dt,.020)
    local throttle,speed,pitch,bank,heading,vertical,mode=q.throttle,q.speed,q.pitch,q.bank,q.heading,q.vertical,q.mode
    local delta,why=advance(q,keys,step,world)
    turned=turned+delta
    if why then
      if q.mode~="short" then
        -- A rejected substep must not turn, gain speed, or change phase
        -- while the aircraft is stopped at its last clear position.
        q.throttle,q.speed,q.pitch,q.bank,q.heading,q.vertical,q.mode=throttle,speed,pitch,bank,heading,vertical,mode
      end
      if world.ground and q.mode~="air" then
        q.throttle,q.speed,q.vertical=0,0,0
        q.mode,q.elevator="ready",0
      end
      return turned,why
    end
    dt=dt-step
  end
  return turned
end
return F
