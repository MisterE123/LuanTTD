-- Loaded in an isolated Luanti world by tests/openttd_save_map.py.
local path=core.get_modpath(core.get_current_modname())
local function json(name)
  local file=assert(io.open(path.."/"..name,"rb"))
  local bytes=file:read("*a")
  file:close()
  return assert(core.parse_json(bytes))
end
local T=dofile(path.."/terrain.lua")
local M=dofile(path.."/openttd_map.lua")(T)
local data=json("snapshot.json")
local stage=M.prepare(data)
local w,h=data.width,data.height
assert(w==256 and h==256 and not stage.can_resume_in_luanti)
assert(stage.corner_grid.width==w-1 and stage.corner_grid.depth==h-1)
assert(type(T.corner(stage.corner_grid,w,h))=="number"
  and stage.tile_type(w,h)==nil and stage.source_tile_id(w-1,h-1)==(h-2)*w+w-2)
for _,point in ipairs(json("official.json")) do
  local tag,values=point[1],point[2]
  local tile=values[1]
  local x,z=tile%w+1,math.floor(tile/w)+1
  assert(stage.source_tile_id(x,z)==tile)
  if tag=="SLOPE" then
    local slope,h=T.tile(stage.corner_grid,x,z)
    assert(h==values[2] and slope==values[3],"upstream shared-corner geometry mismatch")
  elseif tag=="DEPOT" then
    local road=stage.road_tile(x,z)
    assert(stage.tile_type(x,z)==2 and road.kind=="depot" and road.depot_id==0)
  elseif tag=="BAY" or tag=="THROUGH" then
    local road=stage.road_tile(x,z)
    assert(stage.tile_type(x,z)==5 and road.station_id==values[tag=="BAY" and 3 or 2])
  end
end
local invalid_key
for key in pairs(data.road_tiles) do invalid_key=key;break end
assert(invalid_key)
data.road_tiles[tostring(w*h-1)]=data.road_tiles[invalid_key]
assert(not pcall(M.prepare,data),"accepted road tile on the void border")
core.log("action","LuanTTD OpenTTD map adapter PASS")
core.after(0,function() core.request_shutdown("fixture complete",false,0) end)
