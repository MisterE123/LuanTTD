-- Original Blender/native assets. Logical layout and occupancy belong to
-- the farm source/host modules, not this packaging contract.
local A={}
A.footprints={
  industry_farm={{0,0},{0,1},{0,2},{1,0},{1,1},{1,2},{2,0},{2,1},{2,2}},
  industry_factory={{0,0},{0,1},{0,2},{0,3},{1,0},{1,1},{1,2},{1,3},{2,1},{2,2},{3,1},{3,2}},
}
A.slopes={0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30}
function A.missing(core,path)
  local names={}
  for _,sub in ipairs({"models","textures"}) do
    for _,name in ipairs(core.get_dir_list(path.."/"..sub,false)) do names[name]=true end
  end
  for style,parts in pairs(A.footprints) do
    if not names["bl_"..style.."_atlas.png"] then return style.." atlas" end
    for _,pos in ipairs(parts) do
      local mesh=("bl_%s_%d_%d.obj"):format(style,pos[1],pos[2])
      if not names[mesh] then return mesh end
    end
  end
  for _,x in ipairs({"bl_hereford_grain_truck.obj","bl_hereford_grain_truck_loaded.obj","bl_hereford_grain_truck_atlas.png",
      "bl_talbott_livestock_van.obj","bl_talbott_livestock_van_atlas.png","bl_balogh_goods_truck.obj",
      "bl_balogh_goods_truck_atlas.png","bl_farm_fence_atlas.png"}) do
    if not names[x] then return x end
  end
  for _,m in ipairs(A.slopes) do
    local x="bl_farm_land_"..m..".obj"
    if not names[x] then return x end
  end
  for i=0,8 do
    local x="bl_farm_field_"..i..".png"
    if not names[x] then return x end
  end
  if not names["bl_crop_growth_atlas.png"] then return "bl_crop_growth_atlas.png" end
  for i=2,8 do for _,suffix in ipairs({"","_patch"}) do
    local x=("bl_crop_growth_%d%s.obj"):format(i,suffix)
    if not names[x] then return x end
  end end
  for style=1,6 do for rise=0,1 do
    local x=("bl_farm_fence_%d_%d.obj"):format(style,rise)
    if not names[x] then return x end
  end end
end
return A
