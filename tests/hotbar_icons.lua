-- Check mounted menus, including alternative entries not enabled together.
local hotbar = "mods/luanttd_core/hotbar.lua"
local textures = "mods/luanttd_core/textures/"
local identities, owners, pixels = {}, {}, {}
local total = 0
local function inspect(H)
  for menu, slots in pairs(H.menus) do
    for i=1,H.size do
      local entry = slots[i]
      if entry then
        local id, asset = entry[1], entry[3]
        local where = menu.."["..i.."] / "..id
        assert(type(asset)=="string" and asset:match("^bl_dispatch_[a-z_]+%.png$"), where)
        assert(not identities[id] or identities[id]==asset, where.." changed icon across menus")
        assert(not owners[asset] or owners[asset]==id, where.." reuses "..asset.." from "..tostring(owners[asset]))
        if not identities[id] then
          local f = assert(io.open(textures..asset,"rb"), where.." has no asset")
          local image = f:read("*a")
          f:close()
          assert(image:sub(1,8)=="\137PNG\r\n\26\n", where.." is not a PNG")
          assert(not pixels[image], where.." reuses the same PNG as "..tostring(pixels[image]))
          identities[id], owners[asset], pixels[image] = asset, id, id
          total=total+1
        end
      end
    end
  end
end

local plain = dofile(hotbar)
inspect(plain)
for _,picker in ipairs({false,true}) do
  for _,spans in ipairs({false,true}) do
    for _,crossings in ipairs({false,true}) do
      for _,owned in ipairs({false,true}) do
        local H = dofile(hotbar)
        H.enable_structures(picker)
        H.enable_trams()
        H.enable_ships()
        inspect(H) -- ferry before the vessel operations label changes
        H.enable_ship_coal()
        H.enable_airfields(owned)
        H.enable_oneway()
        H.enable_freight()
        H.enable_railworks(spans,crossings,picker)
        inspect(H) -- engineering route and standalone Roadside bus stop
        H.enable_electric_rail()
        H.enable_rail_pair()
        H.enable_rail_block()
        H.enable_bay_termini()
        H.enable_rail_coal()
        H.enable_rail_goods()
        inspect(H) -- Goods before Oil overrides its profile slots
        H.enable_rail_oil()
        inspect(H)
      end
    end
  end
end
assert(total>=60, "hotbar coverage unexpectedly small")
print(("PASS: %d semantic hotbar IDs each have one distinct existing PNG; aliases keep their action icon"):format(total))
