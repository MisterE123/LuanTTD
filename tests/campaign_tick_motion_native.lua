-- Real generated-stock worker protocol, using controlled transparent
-- geometry so all four paid transport modes can be observed each time.
local mod=core.get_modpath(core.get_current_modname())
if not core.get_player_by_name then return end
for _,alias in ipairs({"mapgen_stone","mapgen_water_source","mapgen_river_water_source"}) do
  core.register_alias(alias,"air")
end
local codec=dofile(mod.."/packed_campaign.lua")
local file="live-tick-motion.chk"
local disk=dofile(mod.."/campaign_checkpoint.lua")(core,codec,file)
local state,cap=assert(loadfile(mod.."/campaign_transport_commands_fixture.lua"))("live_motion_fixture")
cap.durable_actions=true
assert(state.passenger_house_clock.counter==0)
local fixture=codec.encode(state)
disk.write_state(state)
local client=dofile(mod.."/campaign_authority_client.lua")(core,mod)
local windows={{x=1,z=1,w=32,h=32},{x=1,z=33,w=32,h=32},
  {x=33,z=1,w=32,h=32},{x=33,z=33,w=32,h=32}}
local seen,stepped,previous,stopped={},{},nil,false
local observations=0
local issued,loan_checked,loan_day=false,false,nil
local function compare_world(reopened,day)
  local original=codec.decode(fixture)
  local Sim=dofile(mod.."/sim.lua")
  local r=dofile(mod.."/campaign_authority_runtime.lua")(Sim,mod,original,cap)
  local endpoint=dofile(mod.."/campaign_authority_endpoint.lua")(Sim,r)
  while original.day<day do
    r.day()
    r.passengers.collect()
    Sim.rail_paid_motion_events(original)
    Sim.air_paid_motion_events(original)
    original.changed=nil
    if original.day==loan_day then
      local v=endpoint.company("Road")
      local receipt=endpoint.command("Road",{kind="company_loan",amount=10000,revision=v.revision})
      assert(receipt.ok,receipt.why)
    end
  end
  local forward,reverse={},{}
  local function equal(a,b,path)
    if type(a)~="table" then
      assert(a==b,path.." value differs: "..tostring(a).." vs "..tostring(b))
      return
    end
    assert(type(b)=="table",path)
    if forward[a] or reverse[b] then
      assert(forward[a]==b and reverse[b]==a,path.." shared reference differs")
      return
    end
    forward[a],reverse[b]=b,a
    for k,v in pairs(a) do
      if a~=original or k~="campaign_day_fraction" then equal(v,b[k],path.."."..k) end
    end
    for k in pairs(b) do
      if a~=original or k~="campaign_day_fraction" then assert(a[k]~=nil,path.."."..k.." extra") end
    end
  end
  equal(original,reopened,"world")
end
local function signature(actor)
  local p=actor.pos or actor.parts and actor.parts[1] and actor.parts[1].pos
  if not p or actor.hidden then return end
  return ("%.4f/%.4f/%.4f"):format(p.x,p.y,p.z)
end
local function query()
  assert(client.query({kind="actor_frames",windows=windows},function(reply)
    assert(reply.ok and reply.actor_tick==reply.tick and (not previous or reply.tick>=previous))
    previous=reply.tick
    observations=observations+1
    if reply.tick%74~=0 then stepped[reply.tick]=true end
    for _,value in ipairs(reply.value) do
      for _,actor in ipairs(value.actors) do
        local p=signature(actor)
        if p then
          seen[actor.mode]=seen[actor.mode] or {}
          seen[actor.mode][p]=true
        end
      end
    end
    if reply.tick>=1000 and reply.tick%74~=0 and not issued then
      issued=true
      assert(client.query({kind="command",player="Road",command={kind="company_loan",
        amount=10000,revision=reply.revision}},function(r)
        assert(r.ok and r.revision==reply.revision+1 and r.tick%74==0,r.why)
        local durable=assert(disk.read())
        assert(durable.day==r.day and durable.passenger_house_clock.counter==r.tick
          and durable.companies.Road.loan==state.companies.Road.loan+10000)
        loan_checked,loan_day=true,r.day
        core.after(.026,query)
      end))
      return
    end
    if reply.tick>=3400 then
      stopped=true
      assert(client.query({kind="stop"},function() error("Unexpected early stop receipt") end))
    else core.after(.026,query) end
  end))
end
core.register_on_mods_loaded(function()
  assert(client.start(cap,function(ready)
    assert(ready.ready and ready.day==0)
    query()
  end,function(why,_,day,detail)
    assert(why=="stopped" and stopped,detail or why)
    local reopened=assert(disk.read())
    assert(reopened.day==day and reopened.passenger_house_clock.counter==day*74)
    for _,mode in ipairs({"road","rail","ship","air"}) do
      local count=0
      for _ in pairs(seen[mode] or {}) do count=count+1 end
      assert(count>=4,mode.." failed to move across at least four distinct actual presentations: "..count)
      core.log("action",("LIVE_TICK_MOTION %s %d distinct native poses"):format(mode,count))
    end
    local count=0
    for _ in pairs(stepped) do count=count+1 end
    assert(count>35 and observations>45 and loan_checked)
    core.log("action",("PASS LIVE TICK MOTION %d distinct in-day ticks, %d views, reopened complete day %d")
      :format(count,observations,day))
    compare_world(reopened,day)
    core.log("action","PASS LIVE TICK EXACT: four paid modes match the unsliced RC1 clock and finance state")
    local total=reopened.passenger_house_clock.counter
    assert(client.start(cap,function(ready)
      assert(ready.ready and ready.day==day)
      core.after(.36,function()
        assert(client.query({kind="actor_frames",windows=windows},function(r)
          assert(r.ok and r.actor_tick>total and #r.value==#windows)
          assert(client.query({kind="stop"},function() error("Unexpected reopen stop receipt") end))
        end))
      end)
    end,function(reason,_,last,error_)
      assert(reason=="stopped" and last>day,error_ or reason)
      core.log("action","PASS LIVE TICK RESTART: durable in-day edit and renewed simulation without views")
      core.request_shutdown("Actual stock actor samples verified",false,0)
    end,file))
  end,file))
end)
