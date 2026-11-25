-- Original alternate layout modules keyed by the pinned source GFX IDs.
-- The classic native layout-0 assets remain the coherent bespoke sites.
local A={atlas="stock_industry_layout_parts_atlas"}
local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local FarmFactory=dofile(mod.."/openttd/farm_factory_industry.lua")
local Farm=FarmFactory()
local Oil=dofile(mod.."/openttd/oil_industry.lua")(FarmFactory)
local Timber=dofile(mod.."/openttd/timber_industry.lua")()
A.farm_footprint={industry_farm_l1=Farm.layout.farm[1],industry_farm_l2=Farm.layout.farm[2],
  industry_factory_l1=Farm.layout.factory[1]}
local farm_parts={}
for style,plan in pairs(A.farm_footprint) do
  if style:match("^industry_farm_l") then
    farm_parts[style]={}
    for _,cell in ipairs(plan) do farm_parts[style][cell[1]*16+cell[2]]=cell[3] end
  end
end
local blocks_from={{0,0},{0,2},{2,1}}
local blocks_to={{0,0},{2,0},{1,2}}
function A.farm_asset(style,x,z)
  local parts=farm_parts[style]
  if parts then
    return ("farm_alt_gfx_%d"):format(assert(parts[x*16+z])),"stock_farm_alternate_atlas"
  end
  if style=="industry_factory_l1" then
    for i,b in ipairs(blocks_to) do
      local dx,dz=x-b[1],z-b[2]
      if dx>=0 and dx<=1 and dz>=0 and dz<=1 then
        local from=blocks_from[i]
        return ("industry_factory_%d_%d"):format(from[1]+dx,from[2]+dz),"industry_factory_atlas"
      end
    end
    error("Missing stock factory block")
  end
  return ("%s_%d_%d"):format(style,x,z),style.."_atlas"
end
-- Approximate collision extents in the model coordinate frame. Low
-- gutters and foliage are intentionally left unobstructed.
local pen={{-.40,-.50,-.38,1.39,-.273,-.285},{-.40,-.50,-.38,-.315,-.273,1.37},
  {1.305,-.50,-.38,1.39,-.273,1.37},{-.40,-.50,1.28,1.39,-.273,1.37}}
local farm_solids={
  [33]={{-.31,-.5,-.22,1.04,.31,1.20}},
  [34]={{-.19,-.5,-.11,1.16,.25,1.08}},
  [35]={{-.22,-.5,-.17,1.19,.11,1.01}},
  [36]={{-.08,-.5,.05,.34,.90,.49},{.56,-.5,.10,.99,.74,.52}},
  [38]=pen,
}
function A.farm_collision(style,gfx)
  if style=="industry_farm_l1" or style=="industry_farm_l2" then return farm_solids[gfx] end
end
local roles={0,2,3,4,5,6,7,8,9,10,11,12,13,14,15}
A.roles=roles
function A.asset(gfx) return ("industry_layout_gfx_%d"):format(gfx) end
function A.alternate(ref)
  return (ref.layout or 0)>0 and
    (ref.chain=="timber" and ref.kind=="sawmill" or ref.chain==nil and
      (ref.style:match("^coal_mine_l%d+$") or ref.style:match("^power_station_l%d+$"))) and A.asset(ref.gfx) or nil
end
function A.available(core,path)
  if not core or not core.get_dir_list then return nil end
  local models,textures={},{}
  for _,filename in ipairs(core.get_dir_list(path.."/models",false)) do models[filename]=true end
  for _,filename in ipairs(core.get_dir_list(path.."/textures",false)) do textures[filename]=true end
  local out={}
  if textures["bl_"..A.atlas..".png"] and models["bl_industry_layout_hoist_wheels.obj"] then
    local ready=true
    for _,role in ipairs(roles) do
      if not models["bl_"..A.asset(role)..".obj"] then ready=false;break end
    end
    if ready then out={[0]={[1]=true,[2]=true,[3]=true},[1]={[1]=true,[2]=true},[2]={[1]=true}} end
  end
  local wells=textures["bl_industry_oil_well_atlas.png"]
  for _,position in ipairs({"0_0","1_0","2_0","0_1","0_2"}) do
    wells=wells and models["bl_industry_oil_well_"..position..".obj"]
  end
  if wells then out[11]={[1]=true} end
  local function complete(style,layout,map)
    for _,c in ipairs(layout) do
      local mesh,atlas
      if map then mesh,atlas=map(style,c[1],c[2])
      else mesh,atlas=("%s_%d_%d"):format(style,c[1],c[2]),style.."_atlas" end
      if not models["bl_"..mesh..".obj"] or not textures["bl_"..atlas..".png"] then return false end
    end
    return true
  end
  if complete("forest_1",Timber.layout.forest[1],function(style,x,z)
    return ("%s_%d_%d"):format(style,x,z),"forest_atlas"
  end) then out[3]={[1]=true} end
  if complete("industry_factory_l1",Farm.layout.factory[1],A.farm_asset) then out[6]={[1]=true} end
  for i=1,2 do
    if complete("industry_farm_l"..i,Farm.layout.farm[i],A.farm_asset) then
      out[9]=out[9] or {}
      out[9][i]=true
    end
  end
  if complete("industry_oil_refinery_l1",Oil.layout.oil_refinery[1]) then out[4]={[1]=true} end
  return next(out) and out or nil
end
return A
