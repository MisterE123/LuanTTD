-- RC1 world boundary for distributed compound rail supports.
-- All candidates use the actual neighbor wire mask (including its
-- outer approach), not the complete physical rail configuration.
return function(Sim,Track,Kernel,Wire,terrain)
  local M={}
  local function placement(s,id,t)
    if not (id and t and t.build=="stock_rail" and t.rail_type==1 and t.rail_tracks and t.rail_tracks>0 and not t.stock_void) or
        t.rail_station_id or t.rail_depot_dir~=nil or t.rail_waypoint_id or
        t.level_crossing or t.rail_span_id or t.signal or Sim.bridge_deck_at(s,id) then return end
    local dispatch=s.stock_rail_dispatch
    if dispatch and dispatch.signals and dispatch.signals.records and dispatch.signals.records[id] then return end
    local slope,height=terrain.tile(id)
    if slope~=0 then
      if Track.foundation(slope,t.rail_tracks)~="leveled" then return end
      height=height+1
    end
    return {tracks=t.rail_tracks,wires=Wire.at(s,id,t) or t.rail_tracks,z=height*8,grade=0}
  end
  function M.at(s,id,t)
    local home=placement(s,id,t)
    if not home then return end
    local x,z=Sim.xy(id)
    local group=(x-1)%2*2+(z-1)%2
    local out={}
    for edge=0,3 do
      local next_id=Sim.adjacent(id,4-edge)
      local next_tile=next_id and s.tiles[next_id]
      local other=placement(s,next_id,next_tile)
      if next_tile and (next_tile.level_crossing or next_tile.rail_span_id or next_tile.rail_type==1 and not other) then
        return nil,"UNSUPPORTED_NEIGHBOR"
      end
      if other and other.z~=home.z then return nil,"UNEQUAL_APPROACH" end
      local dir=Kernel.choose(edge,group,home,other)
      if dir~=nil then
        local px,pz=Kernel.position(edge,dir)
        out[#out+1]={edge=edge,dir=dir,x=px,z=pz,h=home.z/8}
      end
    end
    return out
  end
  return M
end
