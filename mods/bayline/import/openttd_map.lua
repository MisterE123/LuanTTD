-- Glue from tools/openttd_save_map.py to the canonical terrain grid.
-- Read-only preparation, not a player-facing world constructor. Nothing is
-- copied to the live campaign; entity pools and settings are not restored.
return function(Terrain)
  local M={}
  local function size_ok(n)
    if type(n)~="number" then return false end
    for k=6,12 do if n==2^k then return true end end
    return false
  end

  local function rows(hex,width,depth,upper)
    assert(type(hex)=="table" and #hex==depth,"wrong snapshot row count")
    local result={}
    for z=1,depth do
      local row=hex[z]
      assert(type(row)=="string" and #row==2*width,"wrong snapshot row width")
      local converted=string.gsub(row,"..",function(pair)
        assert(pair:match("^%x%x$"),"invalid snapshot hex pair")
        local value=tonumber(pair,16)
        assert(value<=upper,"invalid snapshot byte")
        return string.char(value)
      end)
      result[z]=converted
    end
    return result
  end

  function M.prepare(snapshot)
    assert(type(snapshot)=="table" and snapshot.schema=="luanttd-openttd-map/1"
      and snapshot.can_resume_in_luanti==false,"expected a map-only OpenTTD snapshot")
    local w,h=snapshot.width,snapshot.height
    assert(size_ok(w) and size_ok(h) and snapshot.tile_columns==w-1
      and snapshot.tile_rows==h-1,"invalid snapshot dimensions")
    assert(type(snapshot.freeform_edges)=="boolean","missing OpenTTD edge mode")
    local heights=rows(snapshot.corner_rows_hex,w,h,255)
    local tile_types=rows(snapshot.tile_type_rows_hex,w,h,10)
    for x=1,w do assert(tile_types[h]:byte(x)==7,"far border must be void") end
    for z=1,h do assert(tile_types[z]:byte(w)==7,"far border must be void") end
    for x=1,w-1 do
      assert((tile_types[1]:byte(x)==7)==snapshot.freeform_edges,"invalid near edge")
    end
    for z=2,h-1 do
      assert((tile_types[z]:byte(1)==7)==snapshot.freeform_edges,"invalid near edge")
    end

    -- Public coordinates use LuanTTD's 1-based indexing. The canonical
    -- grid retains the final row/col as real corners, not gameplay tiles.
    local grid=Terrain.new(w-1,h-1,function(x,z) return heights[z]:byte(x) end,
      {freeform_edges=snapshot.freeform_edges})
    local roads=snapshot.road_tiles
    assert(type(roads)=="table","missing road snapshot")
    for integral,record in pairs(roads) do
      local i=tonumber(integral)
      assert(type(integral)=="string" and i and i==math.floor(i) and i>=0 and i<w*h
        and tostring(i)==integral and type(record)=="table","invalid road tile record")
      local code=tile_types[math.floor(i/w)+1]:byte(i%w+1)
      assert(code==2 or code==5,"road record on non-road tile")
    end

    local function has_tile(x,z)
      return type(x)=="number" and type(z)=="number" and x==math.floor(x) and z==math.floor(z)
         and x>=1 and x<w and z>=1 and z<h
    end
    return {
      corner_grid=grid,
      tile_type=function(x,z) if has_tile(x,z) then return tile_types[z]:byte(x) end end,
      source_tile_id=function(x,z) if has_tile(x,z) then return (z-1)*w+x-1 end end,
      road_tile=function(x,z) if has_tile(x,z) then return roads[tostring((z-1)*w+x-1)] end end,
      can_resume_in_luanti=false,
    }
  end
  return M
end
