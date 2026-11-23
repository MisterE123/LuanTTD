local dir="mods/luanttd_core/"
local Track=dofile(dir.."openttd/rail_track.lua")
local Scope=dofile(dir.."rail_diagonal.lua")
local Sim={}
function Sim.id(x,z) if x>=1 and x<=10 and z>=1 and z<=10 then return (z-1)*10+x end end
function Sim.xy(id) return (id-1)%10+1, math.floor((id-1)/10)+1 end
local s={tiles={}}
local shape={}
local D=Scope(Sim,Track,{tile=function(id) return shape[id] or 0,s.tiles[id].h end},
  function(q,y) if q==3 then return 0,y+1 elseif q==0 then return 0,y end end)
local old=dofile(dir.."rail_pose.lua")(Track)
local function track(x,z,bits)
  local id=Sim.id(x,z)
  local t={h=2,owner="P",rail_tracks=bits}
  s.tiles[id]=t
  return id,t
end
local a,t=track(4,5,4)
local w,west=track(3,5,8)
local n,north=track(4,4,8)
assert(D.mode(s,a)==3 and D.mode(s,w)==1 and D.mode(s,n)==2)
local function near(a,b) assert(math.abs(a-b)<1e-9, ("%f != %f"):format(a,b)) end
-- Physical track still uses unmodified X/Z route parts and stock ports.
assert(t.rail_tracks==4 and west.rail_tracks==8 and north.rail_tracks==8)
local function directional(x,z,dx,dz, xx,zz,dxx,dzz)
  near(x,xx);near(z,zz);near(dx,dxx);near(dz,dzz)
end
for _,mask in ipairs({4,8,16,32}) do
  local idx=math.floor(math.log(mask)/math.log(2)+.5)
  for mode=1,3 do
    for i=0,20 do
      local f=i/20
      local x,z,dx,dz=D.sample(idx,f,mode)
      local a,b,c,d=D.sample(idx+8,1-f,mode)
      directional(x,z,dx,dz,a,b,-c,-d)
      near(dx*dx+dz*dz,1)
      if i==0 or i==20 then
        local ox,oz=old.sample(idx,f)
        near(x,ox);near(z,oz)
      end
    end
  end
end
local td=Track.trackdir_for_exit(2,3) -- own UPPER, heading north diagonally
local x,z,dx,dz=D.sample(td,1,3)
local tx,tz,tdx,tdz=D.sample(Track.trackdir_for_entry(3,3),0,2)
directional(x,z,dx,dz,tx,tz-2,tdx,tdz)
-- A transition ends with the exact derivative that an old plain curve
-- uses. Junctions, depots, different owners and uneven railheads cannot
-- cause another tile to select a diagonal seam.
local wt=Track.trackdir_for_exit(3,1)
local x,z,dx,dz=D.sample(wt,1,1)
directional(x,z,dx,dz,old.sample(wt,1))
north.rail_tracks=9;assert(D.mode(s,a)==1 and D.mode(s,n)==0)
north.rail_tracks=8;north.rail_type=1;assert(D.mode(s,a)==1);north.rail_type=nil
north.rail_waypoint_id=10;assert(D.mode(s,a)==1);north.rail_waypoint_id=nil
north.owner="another";assert(D.mode(s,a)==1);north.owner="P"
north.h=1;assert(D.mode(s,a)==1)
shape[n]=3;assert(D.mode(s,a)==3 and D.mode(s,n)==2) -- level foundation
shape[n]=1;assert(D.mode(s,a)==1)
s.tiles[w]=nil;s.tiles[n]=nil;assert(D.mode(s,a)==0)
assert(not D.sample(wt,.5,0))
print("PASS continuous diagonal modes, y/ownership qualification, legacy transition tangents and reverse train pose")
