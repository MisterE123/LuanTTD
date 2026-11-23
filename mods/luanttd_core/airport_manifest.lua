-- Resolve capabilities on the host, not in the economy tick or view.
return function(core,mod)
  local files={}
  for _,subdir in ipairs({"models","textures"}) do
    for _,filename in ipairs(core.get_dir_list(mod.."/"..subdir,false)) do files[filename]=true end
  end
  local assets={}
  for _,art in pairs(dofile(mod.."/airport_airframe_art.lua")) do
    if files[art.mesh] and files[art.atlas] and (not art.flight or files[art.flight]) then
      assets[art.id]=art
    end
  end
  local city=files["bl_city_airport_atlas.png"] and files["bl_dispatch_city_airport.png"]
  for z=0,5 do for x=0,5 do
    city=city and files[("bl_city_airport_%d_%d.obj"):format(x,z)]
  end end
  return assets,not not city
end
