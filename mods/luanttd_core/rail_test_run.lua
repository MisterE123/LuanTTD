-- Trackworks model proving run. One locomotive on a surveyed route, no
-- stations, cargo, train ownership/finances, PBS or service scheduling.
-- The timing distance is counted from actual stock subcoordinate steps;
-- the visual projection follows our authored real rail arcs between seams.
return function(Track,Motion,Speed,Sim)
  local R={}
  local function piece_steps(route,index)
    local record=route[index]
    local x,z=Sim.xy(record.tile)
    local pose=assert(Motion.entry_trackdir(x,z,record.td))
    local distance=0
    local cursor=0
    repeat
      local next_piece=route[index+1]
      local event,p=Motion.step(pose,next_piece and next_piece.td)
      if event=="invalid" then return end
      distance=distance+Speed.advance_distance(pose.direction)
      cursor=cursor+1
      if event=="enter" then
        if Sim.id(p.tx,p.ty)~=next_piece.tile then return end
        return distance,cursor
      elseif event=="boundary" then
        if next_piece then return end
        return distance,cursor
      end
      pose=p
    until cursor>=20
  end
  function R.compile(route)
    local from=0
    local segments={}
    for index,record in ipairs(route) do
      local distance=piece_steps(route,index)
      if not distance then return end
      segments[#segments+1]={tile=record.tile,td=record.td,start=from,span=distance}
      from=from+distance
    end
    if #segments<2 then return end
    return segments,from
  end
  function R.at(courses,units)
    for _,p in ipairs(courses) do
      if units<=p.start+p.span then return p.tile,p.td,(units-p.start)/p.span end
    end
    local t=courses[#courses]
    return t.tile,t.td,1
  end
  return R
end
