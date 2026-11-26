-- Read-only daily lookup for the road-only house station contest.
-- Keep the original day's catalog and candidate order. Do not use the
-- station sign as the bounds for a multi-tile or joined road stop.
local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local sector=dofile(mod.."/catchment_sectors.lua")
return function(Sim,stops,modified_radius)
  local index,topology,radius_setting,width,height
  return function(s,x,z,area)
    if not index or topology~=s.topology or radius_setting~=s.stock_modified_catchment or
        width~=Sim.W or height~=Sim.H then
      topology,radius_setting,width,height=s.topology,s.stock_modified_catchment,Sim.W,Sim.H
      index=sector(width,height)
      local radius=radius_setting==false and 4 or modified_radius
      for _,st in ipairs(stops) do
        if s.stations[st.id]==st then
          local box
          for _,tile in ipairs(Sim.road_stop_tiles(st)) do
            local x,z=tile.x,tile.y
            if not box then box={left=x-radius,right=x+radius,top=z-radius,bottom=z+radius}
            else
              box.left,box.right=math.min(box.left,x-radius),math.max(box.right,x+radius)
              box.top,box.bottom=math.min(box.top,z-radius),math.max(box.bottom,z+radius)
            end
          end
          if box then index.add(box,st) end
        end
      end
    end
    return index.query(x,z,area)
  end
end
