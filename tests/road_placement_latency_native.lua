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
local coast=core.settings:get_bool("luanttd_coast_road",false)
s.corner_grid=T.new(64,64,function(x)return (not coast or x>12 and (x<=25 or x>=31)) and 1 or 0 end)
s.tiles,s.sites={},{}
for i=1,4096 do
  local x=(i-1)%64+1
  local water=coast and (x<=12 or x>=25 and x<=30)
  s.tiles[i]={terrain=water and "water" or "grass",variant=1,h=water and 0 or 1,
    water_class=water and "sea" or nil,coastal_water=coast and (x==12 or x==25 or x==30) or nil}
end
s.road_stock_clock,s.road_economy=true,true
s.speed=0
Sim.company(s,owner).cash=1000000
local cp=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-wide-campaign.chk")
local receipts,projection={},{}
local remove=core.settings:get_bool("luanttd_bench_remove",false)
local shore={tool="bend",first=id(12,8),last=id(15,13)}
local sea={tool="bend",first=id(11,8),last=id(15,13)}
local coast_run="preview"
local quote,bridge_quote
local a,b,middle=id(25,8),id(30,8),id(27,8)
local bridge={mode="road",operation="bridge",tile=a,last=b,style=0}
local function coastal(view)
  local t=view.terrain(12,8)
  if not t then return end
  if coast_run=="preview" then
    assert(t.surface.coastal_water==true and t.ground=="water")
    local q,why,pending=Build.preview(owner,"road",shore,core.get_us_time())
    if pending then return end
    assert(q,why);assert(#q.tiles==9 and q.cost>240)
    quote=q
    coast_run="placing"
    assert(Build.commit(owner,"road",shore,function(ok,note,prior,tiles)
      assert(ok,note)
      assert(prior.ticket==quote.ticket and #tiles==#q.tiles)
      coast_run="projected"
    end))
  elseif coast_run=="projected" and t.build=="road" then
    assert(t.ground=="grass" and not t.surface.coastal_water and not t.water)
    assert(view.terrain(11,8).ground=="water")
    coast_run="blocking"
    assert(Build.commit(owner,"road",sea,function(ok,why)
      assert(not ok and tostring(why):find("bridge over open water",1,true),why)
      local state=assert(cp.read())
      assert(state.companies[owner].cash==1000000-quote.cost)
      assert(state.tiles[id(12,8)].build=="road" and not state.tiles[id(12,8)].coastal_water)
      assert(state.tiles[id(11,8)].terrain=="water" and not state.tiles[id(11,8)].build)
      coast_run="bridge_placing"
      assert(Build.commit(owner,"transport",bridge,function(ok,note,prior,result)
        assert(ok,note)
        assert(result.deck==1 and #result.tiles==6)
        bridge_quote=prior
        coast_run="bridge_projected"
      end))
    end))
  elseif coast_run=="bridge_projected" then
    local first,last=view.terrain(25,8),view.terrain(30,8)
    if not first or not last or first.build~="stock_road_bridge" or last.build~="stock_road_bridge" then return end
    assert(first.ground=="grass" and last.ground=="grass")
    assert(not first.surface.coastal_water and not last.surface.coastal_water)
    assert(view.terrain(27,8).ground=="water")
    local state=assert(cp.read())
    assert(state.companies[owner].cash==1000000-quote.cost-bridge_quote.cost)
    assert(state.tiles[a].road_bridge_id==state.tiles[b].road_bridge_id)
    assert(state.bridge_above[middle] and state.tiles[middle].terrain=="water")
    core.log("action","ROAD_PLACEMENT_NATIVE_PASS mode=coast bend and bank-to-bank bridge: priced receipts, projection, and saved state match; real sea rejected")
    core.request_shutdown("Coast road and bridge verified.",false,0)
  end
end
local finish_seen
if remove then
  for k=1,8 do
    local z=23+k
    assert(Sim.autoroad_build(s,owner,id(8,z),id(52,z),0,false,true))
  end
end
local function median(values)
  table.sort(values)
  return (values[4]+values[5])*.5
end
local function place()
  trial=trial+1
  if trial>8 then
    if remove then
      local reopened=assert(cp.read())
      assert(reopened.companies[owner].cash==finish_seen)
      for k=1,8 do
        for x=8,52 do assert(reopened.tiles[id(x,23+k)].build==nil) end
      end
    end
    core.log("action",("ROAD_PLACEMENT_NATIVE_PASS mode=%s receipt=%.2fms projection=%.2fms"):format(
      remove and "remove" or "build",median(receipts)/1000,median(projection)/1000))
    core.request_shutdown("Road timing complete.",false,0)
    return
  end
  local z=23+trial
  local first,last=id(8,z),id(52,z)
  running={z=z,start=core.get_us_time()}
  local q={tool=remove and "remove" or "drag",first=first,last=last,axis=0,start_half=false,end_half=true}
  local prior=remove and assert(cp.read()).companies[owner].cash
  assert(Build.commit(owner,"road",q,function(ok,why,_,tiles)
    assert(ok,why)
    assert(#tiles==45,"wrong number of edited road tiles")
    if remove then
      finish_seen=assert(cp.read()).companies[owner].cash
      assert(finish_seen==prior-3520, ("cash %d to %d: %s"):format(prior,finish_seen,why))
    end
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
    if coast then coastal(view);return end
    if trial==0 and view.terrain(8,24) then
      trial=-1
      core.after(.031,function()trial=0;place()end)
    elseif running and trial>0 then
      local first=view.terrain(8,running.z)
      local last=view.terrain(52,running.z)
      local expected=not remove and "road" or nil
      if first and last and first.build==expected and last.build==expected then
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
  H.step(dt,{{name=owner,x=coast and 24 or 64,y=4,z=coast and 24 or 64}},1)
end)
