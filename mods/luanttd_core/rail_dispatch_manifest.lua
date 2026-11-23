-- Static capability scan. The engine/view only projects the resulting models.
local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local Freight=dofile(mod.."/rail_freight_kinds.lua")
local models={
  locomotive={mesh="bl_diesel.obj",atlas="bl_vehicle_palette.png",size={x=1,y=1,z=.54},offset=.612},
  steam={mesh="bl_rail_kirby_paul_tank.obj",atlas="bl_rail_kirby_paul_tank.png",size={x=1,y=1,z=1},offset=.614},
  jubilee={mesh="bl_rail_chaney_jubilee.obj",atlas="bl_rail_chaney_jubilee.png",size={x=1,y=1,z=1},offset=.614},
  ginzu={mesh="bl_rail_ginzu_a4.obj",atlas="bl_rail_ginzu_a4.png",size={x=1,y=1,z=1},offset=.614},
  sh_8p={mesh="bl_rail_sh_8p.obj",atlas="bl_rail_sh_8p.png",size={x=1,y=1,z=1},offset=.614},
  manley={mesh="bl_rail_manley_morel.obj",atlas="bl_rail_manley_morel.png",size={x=1,y=1,z=1},offset=.614},
  hendry={mesh="bl_rail_hendry_25.obj",atlas="bl_rail_hendry_25.png",size={x=1,y=1,z=1},offset=.614},
  uu37={mesh="bl_rail_uu_37.obj",atlas="bl_rail_uu_37.png",size={x=1,y=1,z=1},offset=.614},
  floss={mesh="bl_rail_floss_47.obj",atlas="bl_rail_floss_47.png",size={x=1,y=1,z=1},offset=.614},
  sh_125={mesh="bl_rail_sh_125.obj",atlas="bl_rail_sh_125.png",size={x=1,y=1,z=1},offset=.614},
  sh_30={mesh="bl_rail_sh_30.obj",atlas="bl_rail_sh_30.png",size={x=1,y=1,z=1},offset=.614},
  sh_40={mesh="bl_rail_sh_40.obj",atlas="bl_rail_sh_40.png",size={x=1,y=1,z=1},offset=.614},
  wagon={mesh="bl_rail_passenger_wagon.obj",atlas="bl_rail_wagon_atlas.png",size={x=1,y=1,z=1},offset=.614},
  coal_empty={mesh="bl_rail_coal_wagon_empty.obj",atlas="bl_rail_coal_wagon_atlas.png",size={x=1,y=1,z=1},offset=.614},
  coal_loaded={mesh="bl_rail_coal_wagon_loaded.obj",atlas="bl_rail_coal_wagon_atlas.png",size={x=1,y=1,z=1},offset=.614},
  goods_van={mesh="bl_rail_goods_van.obj",atlas="bl_rail_goods_van.png",size={x=1,y=1,z=1},offset=.614},
  oil_tanker={mesh="bl_rail_oil_tanker.obj",atlas="bl_rail_oil_tanker.png",size={x=1,y=1,z=1},offset=.614},
}
for _,p in pairs(Freight.profiles) do
  for _,suffix in ipairs(p.fixed_visual and {""} or {"_empty","_loaded"}) do
    local name=p.stem..suffix
    models[name]={mesh="bl_rail_"..name..".obj",atlas="bl_rail_"..p.stem.."_atlas.png",
      size={x=1,y=1,z=1},offset=.614,optional=true}
  end
end
local stock_kind={[0]="steam",[8]="jubilee",[9]="ginzu",[10]="sh_8p",[11]="manley",[13]="hendry",[14]="uu37",[15]="floss",[22]="sh_125",[23]="sh_30",[24]="sh_40"}
local stock_extra={jubilee=8,ginzu=9,sh_8p=10,manley=11,hendry=13,uu37=14,floss=15,sh_125=22,sh_30=23,sh_40=24}
local M={models=models,stock_kind=stock_kind}
function M.wagon(train,Sim,s)
  local id=train.stock_wagon
  if train.stock_engine==11 and not id then return "manley" end
  local cargo=Freight.wagons[id]
  if cargo=="oil" then return "oil_tanker" end
  if cargo=="goods" then return "goods_van" end
  local p=Freight.profiles[cargo]
  if p and p.fixed_visual then return p.stem end
  if cargo=="coal" or p then
    local get=Sim["rail_"..cargo.."_status"]
    local state=get and get(s)
    -- Stock RC1 GetTrainImage: the wagon's high sprite set only
    -- appears at >= half of physical cargo capacity.
    local loaded=state and (p and state.onboard>=math.floor(state.capacity/2) or not p and state.onboard>0)
    return (p and p.stem or "coal")..(loaded and "_loaded" or "_empty")
  end
  return "wagon"
end
function M.scan(path,electric,span)
  local function exists(file)
    local f=io.open(path.."/"..file,"rb")
    if not f then return false end
    f:close()
    return true
  end
  local art={ready={},split={},engines={}}
  for kind,d in pairs(models) do
    local id=stock_extra[kind]
    local optional=id or kind=="oil_tanker" or kind=="goods_van" or d.optional
    local available=not optional or path and exists("models/"..d.mesh) and exists("textures/"..d.atlas)
    if id==11 and available then available=exists("openttd/rail_multihead_loading.lua") end
    if id==23 or id==24 then available=available and electric==true end
    if available then
      art.ready[kind]=true
      if id then art.engines[#art.engines+1]=id end
    end
    if span and available and (id==23 or id==24) then
      local body=d.mesh:gsub("%.obj$","_body.obj")
      if exists("models/"..body) and exists("models/bl_rail_sh_collector.obj") then art.split[kind]=true end
    end
  end
  table.sort(art.engines)
  return art
end
return M
