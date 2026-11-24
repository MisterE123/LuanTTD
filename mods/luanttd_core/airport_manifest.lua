-- Resolve capabilities on the host, not in the economy tick or view.
return function(core,mod)
  local files={}
  for _,subdir in ipairs({"models","textures"}) do
    for _,filename in ipairs(core.get_dir_list(mod.."/"..subdir,false)) do files[filename]=true end
  end
  local assets={}
  for _,art in pairs(dofile(mod.."/airport_airframe_art.lua")) do
    if files[art.mesh] and files[art.atlas] and (not art.flight or files[art.flight])
        and (not art.rotor or (files[art.rotor] and files[art.tail_rotor])) then
      assets[art.id]=art
    end
  end
  local city=files["bl_city_airport_atlas.png"] and files["bl_dispatch_city_airport.png"]
  for z=0,5 do for x=0,5 do
    city=city and files[("bl_city_airport_%d_%d.obj"):format(x,z)]
  end end
  local heliport=files["bl_heliport_0_0.obj"] and files["bl_heliport_atlas.png"] and files["bl_dispatch_heliport.png"]
  local ground={}
  if files["bl_dispatch_rotary_airfields.png"] then
    for name,width in pairs({helidepot=2,helistation=4}) do
      local ready=files["bl_"..name.."_atlas.png"] and files["bl_dispatch_"..name..".png"]
      for z=0,1 do for x=0,width-1 do ready=ready and files[("bl_%s_%d_%d.obj"):format(name,x,z)] end end
      ground[name]=not not ready
    end
  end
  local data=dofile(mod.."/openttd/airport_expansion_data.lua")
  local art=dofile(mod.."/airport_metropolitan_art.lua")
  local expansion={}
  for _,name in ipairs({"metropolitan","commuter"}) do
    expansion[name]=not not files["bl_dispatch_"..name.."_airport.png"] and not art(data[name],name).missing(files)
  end
  return assets,not not city,not not heliport,ground,expansion
end
