local root="mods/luanttd_core/openttd/"
local A=dofile(root.."airport_small.lua")
local Move=dofile(root.."airport_motion.lua")(A)
local S,B=A.state,A.block
local function air(id,x,z,owner)
  return {id=id,x=x or 0,z=z or 0,ground=16,flags=0,owner=owner or "A"}
end
local origin=air(1,96,96)
local dst=air(2,640,337)
local h={airports={[1]=origin,[2]=dst},plane_speed=4}
local function sequence(a,v,wanted,max_ticks)
  local events={}
  local climbed=false
  local runway=false
  for tick=1,max_ticks or 25000 do
    local next,results,why=Move.tick(a,v,h)
    assert(not why,why)
    a=next
    if v.y>(a.ground+1) then climbed=true end
    for _,s in ipairs(results) do
      events[#events+1]=s
      if s=="approach" then
        assert(A.has(a.flags,B.BUSY));runway=true
      end
      if s=="terminal" then
        assert(v.loading and v.y==a.ground+1)
        assert(v.x==a.x+(v.pos==2 and 32 or 10) and v.z==a.z+23 and v.direction==7)
      end
      if s==wanted then return a,events,tick,climbed,runway end
    end
  end
  error(("no %s: %s position=%s coords=%s,%s"):format(wanted,table.concat(events,","),v.pos,v.x,v.z))
end
assert(A.W==4 and A.H==3 and A.hangar.x==3 and A.hangar.z==0)
local p=A.new(origin,{owner="A",max_speed=512,order={kind="station",id=2}})
assert(p.hidden and p.pos==0 and p.direction==3)
local a,ev,_,climbed,runway=sequence(origin,p,"terminal")
assert(p.target==2 and a==dst and p.pos==2 and climbed and runway)
assert(table.concat(ev,","):match("takeoff,.*liftoff,.*departed,.*approach,.*touchdown,"))
assert(origin.flags==0 and dst.flags==B.TERM1)
p.loading=nil;p.order={kind="station",id=1}
a=sequence(dst,p,"terminal")
assert(a==origin and p.last_station==1 and dst.flags==0 and origin.flags==B.TERM1)
p.loading=nil;p.order={kind="depot",id=1}
a=sequence(origin,p,"hangar")
assert(a==origin and p.hidden and p.pos==0 and origin.flags==0)

-- Busy coverage: aircraft in the air keep speed in holding, and neither
-- a closed nor a competing airport accepts a new landing approach.
local function inbound(a)
  return {pos=10,previous_pos=18,state=S.FLYING,speed=356,subspeed=234,
    owner="A",x=a.x+177,z=a.z+40,y=a.ground+160,order={kind="station",id=a.id}}
end
p=inbound(dst)
dst.flags=B.BUSY
assert(A.arrive(dst,p)=="hold" and p.pos==15 and p.speed==356 and p.subspeed==234)
p=inbound(dst);dst.flags=0;dst.closed=true
assert(A.arrive(dst,p)=="hold" and dst.flags==0)
p=inbound(dst);dst.closed=nil;dst.owner="Competitor"
assert(A.arrive(dst,p)=="hold" and dst.flags==0)
p=inbound(dst);dst.owner="A"
assert(A.arrive(dst,p)=="approach" and p.pos==11 and dst.flags==B.BUSY)
local other=inbound(dst)
assert(A.arrive(dst,other)=="hold" and dst.flags==B.BUSY)

-- Both terminal choices are sticky, and full terminals route to the
-- hangar without dropping airport runway ownership in mid-taxi.
p={pos=13,previous_pos=12,state=S.ENDLANDING,speed=0,subspeed=0,owner="A",
   order={kind="station",id=dst.id},x=dst.x+7,z=dst.z+40,y=17,direction=5}
dst.flags=B.BUSY+B.TERM1
assert(A.arrive(dst,p)=="assigned_terminal" and p.state==S.TERM2)
assert(dst.flags==B.BUSY+B.TERM1+B.TERM2)
assert(A.arrive(dst,p)=="next" and p.pos==5)
assert(A.arrive(dst,p)=="next" and p.pos==3)
assert(A.arrive(dst,p)=="terminal" and dst.flags==B.TERM1+B.TERM2)
p={pos=13,previous_pos=12,state=S.ENDLANDING,speed=0,subspeed=0,owner="A",
   order={kind="station",id=dst.id},x=dst.x+7,z=dst.z+40,y=17,direction=5}
dst.flags=B.BUSY+B.TERM1+B.TERM2
assert(A.arrive(dst,p)=="to_hangar" and p.state==S.HANGAR)
assert(A.arrive(dst,p)=="next" and p.pos==14)
assert(dst.flags==B.BUSY+B.TERM1+B.TERM2)
assert(A.arrive(dst,p)=="next" and p.pos==1)
assert(A.arrive(dst,p)=="next" and p.pos==0)
assert(A.arrive(dst,p)=="hangar" and dst.flags==B.TERM1+B.TERM2)
print("PASS: stock fixed-wing departure and round trip, landing/holding arbitration, both terminals, hangar and block release")
