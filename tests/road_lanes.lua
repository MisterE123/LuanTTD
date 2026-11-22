local L = dofile("mods/bayline/road_lanes.lua")
local M = dofile("mods/bayline/road_motion.lua")

local function near(a,b)
  assert(math.abs(a-b)<1e-8, tostring(a).." ~= "..tostring(b))
end
local specs = {{'bus','town_flyer'},{'truck','truck'},{'coach','coach'}}
local bounds = {}
for _,pair in ipairs(specs) do
  local engine,key=pair[1],pair[2]
  local mnx,mxx,mnz,mxz
  for line in io.lines("mods/bayline/models/bl_"..key..".obj") do
    if line:sub(1,2)=="v " then
      local x,_,z = line:match("^v%s+(%S+)%s+(%S+)%s+(%S+)")
      x,z=tonumber(x)/10,tonumber(z)/10
      mnx,mxx=math.min(mnx or x,x),math.max(mxx or x,x)
      mnz,mxz=math.min(mnz or z,z),math.max(mxz or z,z)
    end
  end
  local scale=L.visual_size(engine)
  near(scale.x,scale.y)
  near(scale.x,scale.z)
  local half_width=math.max(math.abs(mnx),mxx)*scale.x
  local half_length=math.max(math.abs(mnz),mxz)*scale.z
  assert(L.right_offset-half_width>.02)
  assert(L.road_width/2-L.right_offset-half_width>.02)
  bounds[#bounds+1]={half_width,half_length}
end
near(L.visual_size("steam").x,1)
local head={{0,1,.155,0},{1,0,0,-.155},{0,-1,-.155,0},{-1,0,0,.155}}
for _,v in ipairs(head) do
  local x,z=L.offset(v[1]*2,v[2]*2)
  near(x,v[3])
  near(z,v[4])
end
local ox,oz=L.offset(0,0)
near(ox,0)
near(oz,0)
near(L.depot_blend(0,true,false),0)
near(L.depot_blend(.25,true,false),.5)
near(L.depot_blend(.5,true,false),1)
near(L.depot_blend(.5,false,true),1)
near(L.depot_blend(.75,false,true),.5)
near(L.depot_blend(1,false,true),0)

-- Check full sampled vehicle footprint through synthetic orthogonal
-- compact corners, both right and left. A rectangular test may be more
-- conservative than the rounded Blender bumper.
local function xy(p) return p[1],p[2] end
for _,side in ipairs({-1,1}) do
  local route={{0,-1},{0,0},{side,0}}
  for j=1,199 do
    local progress=2-L.corner_radius+j*(2*L.corner_radius/200)
    local x,z,dx,dz=M.corner(route,progress,xy)
    x,z=x-.5,z-.5
    x,z=L.position(x,z,dx,dz,L.outside_phase(route,progress,xy))
    local norm=math.sqrt(dx*dx+dz*dz)
    dx,dz=dx/norm,dz/norm
    for _,size in ipairs(bounds) do
      for a=0,20 do
        for b=0,6 do
          local len=size[2]*(2*a/20-1)
          local wid=size[1]*(2*b/6-1)
          local vx=x+dx*len+dz*wid
          local vz=z+dz*len-dx*wid
          local edge=L.road_width/2+1e-8
          local approaching=(math.abs(vx)<=edge and vz<=edge)
          local exiting=(math.abs(vz)<=edge and side*vx>=-edge)
          assert(approaching or exiting,"asset crosses the asphalt through an orthogonal compact corner")
        end
      end
    end
  end
  assert(not L.outside_phase(route,1,xy))
  assert(not L.outside_phase(route,3,xy))
end
print("PASS road lane scales, straight clearance, depot transition, and both curved swept footprints")
