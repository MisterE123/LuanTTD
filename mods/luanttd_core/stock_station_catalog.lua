-- SPDX-License-Identifier: GPL-2.0-only
-- World-facing StationID and tile lookup for RC1 construction commands.
-- A local facility number is never used as a physical StationID.
return function(Sim)
  local M={}
  local Joined=Sim.stock_joined_station
  local function enclosing(cells)
    local ax,az,bx,bz=math.huge,math.huge,-1,-1
    for _,c in ipairs(cells) do
      ax,az,bx,bz=math.min(ax,c.x),math.min(az,c.y),math.max(bx,c.x),math.max(bz,c.y)
    end
    if bx>=0 then return {tile=Sim.id(ax+1,az+1),w=bx-ax+1,h=bz-az+1} end
  end

  function M.board(s)
    local catalog={}
    local function include(target,area)
      if not area then return end
      local prior=target.spread
      if not prior then target.spread=area;return end
      local x,y=Sim.xy(prior.tile)
      local u,v=Sim.xy(area.tile)
      local a,b=math.min(x,u),math.min(y,v)
      target.spread={tile=Sim.id(a,b),w=math.max(x+prior.w,u+area.w)-a,h=math.max(y+prior.h,v+area.h)-b}
    end
    local function register(mode,host,row)
      local id=row and row.stock_station_id
      if id==nil or row.neutral then return end
      local group=Joined.resolve(s,id,mode,host,row)
      local target=catalog[id]
      if not target then target={id=id,owner=row.owner};catalog[id]=target
      elseif not group or group~=target.group then error("Conflicting airport join StationID") end
      target.group=group
      if mode=="road" then
        target.road,target.name=host,row.name
        include(target,enclosing(Sim.road_stop_tiles(row)))
        target.bus_only=Sim.road_stop_has(row,"bus") and not Sim.road_stop_has(row,"truck") and not row.tram_only
      elseif mode=="air" or mode=="rail" or mode=="dock" then
        target[mode=="air" and "airport" or mode]=host
        local cells={}
        local function add(cell)
          local x,y=Sim.xy(cell);cells[#cells+1]={x=x-1,y=y-1}
        end
        if mode=="dock" then
          for _,dock in ipairs(row.docks or {row}) do add(dock.land);add(dock.water) end
        else
          for _,tile in ipairs(row.tiles or {}) do add(type(tile)=="table" and tile.id or tile) end
        end
        include(target,enclosing(cells))
      end
      return target
    end
    for host,row in pairs(s.stations or {}) do
      if row.mode=="road" then register("road",host,row) end
    end
    for host,row in pairs(s.stock_small_airports or {}) do register("air",host,row) end
    for host,row in pairs(s.stock_rail_stations or {}) do register("rail",host,row) end
    for host,row in pairs(s.stock_ship_stations or {}) do register("dock",host,row) end
    local function at(cell)
      local t=s.tiles[cell]
      if not t then return end
      local st
      local road=t.station or t.tram and t.tram.tram_station
      if road then st=(s.stations or {})[road]
      elseif t.airfield then st=(s.stock_small_airports or {})[t.airfield.airport]
      elseif t.rail_station_id and not t.rail_waypoint_id then st=(s.stock_rail_stations or {})[t.rail_station_id]
      elseif t.ship and t.ship.kind=="dock" then st=(s.stock_ship_stations or {})[t.ship.station] end
      return st and st.stock_station_id~=nil and catalog[st.stock_station_id] or nil
    end
    return {xy=Sim.xy,id=Sim.id,station_at=at,
      station=function(id) return catalog[id] end,matches=function() return true end}
  end
  M.enclosing=enclosing
  return M
end
