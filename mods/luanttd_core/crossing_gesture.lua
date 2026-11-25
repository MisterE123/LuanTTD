-- Translate the native pointer's tile into the ordinary crossing command.
-- The crossing runtime remains the sole authority for gates, occupancy,
-- ownership, reservation, geometry and the actual cost.
local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local Track=dofile(mod.."/openttd/rail_track.lua")
return function(Sim,s,id,railtype)
  local t=s.tiles[id]
  if t and t.level_crossing then return nil,"ALREADY_BUILT" end
  local tram=t and t.tram and t.tram.kind=="road" and t.tram
  if t and not t.rail_tracks and (t.build=="road" or not t.build and tram) then
    local available=Track.union(Sim.road_bits(s,id),tram and tram.tram_bits or 0)
    local track=({[1]=0,[4]=0,[5]=0,[2]=1,[8]=1,[10]=1})[available]
    if track~=nil then return {kind="rail",track=track,railtype=railtype} end
  elseif t and t.build=="stock_rail" and (t.rail_tracks==1 or t.rail_tracks==2) then
    return {kind="road",pieces=t.rail_tracks==1 and 5 or 10}
  end
  return nil,"NEEDS_PLAIN_ROAD_OR_RAIL"
end
