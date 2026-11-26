-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 elrail.cpp DrawRailCatenary, for one control point.
-- Caller supplies post-foundation adjusted slopes and rounded pixel Z.
return function(Track,A)
  local R={}
  function R.choose(edge,location,home,nbr,override)
    if override or home.no_pylons then return end
    local e=edge+1
    local rev=Track.reverse_side(edge)+1
    local eh=home.z
    if nbr and (eh~=nbr.z or nbr.mask_hidden) then nbr=nil end
    local enabled,preferred,allowed=false,255,A.allowed[e]
    for k=1,6 do
      local visiting=A.source[e][k]==1
      local t=visiting and nbr or not visiting and home
      if t and not (visiting and t.bridge_inside==rev-1) then
        local track=A.tracks[e][k]
        local pos=e
        if Track.has(t.wires,track) then
          pos=visiting and rev or e
          enabled=true
          preferred=Track.intersect(preferred,A.preferred[track+1][pos])
        end
        if Track.has(t.tracks,track) then
          allowed=Track.remove(allowed,A.blocked[track+1][pos])
        end
      end
    end
    if not enabled then return end
    local p=location+1
    local grade=nbr and nbr.grade or 0
    if home.grade==grade or home.tracks>=4 and nbr and nbr.tracks>=4 then
      for _,row in ipairs(A.ignored) do
        if preferred==row[p][e] then return end
      end
    end
    local pruned=Track.intersect(allowed,preferred)
    if pruned~=0 then allowed=pruned end
    for _,direction in ipairs(A.order[e][p]) do
      if Track.has(allowed,direction) then
        if Track.has(A.owned[e],direction) then return direction end
        if nbr and nbr.tracks~=0 then return end
      end
    end
  end
  function R.position(edge,dir)
    return A.pcp_x[edge+1]+A.ppp_x[dir+1],A.pcp_z[edge+1]+A.ppp_z[dir+1]
  end
  -- GetPCPElevation uses the closest inside pixel and rounds to the
  -- nearest half-height instead of consulting the far side's foundation.
  function R.elevation(edge,stock_z)
    local x,z=math.min(A.pcp_x[edge+1],15),math.min(A.pcp_z[edge+1],15)
    return math.floor((stock_z(x,z)+2)/4)*4
  end
  return R
end
