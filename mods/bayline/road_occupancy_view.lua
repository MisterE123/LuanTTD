-- SPDX-License-Identifier: GPL-2.0-only
-- Bridge actual live stock road poses to RoadStop::Entry / YAPF costs.
-- The supported live road fleet is unarticulated (cached length 8).
-- Through-stop storage can be reconstructed exactly from front poses;
-- the atomic bay entrance itself still uses the saved controller bits.
return function(Sim,s)
  local lengths={}
  for _,v in pairs(s.fleet) do
    local engine=Sim.vehicles[v.engine]
    if engine and engine.mode=="road" and not (v.depot or v.crashed) then
      local f=Sim.road_motion_frame(s,v)
      local row=f and f[6]
      local t=f and s.tiles[f[4]]
      if row and row>=64 and row<80 and t and t.build=="road_station" and t.station then
        local axis=t.stop_axis or Sim.road_bits(s,f[4])
        if axis==5 or axis==10 then
          local length=lengths[f[4]]
          if not length then length={};lengths[f[4]]=length end
          local dir=math.floor(f[3]/2)
          length[dir]=(length[dir] or 0)+8
        end
      end
    end
  end
  local bays=s.stock_road_bays and s.stock_road_bays.stops
  return {
    drive_length=function(id,direction)
      local v=lengths[id]
      return v and v[direction] or 0
    end,
    bay_taken=function(id,bay)
      local v=bays and bays[id]
      return v and math.floor(v.status/2^bay)%2==0 or false
    end,
  }
end
