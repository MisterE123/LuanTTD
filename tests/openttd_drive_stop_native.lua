-- SPDX-License-Identifier: GPL-2.0-only
-- Closed OpenTTD 14.1 station_cmd.cpp through-road site and price adapter.
-- The production road-stop UI has independent campaign pricing.
local path=core.get_modpath(core.get_current_modname())
local function load(n) return dofile(path.."/"..n..".lua") end
local file=assert(io.open(path.."/input.json","rb"))
local spec=assert(core.parse_json(file:read("*a")));file:close()
local T=load("terrain")
local I=load("openttd_map")(T)
local R=load("yapf_road_follow")
local S=load("road_slope")
local Prices=load("road_bridge")(S)

local function quote(q)
  assert(q.schema=="luanttd-drive-stop-input/1" and q.site==44385 and q.front==44386
    and q.owner==0 and q.road_type==0 and q.platform=="drive_stop" and q.stop_type=="bus"
    and q.new_station==true and q.requested_tile_count==1 and not q.occupied and not q.roadworks
    and q.inflation==65536 and q.snapshot.source.sha256==q.source_sha256
    and q.snapshot.width==256 and q.snapshot.height==256 and q.no_existing_join==true)
  local map=I.prepare(q.snapshot)
  local x,z=q.site%256+1,math.floor(q.site/256)+1
  local r=assert(map.road_tile(x,z))
  local ground,base=T.tile(map.corner_grid,x,z)
  assert(map.source_tile_id(x+1,z)==q.front and ground==0 and base==1
    and r.kind=="road" and r.road_bits==10 and r.disallowed==0
    and r.road_type==q.road_type and r.road_owner==q.owner
    and #r.unsupported_for_initial_bus_world==0 and r.tram_type==nil)
  local west,east=assert(map.road_tile(x-1,z)),assert(map.road_tile(x+1,z))
  local function bit(b,v) return math.floor(b/v)%2==1 end
  assert(west.road_type==0 and bit(west.road_bits,2) and east.road_type==0 and bit(east.road_bits,8))
  local before={kind="road",roadtype=0,road_bits=10}
  local after={kind="drive_stop",roadtype=0,road_bits=10,axis=0,dir=0}
  local status=R.status(before,false)
  assert(status==R.status(after,false) and R.has_trackdir(status,0) and R.has_trackdir(status,8))
  -- Base PR_BUILD_STATION_BUS is 200 in table/pricebase.h. A level plain
  -- road already has both stock pieces so no foundation, demolition or
  -- new pavement charge applies (CheckFlatLandRoadStop).
  local factor=assert(({[0]=6,8,9})[q.construction_difficulty])
  local base_price=math.floor(200*factor/8)
  local piece_price=math.floor(Prices.road_build_cost(0)*factor/8)
  local added_road=0
  assert(q.cash>=base_price+added_road*piece_price)
  return {schema="luanttd-drive-stop-quote/1",source_sha256=q.source_sha256,
    source_tick=q.source_tick,site=q.site,front=q.front,owner=q.owner,station_type="bus",
    station_site_is_new=true,axis=0,road_bits=10,cost=base_price+added_road*piece_price,
    facility_cost=base_price,new_road_pieces=added_road}
end

local function copy(t)
  if type(t)~="table" then return t end
  local r={}
  for k,v in pairs(t) do r[k]=copy(v) end
  return r
end
local result=quote(spec)
local failed=0
for _,mutate in ipairs({
  function(q) q.owner=1 end,
  function(q) q.front=q.front+256 end,
  function(q) q.requested_tile_count=2 end,
  function(q) q.occupied=true end,
  function(q) q.roadworks=true end,
  function(q) q.no_existing_join=false end,
  function(q) q.snapshot.road_tiles[tostring(q.site)].road_bits=7 end,
  function(q) q.snapshot.road_tiles[tostring(q.site)].disallowed=1 end,
  function(q) q.cash=0 end,
}) do
  local q=copy(spec);mutate(q);assert(not pcall(quote,q),"unsupported station accepted");failed=failed+1
end
result.rejected_lab_inputs=failed
local body=assert(core.write_json(result))
core.log("action","LuanTTD stock drive-through quote "..assert(core.write_json({body=body,sha256=core.sha256(body)})))
core.register_on_mods_loaded(function()
  core.after(.05,function() core.request_shutdown("private stop quote complete",false,0) end)
end)
