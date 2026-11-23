-- Shared assembly view of the real stock depot. No formspec or renderer.
local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local Roster=dofile(mod.."/openttd/rail_roster.lua")
local Help=dofile(mod.."/depot_vehicle_help.lua")
local Freight=dofile(mod.."/rail_freight_kinds.lua")
return function(S,owned)
  local A={}
  function A.read(n,id)
    local t=S.tiles[id]
    if not t or t.owner~=n or t.rail_depot_dir==nil then return nil,"Choose a rail depot you own." end
    local rows,revision=owned.loose_wagons(S,n,id)
    local units=owned.list(S,n,id)
    local cat,engines,wagons={}, {}, {}
    local function help(stock,id)
      local cargo=stock.railtype and stock.railtype>=2 and stock.cargo or Help.rail_cargo(id)
      local dmu=Roster.passenger_dmu(id)
      return Help.describe("rail",cargo,stock.name,{speed=stock.speed,capacity=dmu and stock.capacity*2 or stock.capacity},
        stock.kind=="wagon" and "wagon" or dmu and "dmu" or "engine")
    end
    for _,r in ipairs(owned.catalog(S) or {}) do
      cat[r.stock_id]=r
      if (r.kind=="wagon" and (r.stock_id==27 or r.stock_id==28 or Freight.wagons[r.stock_id]
        or r.railtype>=2 and r.visual and (r.cargo=="mail" or r.cargo=="passenger"))) or r.passenger_model_ready then
        local q=owned.quote_part(S,n,id,r.stock_id)
        if q then
          local target=r.kind=="wagon" and wagons or engines
          target[#target+1]={name=r.name,quote=q,id=r.stock_id,help=help(r,r.stock_id)}
        end
      end
    end
    local bodies,destinations,staged={}, {}, {}
    local function row(r,label)
      for i,part in ipairs(r.parts) do
        if part.role~="rear" then
          local stock=cat[part.stock_id] or {}
          local text=label.."  "..i..". "..(stock.name or ("#"..part.stock_id))
          local x={id=part.body_id,name=text,unit=r.status=="depot" and r.id or nil,help=help(stock,part.stock_id)}
          destinations[#destinations+1]=x
          if r.status=="loose" or i>1 then bodies[#bodies+1]=x end
        end
      end
    end
    for _,r in ipairs(units) do
      if r.status=="depot" then staged[r.id]=r;row(r,"Train "..r.unit_number.." ·") end
    end
    for i,r in ipairs(rows) do row(r,"Loose row "..i.." ·") end
    return {depot=id,revision=revision,engines=engines,wagons=wagons,bodies=bodies,destinations=destinations,staged=staged}
  end
  return A
end
