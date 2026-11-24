-- The real campaign worker owns a priced road gesture; measure from release
-- to receipt and to the host's normal 32x32-sector presentation refresh.
local path=core.get_modpath(core.get_current_modname())
local function m(name) return dofile(path.."/"..name..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local H,Build
local owner="Road Timing"
local step,trial,running=0,0,nil
local id=function(x,z) return (z-1)*64+x end
local s=Sim.new(1751)
Sim.W,Sim.H=64,64
s.corner_grid=T.new(64,64,function()return 1 end)
s.tiles,s.sites={},{}
for i=1,4096 do s.tiles[i]={terrain="grass",variant=1,h=1} end
s.road_stock_clock,s.road_economy=true,true
s.speed=0
Sim.company(s,owner).cash=1000000
local cp=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-wide-campaign.chk")
local receipts,projection={},{}
local function median(values)
  table.sort(values)
  return (values[4]+values[5])*.5
end
local function place()
  trial=trial+1
  if trial>8 then
    core.log("action",("ROAD_PLACEMENT_NATIVE_PASS receipt=%.2fms projection=%.2fms"):format(
      median(receipts)/1000,median(projection)/1000))
    core.request_shutdown("Road timing complete.",false,0)
    return
  end
  local z=23+trial
  local first,last=id(8,z),id(52,z)
  running={z=z,start=core.get_us_time()}
  local q={tool="drag",first=first,last=last,axis=0,start_half=false,end_half=true}
  assert(Build.commit(owner,"road",q,function(ok,why,_,tiles)
    assert(ok,why)
    assert(#tiles==45,"wrong number of painted road tiles")
    receipts[#receipts+1]=core.get_us_time()-running.start
  end))
end
H=m("campaign_authority_host")(core,path,{
  freeze_host=function()end,
  seal_checkpoint=function()cp.write_state(s);return "luanttd-wide-campaign.chk"end,
  ready=function()
    Build=m("campaign_build_proxy")(H)
  end,
  stopped=function(why,_,_,detail) error(tostring(detail or why)) end,
  present=function(view,motion)
    if motion or not Build then return end
    if trial==0 and view.terrain(8,24) then
      trial=-1
      core.after(.031,function()trial=0;place()end)
    elseif running and trial>0 then
      local first=view.terrain(8,running.z)
      local last=view.terrain(52,running.z)
      if first and last and first.build=="road" and last.build=="road" then
        projection[#projection+1]=core.get_us_time()-running.start
        running=nil
        core.after(.031,place)
      end
    end
  end,
})
for _,group in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..group,"air") end
core.register_on_mods_loaded(function()
  assert(H.start({road={start_year=1950,breakdowns=0,service_interval=0},autoplay=false,durable_actions=true},64,64))
end)
core.register_globalstep(function(dt)
  H.step(dt,{{name=owner,x=64,y=4,z=64}},1)
end)
