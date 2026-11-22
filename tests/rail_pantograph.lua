-- Rendering geometry only. Use the exact one-unit rise per two-node
-- ramp and coastal test circuit's deck of 2. No flat-grade motion claims.
local P=dofile("mods/luanttd_core/rail_pantograph.lua")
local rise,deck,track=1,2,.614
local shoe,pivot,shoe_z=.784,.580,.031
local center=2*21+.5
local low,high=deck-rise+track+shoe,deck+track+shoe
local ramps={
  {center-3,low,center-1,low},
  {center-1,low,center+1,high},
  {center+1,high,center+3,high},
}
local function target(u)
  return low+math.max(0,math.min(1,(u-center+1)*.5))
end
local max_reach,min_reach=0,1
local trials=0
for travel=-1,1,2 do
  for i=-230,230 do
    local u=center+i/100
    local rail=target(u)-shoe
    local local_pitch=math.abs(u-center)<1 and math.atan(.5)*travel or 0
    local si,co=math.sin(local_pitch),math.cos(local_pitch)
    -- Longitudinal reflection models entering on the reversed cab
    -- without changing where the pole/tree/ground lives in the world.
    local heel_u=u+travel*(shoe_z*co-pivot*si)
    local heel_y=rail+shoe_z*si+pivot*co
    local reach,x,y=assert(P.contact(ramps,heel_u,heel_y,-travel*si,co,.03,.45))
    assert(math.abs(y-target(x))<1e-7)
    min_reach,max_reach=math.min(min_reach,reach),math.max(max_reach,reach)
    trials=trials+1
  end
end
local nominal,x,y=assert(P.contact(ramps,center-1,low-(shoe-pivot),0,1,.03,.45))
assert(math.abs(nominal-(shoe-pivot))<1e-8 and x==center-1 and y==low)
local insufficient,why=P.contact(ramps,center-2,low-1,0,1,0,.35)
assert(not insufficient and why=="NO_WIRE_CONTACT")
local unwired,err=P.contact({{0,0,1,0},{1,1,2,1}},1,0,0,1,0,1)
assert(not unwired and err=="DISCONTINUOUS_WIRE")
assert(select(2,P.contact({{0,0,1,2}},0,0,1,1,0,1))=="UNSUPPORTED_WIRE_ANGLE")
print(("PASS detached bridge pantograph contact ray: %d placements, extension %.3f–%.3f native units"):format(trials,min_reach,max_reach))

-- Optional validation of actual Luanti 5.10 rotation, not a model of
-- engine client Eulers. Pass the installed builtin/common/vector.lua.
if arg[1] then
  dofile(arg[1])
  local rotate=assert(vector.rotate)
  for _,axis in ipairs{"x","z"} do
    local cross=axis=="x" and "z" or "x"
    for facing=-1,1,2 do
      local yaw=axis=="x" and -facing*math.pi/2 or facing<0 and math.pi or 0
      for i=-220,220 do
        local u=center+i/100
        local body={y=target(u)-shoe,[axis]=u,[cross]=5}
        local rot={x=math.abs(u-center)<1 and facing*math.atan(.5) or 0,y=yaw,z=0}
        local mount,why=P.mount(ramps,axis,5,body,rot,rotate,.03,.45)
        assert(mount,why)
        local shoe_offset=rotate({x=0,y=mount.extension,z=P.shoe_run},rot)
        for k,v in pairs(mount.world_contact) do assert(math.abs(v-mount.heel[k]-shoe_offset[k])<1e-8) end
        assert(math.abs(mount.world_contact.y-target(mount.world_contact[axis]))<1e-8)
      end
    end
  end
  local invalid,why=P.mount(ramps,"x",6,{x=center-2,y=low-shoe,z=5},{x=0,y=0,z=0},rotate,.03,.45)
  assert(not invalid and why=="CONTACT_OUTSIDE_SHOE")
  print("PASS installed Luanti pitch/yaw basis on both axes and both cab directions (1,764 mounts)")
end
