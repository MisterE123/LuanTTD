-- Machine-readable list of the assets the runtime art selector can request.
local p="mods/luanttd_core/"
local C=dofile(p.."stock_town_construction_art.lua")(
  dofile(p.."openttd/stock_town_draw_rows.lua"),dofile(p.."stock_town_art.lua"))
local names,files={},C.files()
for name in pairs(files) do names[#names+1]=name end
table.sort(names)
for _,name in ipairs(names) do
  local a=files[name]
  print(("%s %d %d %d %d %d %d"):format(name,a.id,a.slot,a.stage,a.ground,a.upper,a.look))
end
