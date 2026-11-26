-- Geometry and static presentation data for a bounded region. Built routes,
-- VM handles, station queues, finance, and unrelated tiles are not copied.
local keys={
  "terrain","variant","h","build","owner","wood","house","parcel","site",
  "road_bits","road_town","roadside","roadworks","road_disallowed","disallowed","road_stop_pair","stop_axis","depot_dir","road_terminal_level","road_waypoint_id","road_stop_type",
  "rail_tracks","rail_type","rail_ground","rail_depot_dir","rail_station_id","rail_station_axis","rail_station_gfx","rail_waypoint_id","rail_waypoint_axis",
  "rail_span_id","road_bridge_id","road_tunnel_id","station","signal","closed","level_crossing",
  "coastal_water","stock_void","stock_clear_ground","stock_clear_density","water_class","stock_canal","stock_river_bits","stock_water_rocks",
  "stock_industry","stock_landmark","stock_object","ship","airfield","tram","source_house",
}
local lift_motion={lift_position=true,lift_destination=true,lift_has_destination=true}
local function detached(value,depth,exclude)
  if type(value)=="table" and depth>0 then
    local out={}
    for k,v in pairs(value) do
      if (type(k)=="string" or type(k)=="number") and not (exclude and exclude[k]) then out[k]=detached(v,depth-1) end
    end
    return out
  end
  if type(value)=="boolean" or type(value)=="number" or type(value)=="string" then return value end
end
local M={}
function M.tile(real)
  local out={}
  for _,key in ipairs(keys) do out[key]=detached(real[key],2,key=="source_house" and lift_motion or nil) end
  return out
end
-- Compare exactly what tile() would transmit, without allocating detached
-- tables. Nested mutable records must still be checked even if the source
-- tile and topology revision both retained their identities.
local function same(actual,projected,depth,exclude)
  local kind=type(actual)
  if kind=="table" and depth>0 then
    if type(projected)~="table" then return false end
    for k,v in pairs(actual) do
      if (type(k)=="string" or type(k)=="number") and not (exclude and exclude[k])
          and not same(v,projected[k],depth-1) then
        return false
      end
    end
    for k in pairs(projected) do if actual[k]==nil then return false end end
    return true
  end
  if kind=="boolean" or kind=="number" or kind=="string" then return actual==projected end
  return projected==nil
end
function M.matches_tile(real,projected)
  if not projected then return false end
  for _,key in ipairs(keys) do
    local a,b=real[key],projected[key]
    if a~=b and not same(a,b,2,key=="source_house" and lift_motion or nil) then return false end
  end
  return true
end
function M.corners(terrain,grid,x,z,w,h)
  local rows={}
  for dz=0,h do
    local row={}
    for dx=0,w do row[dx+1]=string.char(assert(terrain.corner(grid,x+dx,z+dz))) end
    rows[dz+1]=table.concat(row)
  end
  return table.concat(rows)
end
local span_fields={"start","end","head","tail","middle","middle_by_tile","axis","owner","town","base","deck","bridge_type","railtype","kind","roadtype","tramtype","road_owner","tram_owner"}
local station_fields={"owner","id","tile","mode","name","tiles","tram_only","stop_axis","stop_type","bus_tile","truck_tile","freight_art","coal_art","coal_role","coal_stage_tile","coal_stage_mirror","oil_role","goods_role","iron_ore_role","steel_role","valuables_role","livestock_role","grain_role","wood_role"}
local industry_fields={"id","removed","kind","x","z","tiles","layout"}
local farm_fields={"variant","slope","base","fences"}
local site_fields={"id","kind","name","tile","closed","population"}
local port_fields={"owner","id","land","water","neutral","oil_rig","name"}
local airport_fields={"owner","id","origin","tiles","layout","neutral","oil_rig","name"}
local function add(out,s,name,id,fields)
  if id==nil then return end
  local source=s[name] and s[name][id]
  if not source then return end
  local dst=out[name] or {};out[name]=dst
  if dst[id] then return end
  if fields then
    local record={}
    for _,k in ipairs(fields) do record[k]=detached(source[k],3) end
    if name=="stock_coal_industries" and source.produced and source.produced.rate>0 then
      record.hoist_active=true
    end
    dst[id]=record
  else dst[id]=detached(source,2) end
end
local function reference(out,s,name,id)
  local v=s[name] and s[name][id]
  if v==nil then return end
  local dst=out[name] or {};out[name]=dst
  dst[id]=v
  return v
end
function M.registries(s,ids)
  local out={}
  for _,row in ipairs(ids) do
    local id=row.id
    local t=s.tiles[id]
    local above=reference(out,s,"bridge_above",id)
    local below=reference(out,s,"tunnel_below",id)
    local rail_above=reference(out,s,"rail_bridge_above",id)
    local rail_below=reference(out,s,"rail_tunnel_below",id)
    local aqueduct=reference(out,s,"aqueduct_above",id)
    add(out,s,"stock_road_bridges",t.road_bridge_id or above,span_fields)
    add(out,s,"stock_road_tunnels",t.road_tunnel_id or below,span_fields)
    add(out,s,"stock_rail_spans",t.rail_span_id or rail_above or rail_below,span_fields)
    add(out,s,"stock_aqueducts",aqueduct,span_fields)
    add(out,s,"sites",t.site,site_fields)
    add(out,s,"sites",t.road_town,site_fields)
    add(out,s,"stations",t.station,station_fields)
    add(out,s,"stations",t.tram and t.tram.tram_station,station_fields)
    add(out,s,"stock_road_waypoints",t.road_waypoint_id,{"id","name","owner","tile"})
    add(out,s,"stock_rail_stations",t.rail_station_id,station_fields)
    if t.ship and (t.ship.kind=="dock" or t.ship.kind=="oilrig") then
      add(out,s,"stock_ship_stations",t.ship.station,port_fields)
    end
    if t.airfield then
      add(out,s,"stock_small_airports",t.airfield.airport,airport_fields)
    end
    -- The visual scene changes only when the ground variant or actual
    -- fence geometry changes, not when the worker visits a field.
    add(out,s,"stock_farm_fields",id,farm_fields)
    if t.stock_industry then
      local chain=t.stock_industry.chain or "coal"
      add(out,s,"stock_"..chain.."_industries",t.stock_industry.id,industry_fields)
    end
    local d=s.stock_rail_dispatch
    if d and d.signals.records[id] then
      local signals=out.signals or {};out.signals=signals
      local proto=detached(d.signals.records[id],2)
      proto.green_signals=nil -- aspect changes are sent as actor data, not terrain repaint
      signals[id]=proto
    end
  end
  return out
end
return M
