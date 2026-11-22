local T=dofile("mods/luanttd_core/openttd/slope.lua")
local Road=dofile("mods/luanttd_core/openttd/road_slope.lua")
local generated=0
for _,mask in ipairs{3,6,9,12} do
  local path=("mods/luanttd_core/models/bl_road_grade_foundation_%d.obj"):format(mask)
  local model=assert(io.open(path))
  local v,tex,mtl,tri={},{},nil,{Road={},Retaining={}}
  for l in model:lines() do
    local x,y,z=l:match("^v ([^ ]+) ([^ ]+) ([^ ]+)")
    if x then v[#v+1]={.5-tonumber(x),tonumber(y)+.5,tonumber(z)+.5} end
    local u,t=l:match("^vt ([^ ]+) ([^ ]+)")
    if u then tex[#tex+1]={tonumber(u),tonumber(t)} end
    if l=="# road surface" then mtl="Road" end
    if l=="# retaining sides" then mtl="Retaining" end
    if l:match("^f ") then
      local a,at,b,bt,c,ct=l:match("^f (%d+)/(%d+) (%d+)/(%d+) (%d+)/(%d+)$")
      for _,i in ipairs{at,bt,ct} do
        local u=tex[tonumber(i)][1]
        assert((mtl=="Road" and u<.5) or (mtl=="Retaining" and u>.5))
      end
      table.insert(assert(tri[mtl]),{v[tonumber(a)],v[tonumber(b)],v[tonumber(c)]})
    end
  end
  model:close()
  assert(#tri.Road==2 and #tri.Retaining==4)
  for _,t in ipairs(tri.Road) do for _,p in ipairs(t) do
    assert(p[2]==T.surface(p[1]/2,p[3]/2,mask))
  end end
  local total=0
  for _,t in ipairs(tri.Retaining) do
    local a,b,c=t[1],t[2],t[3]
    local ux,uy,uz=b[1]-a[1],b[2]-a[2],b[3]-a[3]
    local vx,vy,vz=c[1]-a[1],c[2]-a[2],c[3]-a[3]
    local nx,ny,nz=uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx
    assert(ny==0 and nx*nx+nz*nz==4)
    assert(a[1]==b[1] and b[1]==c[1] and (a[1]==0 or a[1]==2)
      or a[3]==b[3] and b[3]==c[3] and (a[3]==0 or a[3]==2))
    for _,p in ipairs(t) do
      assert(p[2]==0 or p[2]==T.surface(p[1]/2,p[3]/2,mask))
    end
    total=total+math.sqrt(nx*nx+nz*nz)/2
  end
  assert(total==4)
  for _,raw in ipairs{1,2,4,8,23,27,29,30} do
    for _,bits in ipairs{5,10} do
      if Road.prepare(raw,bits,0,0,true) then
        local foundation=Road.foundation(raw,bits)
        local grade,rise=T.foundation(raw,foundation)
        if grade==mask and foundation~="none" then
          for z=0,20 do for x=0,20 do
            assert(1e-9+rise+T.surface(x/20,z/20,grade)>=T.surface(x/20,z/20,raw))
          end end
          generated=generated+1
        end
      end
    end
  end
end
assert(generated==16)
print("PASS: all 16 incline foundation outcomes keep their exact road top and fill only downhill boundaries")
