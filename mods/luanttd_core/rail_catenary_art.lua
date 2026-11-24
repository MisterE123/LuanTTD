-- Native presentation selector; no track creation, power or pathfinding.
local A={
  atlas="bl_rail_catenary_atlas.png",
  above_flat_rail=.784,
  above_terrain=.898,
}
local edges={
  [1]={[0]=true,[2]=true}, [2]={[1]=true,[3]=true},
  [4]={[0]=true,[3]=true}, [8]={[1]=true,[2]=true},
  [16]={[2]=true,[3]=true}, [32]={[0]=true,[1]=true},
}
local grades={1,1,2,2}
local high_edge={[1]=2,[2]=0,[3]=1,[4]=3}
function A.supports(mask,grade,kind)
  grade=grade or 0
  if kind=="platform" then return grade==0 and (mask==1 or mask==2) end
  if kind~=nil and kind~="plain" then return false end
  return edges[mask]~=nil and (grade==0 or grades[grade]==mask)
end
function A.overlay(mask,grade,kind,x,z,force_mast,diagonal_mode)
  grade=grade or 0
  if not A.supports(mask,grade,kind) then return nil end
  -- Similar to stock's every-other-level-straight rule, not its full
  -- PPP/PCP arbitration. A section at the end of a short run can force
  -- a support. Suppression flags must not remove a platform roof.
  local axis_index=mask==1 and x or z
  local pole=kind~="platform" and
    (force_mast or grade~=0 or mask>2 or (axis_index or 0)%2==0)
  local suffix=grade~=0 and ("grade_"..grade) or tostring(mask)
  if kind~="platform" and grade==0 and mask>2 and diagonal_mode and diagonal_mode>0 then
    suffix=("eased_%d_%d"):format(mask,diagonal_mode)
    -- A regular mast rhythm down a continuous diagonal; retain a
    -- support where the contact wire bends into cardinal track.
    pole=force_mast or diagonal_mode~=3 or mask==4 or mask==16
  end
  local name="rail_catenary_"..suffix.."_"..(pole and "1" or "0")
  return {name=name,mesh="bl_"..name..".obj",texture=A.atlas,
          offset=grade~=0 and 3 or 2,pole=not not pole}
end
function A.wire_edge(mask,grade,edge,base)
  grade=grade or 0
  if not A.supports(mask,grade) or not edges[mask][edge] then return nil end
  return base+1.398+(grade~=0 and high_edge[grade]==edge and 1 or 0)
end
return A
