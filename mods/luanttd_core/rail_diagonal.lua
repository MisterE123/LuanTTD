-- Presentation only: an alternating pair of OpenTTD's short tracks can
-- represent one straight 45-degree line. Retain its tile-edge midpoints
-- and choose smooth visual tangents only where another complementary
-- plain piece on the same railhead (including a slope foundation)
-- actually continues the line.
return function(Sim,Track,terrain,surface,split_surface)
  local D={}
  local displacements={[0]={-1,0},{0,1},{1,0},{0,-1}}
  local by_mask={[4]={0,3,8},[8]={2,1,4},[16]={2,3,32},[32]={0,1,16}}
  local pairs_by_mask={[12]={4,8},[48]={16,32}}
  local sqrt2=math.sqrt(2)
  local function plain(tile)
    return tile and not (tile.rail_station_id or tile.rail_depot_dir~=nil or tile.rail_waypoint_id
      or tile.rail_span_id or tile.level_crossing)
  end
  local function railhead(id,tile,bits)
    if not plain(tile) or not by_mask[bits] then return end
    -- Ordinary and electric pairs share the authored two-track
    -- geometry; unsupported guideway pairs retain stock curves.
    local pair=(tile.rail_type or 0)<2 and pairs_by_mask[tile.rail_tracks]
    local independent=tile.rail_tracks==bits or pair and (pair[1]==bits or pair[2]==bits)
    if not independent then return end
    if not terrain then return tile.h end
    local shape,base=terrain.tile(id)
    do
      if not surface then return shape==0 and base or nil end
      local grade,level=surface(shape,base,tile.rail_tracks)
      if grade~=nil then return grade==0 and level or nil end
    end
    if split_surface and (tile.rail_type or 0)==0 then
      local split=split_surface(shape,base,tile.rail_tracks)
      if not split then return end
      -- A diagonally opposed half can be joined on its own elevation.
      -- Never ease a combined junction or crossover on a shared bed.
      for level,group in pairs(split.groups) do
        if group==bits then return level end
      end
    end
  end
  function D.mode(s,id,bits)
    local tile=s.tiles[id]
    bits=bits or (tile and tile.rail_tracks)
    local ports=by_mask[bits]
    if not ports then return 0 end
    local level=railhead(id,tile,bits)
    if level==nil then return 0 end
    local x,z=Sim.xy(id)
    local mode=0
    for i=1,2 do
      local side=displacements[ports[i]]
      local next_id=Sim.id(x+side[1],z+side[2])
      local other=next_id and s.tiles[next_id]
      if other and other.owner==tile.owner and (other.rail_type or 0)==(tile.rail_type or 0)
          and railhead(next_id,other,ports[3])==level then mode=mode+2^(i-1) end
    end
    return mode
  end
  function D.dual_variant(s,id,mask)
    local pair=pairs_by_mask[mask]
    if not pair then return end
    local first,second=D.mode(s,id,pair[1]),D.mode(s,id,pair[2])
    if first+second>0 then return ("%d_%d_%d"):format(mask,first,second) end
  end
  function D.sample(td,t,mode)
    local ports=by_mask[2^Track.track(td)]
    if not ports or mode==0 then return end
    local side=Track.entry_side(td)
    local reverse=side~=ports[1]
    if reverse then t=1-t end
    local sign=reverse and -1 or 1
    local a,b=displacements[ports[1]],displacements[ports[2]]
    local x,z=b[1]-a[1],b[2]-a[2]
    local lead=.5/sqrt2
    local begin=mode%2==1 and lead or 0
    local finish=mode>=2 and 1-lead or 1
    if mode==3 or t<=begin and mode%2==1 or t>=finish and mode>=2 then
      return a[1]+t*x,a[2]+t*z,sign*x/sqrt2,sign*z/sqrt2
    end
    -- Keep the half-unit around each diagonal port truly straight so
    -- the mesh profile and adjacent port have identical cross-sections.
    -- The rest is the same cubic projected by the Blender mesh author.
    local t0x,t0z=-a[1],-a[2]
    local t1x,t1z=b[1],b[2]
    if begin>0 then t0x,t0z=x/sqrt2,z/sqrt2 end
    if finish<1 then t1x,t1z=x/sqrt2,z/sqrt2 end
    local ax,az=a[1]+begin*x,a[2]+begin*z
    local bx,bz=a[1]+finish*x,a[2]+finish*z
    local h=.55*(finish-begin)
    local cx,cz=ax+h*t0x,az+h*t0z
    local qx,qz=bx-h*t1x,bz-h*t1z
    local v=(t-begin)/(finish-begin)
    local u=1-v
    local u2,v2=u*u,v*v
    local dx=u2*(cx-ax)+2*u*v*(qx-cx)+v2*(bx-qx)
    local dz=u2*(cz-az)+2*u*v*(qz-cz)+v2*(bz-qz)
    local length=math.sqrt(dx*dx+dz*dz)
    return u2*u*ax+3*u2*v*cx+3*u*v2*qx+v2*v*bx,
      u2*u*az+3*u2*v*cz+3*u*v2*qz+v2*v*bz,sign*dx/length,sign*dz/length
  end
  return D
end
