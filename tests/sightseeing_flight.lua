local p="mods/luanttd_core/"
local Flight=dofile(p.."sightseeing_flight.lua")
local Small=dofile(p.."openttd/airport_small.lua")
local City=dofile(p.."openttd/airport_city.lua")
local runway=Flight.runway(Small,1,10,12,2,false)
local city=Flight.runway(City,2,20,27,0,true)
assert(runway.length==7.25 and runway.x==27.125 and runway.z==28.5 and runway.y==2.52)
assert(city.length==10.75 and city.x==50.625 and city.z==64.125 and city.y==.52)
assert(runway.dx==-1 and runway.dz==0 and city.dx==-1)
local ground={runway_at=function() return runway end,clear=function() return true end}
local q=Flight.start(runway)
for _=1,30 do
  assert(not select(2,Flight.step(q,{up=true,jump=true},.1,ground)))
  if q.mode=="air" and q.pos.y>3.75 then break end
end
assert(q.mode=="air" and q.pos.y>3.75 and q.pos.x<runway.x-2)
local yaw=q.heading
for _=1,10 do Flight.step(q,{right=true},.1,ground) end
assert(q.bank>.50 and q.heading>yaw+.10)
for _=1,10 do Flight.step(q,{},.1,ground) end
assert(math.abs(q.bank)<1e-8)
-- A steady, level final with a shallow descent must touch real pavement
-- before rollout. No lowering or automatic relocation off centerline.
local function approach(r,lateral,speed,pitch)
  local q=Flight.start(r)
  q.pos={x=r.x-.9,y=r.y+.13,z=r.z+(lateral or 0)}
  q.mode,q.speed,q.throttle,q.pitch="air",speed,(speed-2)/10,pitch
  return q
end
for _,r in ipairs({runway,city}) do
  local w={runway_at=function()return r end,clear=function() return true end}
  local a=approach(r,.16,4.9,-.14)
  for _=1,20 do Flight.step(a,{sneak=true},.1,w);if a.mode=="rollout" then break end end
  assert(a.mode=="rollout" and a.pos.y==r.y and a.pos.z==r.z)
  for _=1,20 do Flight.step(a,{},.1,w) end
  assert(a.mode=="ready" and a.speed==0 and Flight.on_runway(r,a.pos))
  local fast=approach(r,0,8.4,-.12)
  local rejected
  for _=1,12 do
    local _,why=Flight.step(fast,{sneak=true},.1,w)
    if why then rejected=why;break end
  end
  assert(rejected and fast.pos.y>r.y and fast.mode=="air")
end
local take=Flight.start(city)
local last=take.pos.x
for _=1,80 do
  local _,why=Flight.step(take,{up=true},.1,{runway_at=function()return city end,clear=function(q)
    if q.x<last-1 then return false,"scenery" end
    return true
  end})
  if why then
    assert(why=="scenery" and take.pos.x>=last-1,"Crossed a swept obstruction")
    break
  end
end
assert(take.pos.x<last and take.mode~="air")
local gone=Flight.start(city)
assert(select(2,Flight.step(gone,{up=true,jump=true},.005,{runway_at=function()end,
  clear=function()error("Launched on deleted runway")end})):find("no longer",1,true))
print("PASS stock runway geometry, powered takeoff, manual bank and recovery, shallow landing on both airports, fast landing declined and swept obstruction respected")
