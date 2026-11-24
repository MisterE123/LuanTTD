-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 contributors: table/build_industry.h (_tile_table_oil_rig_0,
-- industry #5, GFX 24–28); industry_cmd.cpp (CheckNewIndustry_OilRig,
-- CheckIfIndustryTilesAreFree, MakeIndustryTileBigger, PopulateStationsNearby);
-- station_cmd.cpp (BuildOilRig); table/airport_{defaults,movement}.h (AT_OILRIG).
-- Pure stock rules. The campaign is responsible for atomic world/industry/
-- station writes; this file does not create gameplay objects on its own.
local R={}
local floor,max,abs=math.floor,math.max,math.abs
R.spec={id=5,life="extractive",built_on_water=true,after1960=true,
  ai_air_ship_routes=true,minimum=5,cost_factor=240,
  procurement_probability=0x99999999,climates=1,map_colour=152,
  out={"oil","passenger"},rates={15,2},input={},multiplier={},
  appearance={6,0,0,0},generation={0,0,0,0},conflict=4}
-- Preserve source traversal order: only the first six entries build
-- anything. The remaining 52 are flat water tests, not acquired terrain.
R.cells={{0,0,24},{0,1,24},{0,2,25},{1,0,26},{1,1,27},{1,2,28}}
local water={}
local function w(x,z) water[#water+1]={x,z} end
for z=-4,6 do w(-4,z) end
for x=-3,5 do w(x,6) end
for z=5,-4,-1 do w(5,z) end
for x=4,-3,-1 do w(x,-4) end
w(2,0);w(2,-1);w(1,-1);w(0,-1);w(-1,-1);w(-1,0);w(-1,1)
w(-1,2);w(-1,3);w(0,3);w(1,3);w(2,3);w(2,2);w(2,1)
R.water_checks=water

-- airport_movement.h: oil rig takes the heliport FTA and entries, but
-- has its own movement points (sixteenths of a tile, north rotation).
-- The terminal is on the next cell over, not at the station-tile center.
R.airport={airplanes=false,helicopters=true,depots=0,catchment=4,delta_z=54,
  entry={7,7,7,7},type="oilrig",rotation="north",moving={
    [0]={31,9,"exact_position","NE"},{28,9,"heli_raise","N"},
    {23,9,"unclamped_slow_turn","N"},{23,9,"heli_lower","N"},
    {28,9,"ground","N"},{-31,69,"unclamped_slow_turn","N"},
    {-31,-49,"unclamped_slow_turn","N"},{69,-49,"unclamped_slow_turn","N"},
    {69,9,"unclamped_slow_turn","N"},
  }}
function R.weight(context,opts)
  opts=opts or {}
  if opts.enabled==false or opts.landscape and opts.landscape~="temperate" then return 0 end
  if context=="mapgen" then return 0 end
  assert(context=="random","expected mapgen or random industry availability")
  if opts.fund_only or (opts.year or 1950)<1960 then return 0 end
  return R.spec.appearance[1]
end

function R.acceptance(gfx,cargo)
  -- ct1/amount1 and ct2/amount2 differ on the first two GFX values.
  if gfx==24 and cargo=="passenger" or gfx==25 and cargo=="mail" then return 8 end
  return 0
end

function R.edge(x,z,board,limit)
  -- CheckScaledDistanceFromEdge(TileAddXY(tile, 1, 1), limit).
  limit=limit or 32
  local near=board.freeform and 1 or 0
  local limit_x=limit*max(1,floor(board.width/256))
  local limit_z=limit*max(1,floor(board.height/256))
  return x+1-near<limit_x or z+1-near<limit_z or
    board.width-3-x<limit_x or board.height-3-z<limit_z
end

-- board.tile exposes source categories (a station with water_class
-- is still not an IsWaterTile); slope=0 encodes IsTileFlat. Board.clear
-- performs a dry-run LandscapeClear for proposed *built* tiles only.
-- WaterCheck cells do not call it and do not reject ships or bridges.
function R.quote(board,x,z,opts)
  opts=opts or {}
  if opts.landscape and opts.landscape~="temperate" then return nil,"OIL_RIG_CLIMATE" end
  local near=board.freeform and 1 or 0
  local function read(a,b)
    if a<near or b<near or a>board.width-2 or b>board.height-2 then return end
    return board.tile(a,b)
  end
  local start=read(x,z)
  if not start then return nil,"OIL_RIG_OFF_MAP" end
  for _,i in ipairs(board.industries or {}) do
    if i.type==R.spec.conflict and max(abs(x-i.x),abs(z-i.z))<=14 then
      return nil,"INDUSTRY_TOO_CLOSE"
    end
  end
  local cells={}
  for j,q in ipairs(R.cells) do
    local u,v=x+q[1],z+q[2]
    local t=read(u,v)
    if not t or t.vehicle or t.bridge or not t.water_class or not board.clear(u,v,t) then
      return nil,"OIL_RIG_FOOTPRINT_OBSTRUCTED"
    end
    cells[j]={x=u,z=v,gfx=q[3],water_class=t.water_class}
  end
  for _,q in ipairs(water) do
    local t=read(x+q[1],z+q[2])
    -- Industry special water-check tiles require plain, flat water in RC1.
    if not t or t.kind~="water" or t.slope~=0 or t.is_water_tile==false then return nil,"OIL_RIG_WATER_BUFFER" end
  end
  if not (opts.editor and opts.ignore_industry_restrictions) and
      (start.base~=0 or not R.edge(x,z,board,opts.oil_refinery_limit)) then
    return nil,"OIL_RIG_NEEDS_SEA_AT_EDGE"
  end
  for _,q in ipairs(cells) do
    if board.tile(q.x,q.z).slope~=0 then return nil,"OIL_RIG_FOOTPRINT_SLOPE" end
  end
  -- Town placement/name, duplicate type per town, cost and pool capacity
  -- use the same caller-side stock checks as the other industries.
  return {type=R.spec.id,x=x,z=z,cells=cells,width=2,height=3}
end

-- Source completion only needs this tile to be finished. It checks the
-- adjacent tile exists, has GFX 24, and belongs to the same industry;
-- neither cell need have a particular ordinal in a custom layout.
function R.completed_station(tile,neighbour,can_allocate)
  if not can_allocate or tile.kind~="industry" or tile.gfx~=24 or not tile.completed or
      not neighbour or neighbour.kind~="industry" or neighbour.gfx~=24 or
      tile.industry~=neighbour.industry then return end
  return {x=tile.x,z=tile.z,industry=tile.industry,water_class=tile.water_class,
    neutral=true,airport="oilrig",airport_rotation="north",dock=true}
end

-- The stock setting Serve neutral industries defaults to true. If it
-- is disabled a rig offers to its own neutral station exclusively.
function R.station_catchment(neutral_id,serve_neutral)
  if neutral_id~=nil and serve_neutral==false then return {neutral_id} end
end
function R.neutral_ref(s,st)
  if not st or not st.neutral or st.owner~=nil or not st.oil_rig then return end
  local key=(s.stock_neutral_stations or {})[st.id]
  if key and key.type=="oilrig" and key.industry==st.oil_rig then return key end
end
return R
