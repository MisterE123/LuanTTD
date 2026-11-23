-- Static capability scan. The engine/view only projects the resulting models.
local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local Freight=dofile(mod.."/rail_freight_kinds.lua")
local Roster=dofile(mod.."/openttd/rail_roster.lua")
local models={
  locomotive={mesh="bl_diesel.obj",atlas="bl_vehicle_palette.png",size={x=1,y=1,z=.54},offset=.612},
  steam={mesh="bl_rail_kirby_paul_tank.obj",atlas="bl_rail_kirby_paul_tank.png",size={x=1,y=1,z=1},offset=.614},
  jubilee={mesh="bl_rail_chaney_jubilee.obj",atlas="bl_rail_chaney_jubilee.png",size={x=1,y=1,z=1},offset=.614},
  ginzu={mesh="bl_rail_ginzu_a4.obj",atlas="bl_rail_ginzu_a4.png",size={x=1,y=1,z=1},offset=.614},
  sh_8p={mesh="bl_rail_sh_8p.obj",atlas="bl_rail_sh_8p.png",size={x=1,y=1,z=1},offset=.614},
  manley={mesh="bl_rail_manley_morel.obj",atlas="bl_rail_manley_morel.png",size={x=1,y=1,z=1},offset=.614},
  dash={mesh="bl_rail_dash.obj",atlas="bl_rail_dash.png",size={x=1,y=1,z=1},offset=.614},
  hendry={mesh="bl_rail_hendry_25.obj",atlas="bl_rail_hendry_25.png",size={x=1,y=1,z=1},offset=.614},
  uu37={mesh="bl_rail_uu_37.obj",atlas="bl_rail_uu_37.png",size={x=1,y=1,z=1},offset=.614},
  floss={mesh="bl_rail_floss_47.obj",atlas="bl_rail_floss_47.png",size={x=1,y=1,z=1},offset=.614},
  sh_125={mesh="bl_rail_sh_125.obj",atlas="bl_rail_sh_125.png",size={x=1,y=1,z=1},offset=.614},
  sh_30={mesh="bl_rail_sh_30.obj",atlas="bl_rail_sh_30.png",size={x=1,y=1,z=1},offset=.614},
  sh_40={mesh="bl_rail_sh_40.obj",atlas="bl_rail_sh_40.png",size={x=1,y=1,z=1},offset=.614},
  tim={mesh="bl_rail_tim.obj",atlas="bl_rail_tim.png",size={x=1,y=1,z=1},offset=.614},
  asiastar={mesh="bl_rail_asiastar.obj",atlas="bl_rail_asiastar.png",size={x=1,y=1,z=1},offset=.614},
  mail_van={mesh="bl_rail_mail_van.obj",atlas="bl_rail_mail_van.png",size={x=1,y=1,z=1},offset=.614,optional=true},
  wagon={mesh="bl_rail_passenger_wagon.obj",atlas="bl_rail_wagon_atlas.png",size={x=1,y=1,z=1},offset=.614},
  x2001={mesh="bl_rail_x2001.obj",atlas="bl_rail_x2001.png",size={x=1,y=1,z=1},offset=.746,bogies=true,optional=true},
  mono_passenger={mesh="bl_rail_mono_passenger.obj",atlas="bl_rail_mono_passenger.png",size={x=1,y=1,z=1},offset=.746,bogies=true,optional=true},
  mono_mail={mesh="bl_rail_mono_mail.obj",atlas="bl_rail_mono_mail.png",size={x=1,y=1,z=1},offset=.746,bogies=true,optional=true},
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
local stock_kind={[0]="steam",[8]="jubilee",[9]="ginzu",[10]="sh_8p",[11]="manley",[12]="dash",[13]="hendry",[14]="uu37",[15]="floss",[22]="sh_125",[23]="sh_30",[24]="sh_40",[25]="tim",[26]="asiastar",[54]="x2001"}
local stock_extra={jubilee=8,ginzu=9,sh_8p=10,manley=11,dash=12,hendry=13,uu37=14,floss=15,sh_125=22,sh_30=23,sh_40=24,tim=25,asiastar=26}
local M={models=models,stock_kind=stock_kind}
function M.wagon(train,Sim,s)
  if train.town_parts then
    local models={}
    for _,part in ipairs(train.town_parts) do
      if part.stock==27 then models[part.index]="wagon"
      elseif part.stock==28 then models[part.index]="mail_van"
      elseif part.stock==57 then models[part.index]="mono_passenger"
      elseif part.stock==58 then models[part.index]="mono_mail" end
    end
    return models
  end
  if train.freight_parts then
    local profile=assert(Freight.profiles[train.freight.cargo])
    local models={}
    for i,part in ipairs(train.freight_parts) do
      local n=train.freight_counts and train.freight_counts[i] or 0
      local order=assert(Roster.entry(part.stock))
      models[part.index]=profile.fixed_visual and profile.stem or
        profile.stem..(n>=math.floor(order.capacity/2) and "_loaded" or "_empty")
    end
    return models
  end
  local id=train.stock_wagon
  if Roster.passenger_dmu(train.stock_engine) and not id then return stock_kind[train.stock_engine] end
  if id==28 then return "mail_van" end
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
    local f=path and io.open(path.."/"..file,"rb")
    if not f then return false end
    f:close()
    return true
  end
  local art={ready={},split={},engines={}}
  for kind,d in pairs(models) do
    local id=stock_extra[kind]
    local optional=id or kind=="oil_tanker" or kind=="goods_van" or d.optional
    local available=not optional or path and exists("models/"..d.mesh) and exists("textures/"..d.atlas)
    if Roster.passenger_dmu(id) and available then available=exists("openttd/rail_multihead_loading.lua") end
    if Roster.electric_engine(id) then available=available and electric==true end
    if available then
      art.ready[kind]=true
      if id then art.engines[#art.engines+1]=id end
    end
    if span and available and Roster.electric_engine(id) then
      local body=d.mesh:gsub("%.obj$","_body.obj")
      if exists("models/"..body) and exists("models/bl_rail_sh_collector.obj") then art.split[kind]=true end
    end
  end
  -- Expose mixed service only for real, renderable stock bodies. Keep the
  -- older mandatory-ready defaults for unrelated existing rendering paths.
  local function has_model(kind)
    local d=models[kind]
    return art.ready[kind] and exists("models/"..d.mesh) and exists("textures/"..d.atlas)
  end
  art.mixed_town_engines={}
  if art.ready.mail_van and has_model("wagon") then
    for id,kind in pairs(stock_kind) do
      if Roster.entry(id).railtype<2 and Roster.freight_engine(id) and has_model(kind) then art.mixed_town_engines[id]=true end
    end
  end
  art.advanced={}
  if has_model("x2001") and has_model("mono_passenger") and has_model("mono_mail")
      and exists("models/bl_rail_x2001_body.obj") and exists("models/bl_rail_mono_bogie.obj")
      and exists("models/bl_rail_mono_drawbar.obj")
      and exists("models/bl_rail_mono_passenger_body.obj") and exists("models/bl_rail_mono_mail_body.obj")
      and exists("models/bl_guideway_mono_flat_1.obj") and exists("textures/bl_guideway_mono_atlas.png")
      and exists("models/bl_guideway_mono_depot_1.obj") and exists("textures/bl_guideway_mono_facility_atlas.png") then
    art.advanced={[54]=true,[57]=true,[58]=true}
  end
  if art.advanced[54] and exists("textures/bl_guideway_mono_span.png") then
    local complete=true
    for kind,n in pairs({span=1,head_flat=3,head_ramp=3,tunnel=3}) do
      for i=0,n do
        local stem="models/bl_guideway_mono_span_"..kind.."_"..i
        complete=complete and exists(stem..".obj") and (kind~="span" or exists(stem.."_road_clear.obj"))
      end
    end
    art.advanced_span=complete
  end
  table.sort(art.engines)
  return art
end
return M
