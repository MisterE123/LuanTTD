-- SPDX-License-Identifier: GPL-2.0-only
local dir="mods/luanttd_core/"
local T=dofile(dir.."openttd/rail_track.lua")
local stock=dofile(dir.."rail_pose.lua")(T).sample
local Sim={tiles={}}
function Sim.id(x,z) if x>=1 and z>=1 and x<=10 and z<=10 then return (z-1)*10+x end end
function Sim.xy(id) return (id-1)%10+1,math.floor((id-1)/10)+1 end
function Sim.adjacent(id,d)
  local x,z=Sim.xy(id)
  local a=({[0]={-1,0},{0,1},{1,0},{0,-1}})[4-d]
  return Sim.id(x+a[1],z+a[2])
end
local function rail(x,z,pieces,level)
  local id=Sim.id(x,z)
  Sim.tiles[id]={rail_type=2,rail_tracks=pieces,owner="Owner",h=level or 0}
  return id
end
local D=dofile(dir.."rail_diagonal.lua")(Sim,T)
local function diag(id,td,f) return D.sample(td,f,D.mode(Sim,id)) end
local grade
local function surface(id,td,f)
  local h=Sim.tiles[id].h
  if grade==id then
    local dir=T.exit_side(td)==2 and 1 or -1
    return h+(dir==1 and f or 1-f),math.atan2(dir,2)
  end
  return h,0
end
local project=dofile(dir.."rail_guideway_bogies.lua")(Sim,T,diag,stock,surface,function(id) return Sim.tiles[id] end)
local function near(actual,expected,tol)
  assert(math.abs(actual-expected)<(tol or .00001),("%f != %f"):format(actual,expected))
end
local function continuity(p,q,delta)
  near(math.sqrt((p.x-q.x)^2+(p.z-q.z)^2),delta,.0001)
end
local l,c,r=rail(3,6,1),rail(4,6,1),rail(5,6,1)
local route={{tile=l,td=8},{tile=c,td=8},{tile=r,td=8}}
local p,y,g=project({route=route,index=2},{id=c,td=8,progress=.5})
near(p.x,8.5);near(p.y,.746);near(p.z,12.5)
near(g[1].pos.x,8.759);near(g[2].pos.x,8.254)
near(y.y,math.pi/2)
p,y,g=project({route=route,index=2},{id=c,td=8,progress=.96})
near(g[1].pos.x,9.679);near(g[2].pos.x,9.174)
near(g[1].rotation.y,g[2].rotation.y)
grade=c
p,y,g=project({route=route,index=2},{id=c,td=8,progress=.5})
near(g[1].pos.y,.746+.6295);near(g[2].pos.y,.746+.377)
near(y.x,-math.atan2(1,2))
grade=nil
local q=rail(4,4,4)
local west=rail(3,4,8)
local north=rail(4,3,8)
assert(D.mode(Sim,q)==3)
local td=T.trackdir_for_exit(2,3)
local other=T.trackdir_for_entry(3,3)
local chain={route={{tile=west,td=11},{tile=q,td=td},{tile=north,td=other}},index=2}
local a,aa,gearA=project(chain,{id=q,td=td,progress=1})
local b,bb,gearB=project(chain,{id=north,td=other,progress=0})
for i=1,2 do continuity(gearA[i].pos,gearB[i].pos,0) end
continuity(a,b,0)
near(aa.y,bb.y)
-- The same curve used when the arrival is visually nose-first either way.
a,_,gearA=project(chain,{id=q,td=td,progress=.8},false)
b,_,gearB=project(chain,{id=q,td=T.reverse_trackdir(td),progress=.2},true)
for i=1,2 do continuity(gearA[i].pos,gearB[i].pos,0) end
continuity(a,b,0)
-- One normal quarter bend: front and back guide wheels take genuinely
-- different headings. A rigid body cannot supply both headings.
local curve=rail(6,6,4)
local midpoint,rotation,trucks=project({},{id=curve,td=td,progress=.5})
local a1,a2=trucks[1].rotation.y,trucks[2].rotation.y
local angular=(a1-a2+math.pi)%(2*math.pi)-math.pi
near(math.abs(angular),.505,.0001)
near(midpoint.y,.746)
print("PASS rail bogies keep correct surface height, distinct ordinary-curve yaw and continuous diagonal seams in both directions")
local link=dofile(dir.."rail_guideway_drawbar.lua")
local function center(x,idx,yaw)
  return {index=idx,pos={x=x,y=3,z=8},rotation={x=0,y=yaw or math.pi/2,z=0}}
end
local joint=assert(link(center(2,1),center(1,2)))
near(joint.pos.x,1.5);near(joint.pos.y,3.095);near(joint.length,.092/.12)
assert(not link(center(2,1),center(1,3)))
assert(not link(center(9,1),center(1,2)),"do not draw a misleading link across culling or teleport")
joint=assert(link(center(1,1,-math.pi/2),center(2,2,-math.pi/2)))
near(joint.pos.x,1.5);near(joint.length,.092/.12)
print("PASS visible drawbars connect adjacent cars in either direction and never jump a hidden or widely separated car")
