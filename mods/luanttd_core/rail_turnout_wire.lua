-- Ported RC1 wire selection, independent of scene-interest boundaries.
-- The physical support on these two-piece turnouts is native Luanti art.
return function(Sim,Track,Kernel)
  local A={}
  A.masks={5,6,9,10,17,18,20,24,33,34,36,40}
  local present={}
  for _,mask in ipairs(A.masks) do present[mask]=true end
  function A.supported(mask) return present[mask]==true end
  function A.at(s,id,t)
    if not (t and t.rail_type==1 and A.supported(t.rail_tracks)) then return end
    local board={
      adjacent=function(i,d) return Sim.adjacent(i,4-d) end,
      rail=function(i)
        local n=i and s.tiles[i]
        if not n then return end
        if n.rail_type==1 and n.rail_tracks then
          return {catenary=true,trackbits=n.rail_tracks,axis=n.rail_station_axis,
            station_wires=n.rail_station_id~=nil}
        end
        if n.level_crossing and n.level_crossing.railtype==1 then
          return {catenary=true,trackbits=n.rail_tracks or n.level_crossing.rail_tracks}
        end
        local p=n.rail_span_id and s.stock_rail_spans and s.stock_rail_spans[n.rail_span_id]
        if p and p.railtype==1 then return {catenary=true,trackbits=2^p.axis} end
      end,
    }
    return Kernel.at(board,id,t.rail_tracks,not (t.rail_station_id or t.rail_waypoint_id or t.rail_depot_dir~=nil))
  end
  return A
end
