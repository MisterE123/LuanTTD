-- Asset manifest: no model placeholders and no optional gameplay switch.
-- For fresh world generation either both original footprints are usable
-- or the heavy industry types are not selected by the stock generator.
local M={}
function M.ready(core,path,world)
  local files={}
  if core.get_dir_list then
    for _,part in ipairs({"models","textures"}) do
      for _,file in ipairs(core.get_dir_list(path.."/"..part,false)) do files[part.."/"..file]=true end
    end
  end
  local function present(name)
    if files[name] then return true end
    if core.get_dir_list then return false end
    local f=io.open(path.."/"..name,"rb")
    if not f then return false end
    f:close()
    return true
  end
  for style,parts in pairs(world.visual_sources()) do
    if not present("textures/bl_"..style.."_atlas.png") then return false end
    for _,t in ipairs(parts) do
      if not present(("models/bl_%s_%d_%d.obj"):format(style,t[1],t[2])) then return false end
    end
  end
  return true
end
return M
