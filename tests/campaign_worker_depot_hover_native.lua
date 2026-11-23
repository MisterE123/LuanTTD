-- Minimal graphical fixture using the real production formspec. Native
-- pointer movement alone must reveal the unselected row's specific help.
local mod=core.get_modpath(core.get_current_modname())
local Help=dofile(mod.."/depot_vehicle_help.lua")
local oil=Help.describe("road","oil","Witcombe Oil Tanker",{capacity=21,speed=48})
local bus=Help.describe("road","passenger","MPS Regal Bus",{capacity=31,speed=56})
local data={
  offers={
    {name="MPS Regal Bus",price=3500,help=bus,request={kind="road_buy",engine="bus"}},
    {name="Witcombe Oil Tanker",price=6000,help=oil,request={kind="road_buy",engine="oil_tanker"}},
  },
  vehicles={{id=1,label="Bus 1",help=bus},{id=2,label="Oil Truck 2",help=oil}},
}
local client={query=function(req,cb)
  assert(req.kind=="depot","hover or selection must never send a purchase")
  cb({ok=true,value=data,revision=1});return true
end}
local D=dofile(mod.."/campaign_worker_depot_ui.lua")(core,client,{},function(n)return "$"..n end)
for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
core.register_on_joinplayer(function(p)
  core.after(1,function()
    D.open(p,"road",1)
    core.log("action","NATIVE DEPOT HOVER READY")
  end)
end)
core.register_on_player_receive_fields(function(p,name,fields)
  if name~=D.form then return end
  for k in pairs(fields) do
    if k:match("_row[12]$") then core.log("action","NATIVE DEPOT ROW "..k) end
  end
  return D.fields(p,fields)
end)
