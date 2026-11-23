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
  return assets
end
