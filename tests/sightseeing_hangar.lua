local base="mods/luanttd_core/"
local H=dofile(base.."sightseeing_hangar.lua")(dofile(base.."openttd/airport_small.lua"),
  dofile(base.."openttd/airport_city.lua"))
local country={x=3,z=0,airport=7}
assert(H.has(country) and H.has({layout="city",x=5,z=0,airport=9}))
assert(not H.has({layout="heliport",x=0,z=0,airport=9}))
assert(not H.has({x=2,z=0,airport=7}))
local dx,dy,dz=0,-.06,-1
local eye={x=.95,y=.265,z=1.78}
assert(H.hit(eye,{x=dx,y=dy,z=dz}))
assert(not H.hit(eye,{x=1,y=0,z=0}))
assert(not H.hit({x=1.925,y=.30,z=.46},{x=-1,y=0,z=0}))
assert(not H.hit({x=.95,y=1.15,z=.46},{x=0,y=-1,z=0}))
assert(not H.hit({x=.95,y=.265,z=3.9},{x=dx,y=dy,z=dz}))
assert(not H.hit({x=.13,y=.16,z=1.8},{x=0,y=0,z=-1}),"keep live taxi centerline free of plane")
local p={get_pos=function()return {x=20.95,y=1.509,z=41.78} end,
  get_properties=function()return {eye_height=.265} end,get_look_dir=function()return {x=dx,y=dy,z=dz} end}
local Sim={id=function(x,z)return 100*z+x end}
local function get(id) if id==2010 then return {h=1,airfield=country} end end
local function visible(x,y,z) return x==21 and y==2 and z==40 end
local id,airport=H.pick(p,Sim,get,visible)
assert(id==2010 and airport==7)
-- Autoslope can lower the natural tile without moving the hangar pad.
local fixed={x=3,z=0,airport=7,level=1}
local function reshaped(id) if id==2010 then return {h=0,airfield=fixed} end end
local parked,field=H.pick(p,Sim,reshaped,visible)
assert(parked==2010 and field==7)
assert(not H.pick(p,Sim,get,function()return false end),"do not select an absent prop")
local file=assert(io.open(base.."models/bl_hangar_ga.obj"))
local bytes=file:read("*a");file:close()
local n=0
for x,y,z in bytes:gmatch("v ([%-%.%d]+) ([%-%.%d]+) ([%-%.%d]+)") do
  x,y,z=1-tonumber(x),tonumber(y)+.491,tonumber(z)
  assert(x>.60 and x<1.31 and y>=0 and y<.27 and z>=0 and z<.81)
  n=n+1
end
assert(n>250 and n<400 and #bytes<15000)
print("PASS stock fixed-wing hangars only, bounded/taxi-clear mesh, front approach picker, no hit through structures")
