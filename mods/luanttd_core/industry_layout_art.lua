-- Original alternate layout modules keyed by the pinned source GFX IDs.
-- The classic native layout-0 assets remain the coherent bespoke sites.
local A={atlas="stock_industry_layout_parts_atlas"}
local roles={0,2,3,4,5,6,7,8,9,10,11,12,13,14,15}
A.roles=roles
function A.asset(gfx) return ("industry_layout_gfx_%d"):format(gfx) end
function A.alternate(ref)
  return (ref.layout or 0)>0 and
    (ref.chain=="timber" and ref.kind=="sawmill" or ref.chain==nil and
      (ref.style:match("^coal_mine_l%d+$") or ref.style:match("^power_station_l%d+$"))) and A.asset(ref.gfx) or nil
end
function A.available(core,path)
  if not core.get_dir_list then return nil end
  local models,textures={},{}
  for _,filename in ipairs(core.get_dir_list(path.."/models",false)) do models[filename]=true end
  for _,filename in ipairs(core.get_dir_list(path.."/textures",false)) do textures[filename]=true end
  if not textures["bl_"..A.atlas..".png"] or not models["bl_industry_layout_hoist_wheels.obj"] then return nil end
  for _,role in ipairs(roles) do
    if not models["bl_"..A.asset(role)..".obj"] then return nil end
  end
  return {[0]={[1]=true,[2]=true,[3]=true},[1]={[1]=true,[2]=true},[2]={[1]=true}}
end
return A
