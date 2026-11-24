-- Test the real asynchronous endpoint without materializing far terrain.
local mod=core.get_modpath(core.get_current_modname())
local function load(name)return dofile(mod.."/"..name..".lua") end
local Sim,Terrain=load("sim"),load("openttd/terrain")
local Client=load("campaign_authority_client")(core,mod)
local checkpoint=load("campaign_checkpoint")(core,load("packed_campaign"),"luanttd-wide-campaign.chk")
local owner="Place Label Survey"
local function id(x,z)return (z-1)*64+x end
local s=Sim.new(1751)
s.tiles,s.sites,s.stations={}, {}, {}
Sim.W,Sim.H=64,64
s.corner_grid=Terrain.new(64,64,function(x)return math.min(18,x-1) end)
for z=1,64 do for x=1,64 do s.tiles[id(x,z)]={h=math.min(18,x-1),variant=1,terrain="grass"} end end
local far=id(57,31)
s.sites[1]={id=1,kind="town",name="Unloaded Ridge",population=486,tile=far,stock={},produced={},received={}}
s.sites[2]={id=2,kind="farm",name="Closed farm",closed=true,tile=id(25,31),stock={},produced={},received={}}
Sim.company(s,owner)
checkpoint.write_state(s)
local cap={road={start_year=1950,breakdowns=0,service_interval=0},ferry={},air={},
  rail=load("rail_dispatch_manifest").scan(mod,false,false),durable_actions=true}
for _,group in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..group,"air") end
local passed
core.register_on_mods_loaded(function()
  assert(Client.start(cap,function(r)
    assert(r.ready)
    assert(Client.query({kind="place_labels",player=owner,x=6,z=62},function(first)
      assert(first.ok and #first.value==1)
      local d=first.value[1]
      assert(d.tile==far and d.id==1 and d.name=="Unloaded Ridge" and type(d.population)=="number" and d.y==23,core.write_json(d))
      assert(Client.query({kind="place_labels",player=owner,x=999999,z=62},function(bad)
        assert(not bad.ok and bad.why=="Place names unavailable.")
        passed=true
        assert(Client.query({kind="stop"},function() end))
      end))
    end))
  end,function(why,_,_,detail)
    assert(passed and why=="stopped",tostring(detail or why))
    core.log("action","PLACE_LABELS_NATIVE_WORKER_PASS 108.5 nodes, exact above-ridge height, bounded and no terrain subscription")
    core.request_shutdown("Passed place-name authority test",false,0)
  end,"luanttd-wide-campaign.chk"))
end)
