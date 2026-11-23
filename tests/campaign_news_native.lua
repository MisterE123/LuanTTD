-- Graphical formspec fixture for real Luanti input, isolated from the
-- generated-campaign worker event integration tested separately.
local mod=core.get_modpath(core.get_current_modname())
local read
local row={seq=1,kind="new_vehicles",style="vehicle",year=1965,month=5,day=1,economy=20,icon="road",
  headline="Road vehicle now available: Hereford Leopard Bus",
  body="The Hereford Leopard Bus is now available to all companies. Check the appropriate depot to buy it."}
local function query(q,done)
  assert(q.kind=="news" and q.player=="NewsQA")
  if q.after then read=true;done({ok=true,value={items={row},cursor=1,economy=20}})
  elseif q.action=="last" then done({ok=true,value={article=row}})
  else done({ok=true,value={items={row},count=1}}) end
  return true
end
local U=dofile(mod.."/campaign_news_ui.lua")(core,mod,{query=query},
  function(y,m,d) return ("%02d MAY %d"):format(d,y) end)
for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
core.register_on_joinplayer(function(p)
  p:set_physics_override({gravity=0,speed=0,jump=0})
  p:set_pos({x=0,y=10,z=0})
  p:set_inventory_formspec("formspec_version[7]size[7,3]label[.4,.5;Control desk]button[.4,1.2;6.2,.65;bl_newspaper;Newspaper]")
  core.after(1,function()
    U.observe(p,{news_head=1,world_day=20})
    assert(read)
    core.log("action","NATIVE NEWSPAPER BULLETIN")
  end)
end)
core.register_on_player_receive_fields(function(p,name,f)
  if name=="" and f.bl_newspaper then
    core.log("action","NATIVE NEWSPAPER HISTORY");return U.open(p)
  elseif name==U.form then
    if f.read_1 then core.log("action","NATIVE NEWSPAPER ARTICLE") end
    if f.close then core.log("action","NATIVE NEWSPAPER CLOSED") end
    return U.fields(p,f)
  end
end)
