local L=dofile("mods/luanttd_core/ship_lock_presentation.lua")
local step={[0]={-1,0},{0,1},{1,0},{0,-1}}
for dir=0,3 do
  local lock={middle=5,dir=dir}
  local loc=step[dir]
  local v={direction=2*dir+1,x=10*16+8,y=12*16+8,z=24}
  local r={lock_middle=5,part="lower"}
  local dx,dz=v.x,v.y
  local function f() return L.frame(lock,r,v,10,12,3) end
  assert(f().lower and not f().upper and f().phase==0)
  r.part="middle"
  v.x,v.y=dx-2*loc[1],dz-2*loc[2]
  assert(f().lower and not f().upper)
  v.x,v.y=dx,dz
  for level=0,7 do
    v.z=24+level
    assert(not f().lower and not f().upper and f().phase==level/8)
  end
  v.z=32;assert(f().upper and not f().lower)
  r.part="upper";assert(f().upper)
  v.direction=(2*dir+5)%8;r.part="middle"
  v.x,v.y=dx+2*loc[1],dz+2*loc[2]
  assert(f().upper)
  v.x,v.y=dx,dz;assert(not f().upper and not f().lower)
  for level=7,1,-1 do
    v.z=24+level
    assert(not f().lower and not f().upper and f().phase==level/8)
  end
  v.z=24;assert(f().lower and not f().upper)
  local w,a,b,turn=L.pose(dir,10,12,3,.5)
  assert(w.x==20.5 and w.z==24.5 and w.y==4 and a.y==3.5 and b.y==3.5)
  assert(math.abs((b.x-a.x)*loc[1]+(b.z-a.z)*loc[2]-2.23)<1e-10)
  assert(type(turn)=="number")
end
print("PASS: native lock chamber follows all eight stock water-height steps with both gates closed on ascent/descent")
