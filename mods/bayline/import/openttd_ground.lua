-- The optional read-only ground sidecar, only for render profiles.
-- OpenTTD 14.1 src/water_map.h class/subtype port is in the extractor.
local M={}
local floor=math.floor
local function int(v,lo,hi) return type(v)=="number" and v>=lo and v<=hi and v==floor(v) end
function M.prepare(data,base)
  assert(type(data)=="table" and data.schema=="luanttd-openttd-ground/1"
    and (data.save_version==333 or data.save_version==334)
    and data.source_sha256==base.source_sha256,"ground sidecar does not match source provenance")
  local w,h=base.source_width,base.source_depth
  assert(data.width==w and data.height==h and type(data.water_rows_hex)=="table"
    and #data.water_rows_hex==h,"wrong ground sidecar dimensions")
  local rows={}
  local source=base.new_world()
  for z=1,h do
    local encoded=data.water_rows_hex[z]
    assert(type(encoded)=="string" and #encoded==2*w,"wrong ground sidecar row width")
    local row=encoded:gsub("..",function(pair)
      assert(pair:match("^0[0-5]$"),"invalid ground sidecar byte")
      return string.char(tonumber(pair,16))
    end)
    for x=1,w do
      local v=row:byte(x)
      if v~=0 then
        local terrain_class=source.tile(x,z)
        assert((v==3 and terrain_class==4) or (v~=3 and terrain_class==6),"ground sidecar disagrees with source tile class")
      elseif x<w and z<h then
        assert(source.tile(x,z)~=6,"ground sidecar is missing a source water tile")
      end
    end
    rows[z]=row
  end
  return function(x,z)
    if int(x,1,w-1) and int(z,1,h-1) then return rows[z]:byte(x) end
  end
end
return M
