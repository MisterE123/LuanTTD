-- Translate the native tile records once at the terrain scene boundary.
-- Stock direction SW is local +x, SE is +z. The stock edge offsets
-- therefore already use the Luanti tile coordinates without rotation.
return function(Sim,S,tile,Rules)
  local M={}
  local void={kind="void"}
  local dry={kind="dry"}
  local function on_water(t,s)
    local cls=s and s.water_class or t.water_class
    return cls=="sea" or cls=="canal" or cls=="river"
  end
  local function describe(id)
    local t=id and S.tiles[id]
    if not id then return void end
    if not t then return dry end -- an unmounted projection is not a map border
    if t.stock_void then return void end
    local s=t.ship
    if s then
      if s.kind=="ship_depot" then return {kind="depot"} end
      if s.kind=="lock" or s.kind=="aqueduct" then return {kind=s.kind,dir=s.dir} end
      if s.kind=="dock" then return {kind="dock",slope=tile(id)} end
      if s.kind=="oilrig" then return {kind="oilrig",on_water=on_water(t,s)} end
      if s.kind=="buoy" then return {kind="buoy"} end
    end
    if t.stock_industry then
      local i=t.stock_industry
      return {kind="industry",industry=(i.chain or "coal")..":"..i.id,on_water=on_water(t)}
    end
    if t.stock_object or t.stock_landmark then return {kind="object",on_water=on_water(t)} end
    if t.rail_tracks then return t.rail_ground==13 and {kind="half_rail",slope=tile(id)} or dry end
    if t.coastal_water then return {kind=t.stock_water_rocks and "coast_rocks" or "coast",slope=tile(id)} end
    if t.terrain=="water" and not (t.road_bridge_id or t.road_tunnel_id or t.rail_span_id) then
      return {kind=t.stock_water_rocks and "water_rocks" or "clear_water"}
    end
    return dry
  end
  function M.has_dikes(t)
    if not t or t.stock_void or t.coastal_water then return false end
    -- DrawWaterLock draws its own structures, not DrawWaterClassGround.
    if t.ship then
      local k=t.ship.kind
      return (k=="buoy" or k=="ship_depot" or k=="dock" and t.ship.water_part or k=="oilrig")
        and t.ship.water_class=="canal"
    end
    if t.stock_industry then
      return t.stock_industry.kind=="rig" and t.water_class=="canal"
    end
    if t.stock_object or t.stock_landmark or t.rail_tracks then return false end
    return t.stock_canal==true or t.terrain=="water" and t.water_class=="canal"
  end
  function M.mask(id)
    if not M.has_dikes(S.tiles[id]) then return end
    local x,z=Sim.xy(id)
    local source=describe(id)
    return Rules.edges(function(dx,dz,from)
      return Rules.watered(describe(Sim.id(x+dx,z+dz)),from,source)
    end)
  end
  M.describe=describe
  return M
end
