local root="mods/luanttd_core/"
local counted=0
local Sim={W=4096,H=4096}
function Sim.id(x,z) return (z-1)*Sim.W+x end
function Sim.xy(id) return (id-1)%Sim.W+1,math.floor((id-1)/Sim.W)+1 end
function Sim.distance(a,b)
  local x,z=Sim.xy(a)
  local u,v=Sim.xy(b)
  counted=counted+1
  return math.abs(x-u)+math.abs(z-v)
end
local A=dofile(root.."town_road_authority.lua")(Sim,dofile(root.."openttd/road_town_permission.lua"))
local s={sites={},stock_generated_profile={},companies={A={}}}
for z=0,63 do for x=0,63 do
  local id=#s.sites+1
  s.sites[id]={id=id,kind="town",tile=Sim.id(x*64+(37*x+19*z)%64+1,z*64+(23*z+39*x)%64+1)}
end end
for i=1,512 do
  local tile=Sim.id((309*i-1)%4096+1,(2381*i-1)%4096+1)
  local limit=({1,20,49,88})[1+i%4]
  local town,d=A.nearest(s,tile)
  local prior=counted
  local r,actual=A.nearest_in(s,tile,limit)
  assert(counted==prior,"Local rating query traversed all towns")
  if d<limit then assert(r==town and actual==d)
  else assert(not r and not actual) end
end
assert(counted==2097152)
s.sites[4097]={kind="industry",id=4097,tile=s.sites[1].tile}
assert(A.nearest_in(s,s.sites[1].tile,1)==s.sites[1])
s.sites[4098]={kind="town",id=4098,tile=Sim.id(4096,4096)}
A.invalidate_towns(s)
assert(A.nearest_in(s,s.sites[4098].tile,1)==s.sites[4098])
local tile=Sim.id(25,20)
s.sites={{kind="town",id=1,tile=Sim.id(25,19)},{kind="town",id=2,tile=Sim.id(25,21)}}
assert(not A.nearest_in(s,tile,1))
assert(A.nearest_in(s,tile,2)==s.sites[1])
local last=s.sites[1]
last.name="Near Town"
s.companies.A.stock_town_authority_ratings={[last.id]=-200}
assert(A.company_view(s,s.companies.A,last).new_stations==false)
s.stock_road_town_policy={tolerance=3}
assert(A.company_view(s,s.companies.A,last).new_stations==true)
print("PASS 512 exact bounded Manhattan samples on 4096², stable ties, new town rebuild, and no 2,097,152 full-table distance probes")
