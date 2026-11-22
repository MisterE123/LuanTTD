-- An original mechanical presentation of stock water-height changes. Gate
-- meshes and the movable chamber do not control vehicle path or collision.
local L={}
local steps={[0]={-1,0},{0,1},{1,0},{0,-1}}
local rotations={[0]=math.pi/2,0,-math.pi/2,math.pi}
local gate_distance=1.115
function L.frame(lock,record,vehicle,x,z,base)
  if vehicle and record and record.lock_middle==lock.middle then
    if record.part=="lower" then return {phase=0,lower=true,upper=false} end
    if record.part=="upper" then return {phase=1,lower=false,upper=true} end
    local dx,dz=steps[lock.dir][1],steps[lock.dir][2]
    local offset=(vehicle.x-(x*16+8))*dx+(vehicle.y-(z*16+8))*dz
    local travel=2*lock.dir+1==vehicle.direction
    local phase=math.max(0,math.min(1,(vehicle.z-base*8)/8))
    local incoming=travel and offset<0 or not travel and offset>0
    local outgoing=travel and offset>0 or not travel and offset<0
    local at_exit=offset==0 and (travel and phase==1 or not travel and phase==0)
    return {phase=phase,lower=(incoming and travel or (outgoing or at_exit) and not travel) and phase==0,
      upper=(incoming and not travel or (outgoing or at_exit) and travel) and phase==1}
  end
  return lock.presentation or {phase=0,lower=true,upper=false}
end
function L.pose(dir,x,z,base,phase)
  local step=steps[dir]
  local xx,zz=2*x+.5,2*z+.5
  local y=base+.5
  return {x=xx,y=y+phase,z=zz},
    {x=xx-gate_distance*step[1],y=y,z=zz-gate_distance*step[2]},
    {x=xx+gate_distance*step[1],y=y,z=zz+gate_distance*step[2]},
    rotations[dir]
end
return L
