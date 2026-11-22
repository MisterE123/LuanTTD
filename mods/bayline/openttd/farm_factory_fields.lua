-- SPDX-License-Identifier: GPL-2.0-only
-- Temperate planting/fence rules: OpenTTD 14.1 industry_cmd.cpp
-- PlantRandomFarmField, PlantFarmField, SetupFarmFieldFence and map.cpp.
-- Board uses real source tile classifications; no time/render ownership.
return function(Commons)
  local F={}
  local floor,min=math.floor,math.min
  local types={1,1,1,1,1,3,3,4,4,4,5,5,5,6,6,6}
  F.fence_types=types
  local dx={[0]=-1,0,1,0}
  local dz={[0]=0,1,0,-1}
  local function field(t) return t and t.kind=="clear" and t.ground=="field" end
  function F.suitable(t,allow_fields)
    return t~=nil and (
      t.kind=="clear" and t.ground~="snow" and t.ground~="desert" and (allow_fields or t.ground~="field") or
      t.kind=="trees" and t.ground~="shore")
  end
  function F.random(ind,b,rnd)
    local x=ind.x+floor(ind.width/2)+rnd()%31-16
    local z=ind.z+floor(ind.height/2)+rnd()%31-16
    -- Last row/column is always map void. In freeform mode the north
    -- edges are void as well. The stock target check discards wrapping.
    if x<0 or z<0 or x>=b.width-1 or z>=b.height-1 or
        b.freeform and (x==0 or z==0) then return 0 end
    return F.plant(b,x,z,ind.id,rnd)
  end
  function F.plant(b,x,z,industry,rnd)
    local w,h=b.width,b.height
    local n=rnd()
    local size_x,size_z=4+n%4,4+floor(n/256)%4
    x=x-min(x,floor(size_x/2));z=z-min(z,floor(size_z/2))
    size_x,size_z=min(size_x,w-x),min(size_z,h-z)
    if size_x==0 or size_z==0 then return 0 end
    local good=0
    for v=z,z+size_z-1 do for u=x,x+size_x-1 do
      if F.suitable(b.tile(u,v),false) then good=good+1 end
    end end
    if good*2<size_x*size_z then return 0 end
    n=rnd()
    local counter=floor(n/32)%8
    local field_type=floor((floor(n/256)%256)*9/256)
    local planted=0
    for v=z,z+size_z-1 do for u=x,x+size_x-1 do
      if F.suitable(b.tile(u,v),true) then
        b.make_field(u,v,field_type,industry,counter)
        planted=planted+1
      end
    end end
    local fence=types[rnd()%16+1]
    local function scan(u,v,amount,side)
      local flat=v*w+u
      local step=side%2==1 and 1 or w
      for _=1,amount do
        flat=flat%(w*h)
        local tx,tz=flat%w,floor(flat/w)
        local old=b.tile(tx,tz)
        if field(old) then
          local adjacent=flat+dx[side]+dz[side]*w
          local near=adjacent>=0 and adjacent<w*h and b.tile(adjacent%w,floor(adjacent/w)) or nil
          local reverse=(side+2)%4
          local existing=near and near.fences and near.fences[reverse] or 0
          if not field(near) or existing==0 then
            local style=fence
            if fence==1 and Commons.chance(7,rnd()) then style=2 end
            b.set_fence(tx,tz,side,style)
          end
        end
        flat=flat+step
      end
    end
    scan(x,z,size_z,0) -- DIAGDIR_NE
    scan(x,z,size_x,3) -- DIAGDIR_NW
    scan(x+size_x-1,z,size_z,2) -- DIAGDIR_SW
    scan(x,z+size_z-1,size_x,1) -- DIAGDIR_SE
    return planted,{x=x,z=z,w=size_x,h=size_z,field_type=field_type,counter=counter,fence=fence}
  end
  function F.on_built(ind,board,rnd)
    assert(ind.kind=="farm")
    local planted=0
    for _=1,50 do planted=planted+F.random(ind,board,rnd) end
    return planted
  end
  return F
end
