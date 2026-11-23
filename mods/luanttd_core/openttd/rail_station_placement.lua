-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 rail_gui.cpp PlaceRail_Station/HandleStationPlacement,
-- viewport.cpp VPM_X_AND_Y_LIMITED, and gui/game station settings.
-- Converts the screen selection into the real BuildRailStation arguments.
local P={spread=12,default={axis=0,drag=true,tracks=1,length=5}}
local min,max=math.min,math.max
local function integer(v,a,b) return type(v)=="number" and v%1==0 and v>=a and v<=b end
function P.layout(axis,drag,tracks,length,separate)
  if not integer(axis,0,1) or type(drag)~="boolean" or
      not integer(tracks,1,7) or not integer(length,1,7) then return nil end
  return {axis=axis,drag=drag,tracks=tracks,length=length,separate=not not separate}
end
function P.bounds(x,z,u,v,layout,spread)
  spread=spread or P.spread
  if layout.drag then
    u,v=max(x-spread+1,min(x+spread-1,u)),max(z-spread+1,min(z+spread-1,v))
  else
    u,v=x+(layout.axis==0 and layout.length or layout.tracks)-1,
      z+(layout.axis==0 and layout.tracks or layout.length)-1
  end
  local w,h=math.abs(x-u)+1,math.abs(z-v)+1
  local tracks,length=w,h
  if layout.axis==0 then tracks,length=h,w end
  return {x=min(x,u),z=min(z,v),w=w,h=h,axis=layout.axis,tracks=tracks,length=length}
end
-- station_cmd.cpp FindJoiningBaseStation / GetStationAround. Overlap
-- names the station directly. Otherwise expand the rectangle by one in
-- every direction and allow only one existing owned station.
function P.find_join(area,owner,existing,separate,station_at)
  if existing then
    if separate then return nil,"Cannot build a separate station on an existing platform." end
    return existing
  end
  if separate then return nil end
  local closest
  for row=area.z-1,area.z+area.h do
    for col=area.x-1,area.x+area.w do
      local st=station_at(col,row)
      if st and st.owner==owner then
        if closest and closest.id~=st.id then return nil,"Adjoins more than one existing station." end
        closest=st
      end
    end
  end
  return closest
end
function P.combined(a,b)
  local x,z=min(a.x,b.x),min(a.z,b.z)
  return {x=x,z=z,w=max(a.x+a.w,b.x+b.w)-x,h=max(a.z+a.h,b.z+b.h)-z}
end
return P
