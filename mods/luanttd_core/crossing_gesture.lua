-- Translate the native pointer's tile into the ordinary crossing command.
-- The crossing runtime remains the sole authority for gates, occupancy,
-- ownership, reservation, geometry and the actual cost.
return function(Sim,s,id)
  local t=s.tiles[id]
  if t and t.level_crossing then return nil,"ALREADY_BUILT" end
  if t and t.build=="road" and not t.rail_tracks then
    local track=({[1]=0,[4]=0,[5]=0,[2]=1,[8]=1,[10]=1})[Sim.road_bits(s,id)]
    if track~=nil then return {kind="rail",track=track} end
  elseif t and t.build=="stock_rail" and (t.rail_tracks==1 or t.rail_tracks==2) then
    return {kind="road",pieces=t.rail_tracks==1 and 5 or 10}
  end
  return nil,"NEEDS_PLAIN_ROAD_OR_RAIL"
end
