local M=dofile("mods/luanttd_core/campaign_step.lua")
local world={day=0,speed=1}
local seen,captures,effects={},0,0
local hooks={advance=function(s)
  s.day=s.day+1
  s.changed={6,3,10,s.day%3+1}
end,refresh=function(ids)
  local a={}
  for i,v in ipairs(ids) do a[i]=v end
  seen[#seen+1]=table.concat(a,",")
end,capture=function() captures=captures+1 end,discard_effects=function() effects=effects+1 end}
local run=M.new(world,1,hooks)
local f,n=run.step(100,false,false)
assert(n==0 and f==1 and world.day==0 and #seen==0)
f,n=run.step(.5,false,true)
assert(n==0 and f==.5)
f,n=run.step(3,false,true)
assert(n==3 and f==.5 and world.day==3 and #seen==0 and captures==0 and effects==3)
assert(world.offscreen_terrain_dirty[1] and world.offscreen_terrain_dirty[2] and world.offscreen_terrain_dirty[3])
-- An engine process can restart while nothing behind the latest visual
-- unacknowledged tile state has been updated. The dirty set travels with it.
run=M.new(world,1,hooks)
f,n=run.step(.75,true,false)
assert(n==0 and f==.75 and seen[1]=="1,2,3,6,10" and not world.offscreen_terrain_dirty)
f,n=run.step(.25,true,false)
assert(n==1 and f==0 and world.day==4 and captures==1 and effects==3 and seen[2]=="6,3,10,2")
world.speed=0
f,n=run.step(60,false,true)
assert(n==0 and f==1 and world.day==4)
world.speed=4
f,n=run.step(600,false,true)
assert(n==12 and world.day==16 and captures==1 and effects==15)
print("PASS: exact one campaign clock, opt-in headless ticks, bounded serializable dirty IDs, fresh view flush and paused-time discard")

-- The native owner gets an inbox turn between overdue days. The smaller
-- slice changes latency, not the total number of days that come due.
do
  local s={day=0,speed=4,campaign_day_fraction=.5}
  local run=M.new(s,1,{persist_fraction=true,day_budget=1,
    advance=function(w) w.day=w.day+1 end,refresh=function() error("Unexpected terrain edit") end})
  local f,n,overdue=run.step(.75,true,true)
  assert(f==1 and n==1 and overdue and s.day==1)
  f,n,overdue=run.step(0,true,true)
  assert(f==1 and n==1 and overdue and s.day==2)
  f,n,overdue=run.step(0,true,true)
  assert(f==.5 and n==1 and not overdue and s.day==3)
  f,n,overdue=run.step(0,true,true)
  assert(f==.5 and n==0 and not overdue and s.day==3)
  assert(run.sample(.0625)==.75 and run.sample(50)==1)
  assert(s.day==3 and s.campaign_day_fraction==.5)
  s.speed=0; f,n,overdue=run.step(60,true,true)
  assert(f==1 and n==0 and not overdue and s.campaign_day_fraction==.5)
  s.speed=2; f,n,overdue=run.step(.25,true,true)
  assert(f==0 and n==1 and not overdue and s.day==4)
end
print("PASS: mailbox catch-up quantum preserves elapsed days, pause and saved interpolation")

-- Exercise the real owner loop without relying on a particular CPU
-- speed. At the first poll, exactly three whole game days become due.
do
  local s,ipc,events={speed=4,day=0,authority_revision=0},{},{}
  local mod="mods/luanttd_core"
  local prefix="luanttd_core:authority:1"
  local now,polls=0,0
  local old_core,load=core,dofile
  local function add(value) events[#events+1]=value end
  core={
    get_modpath=function() return mod end,
    get_current_modname=function() return "luanttd_core" end,
    get_us_time=function() return now end,
    ipc_get=function(k) return ipc[k] end,
    ipc_set=function(k,v)
      ipc[k]=v
      if k==prefix..":reply" and v and v.seq>0 then add("reply"..v.seq..":"..s.day) end
    end,
    ipc_poll=function(k,wait)
      polls=polls+1
      assert(wait==(polls==1 and 35 or polls==4 and 35 or 1))
      if polls==1 then now=750000;return false end
      if polls==2 then ipc[k]={seq=1,kind="actor_frames"};return true end
      if polls==3 then ipc[k]={seq=2,kind="command",player="tester",command={kind="edit"}};return true end
      assert(polls==4)
      ipc[prefix..":cancel"]=true
      return false
    end,
  }
  local noop=function() end
  local sim=setmetatable({},{__index=function() return function() return {} end end})
  local modules={
    ["/campaign_authority_runtime.lua"]=function()
      return {day=function() s.day=s.day+1;add("day"..s.day) end,frame=noop,
        passengers={frame=noop,collect=noop,collect_fares=noop}}
    end,
    ["/campaign_authority_endpoint.lua"]=function()
      return {
        actor_frames=function(_,fraction) assert(fraction==1);return {ok=true} end,
        command=function() s.authority_revision=1;add("edit:"..s.day);return {ok=true,revision=1} end,
      }
    end,
    ["/campaign_checkpoint.lua"]=function()
      return {read=function() return s end,write_state=function() add("save:"..s.day) end}
    end,
    ["/packed_campaign.lua"]={},
    ["/sim.lua"]=sim,
    ["/campaign_solar_clock.lua"]={sample_interval=.1,new=function() return function() return {} end end},
  }
  dofile=function(path)
    if path:sub(1,#mod)==mod then
      local override=modules[path:sub(#mod+1)]
      if override then return override end
    end
    return load(path)
  end
  local ok,why=pcall(function()
    load(mod.."/campaign_authority_worker.lua")
    local why,seq,day=core.luanttd_own_campaign("ignored",prefix,{autoplay=true,seconds_per_day=1,durable_actions=true})
    assert(why=="cancelled" and seq==2 and day==3)
    assert(table.concat(events,",")=="day1,reply1:1,day2,edit:2,save:2,reply2:2,day3,save:3")
  end)
  core,dofile=old_core,load
  assert(ok,why)
end
print("PASS: native owner replies and saves deliberately queued actions between full catch-up days")

-- Wire requests still run while paused. An uncheckpointed edit must
-- trigger the periodic save even if the clock is frozen; ordinary view
-- polls should never re-save the same state.
do
  local prefix,mod="luanttd_core:authority:1","mods/luanttd_core"
  local orig_core,orig_dofile=core,dofile
  for _,durable in ipairs({false,true}) do
    local s={day=12,speed=0,authority_revision=0}
    local ipc,stored={},{}
    local index,now=0,0
    local script={
      {8,"clock"},            -- first periodic write after mount
      {16,"snapshots"},       -- no repeated paused write
      {24,"road_quote"},      -- read-only AutoRoad hover does not arm a save
      {25,"checkpoint"},      -- reset the quiet window
      {27,"command"},         -- persist now only if durable
      {36,"clock"},           -- otherwise persist here
      {44,"snapshots"},       -- no repeated write after the edit
      {45,"checkpoint"},      -- deliberate write always honored
      {46,"cancel"},          -- clean shutdown always honored
    }
    core={
      get_modpath=function() return mod end,
      get_current_modname=function() return "luanttd_core" end,
      get_us_time=function() return now end,
      ipc_get=function(k) return ipc[k] end,
      ipc_set=function(k,v) ipc[k]=v end,
      ipc_poll=function(k)
        index=index+1
        local r=assert(script[index])
        now=r[1]*1000000
        if r[2]=="cancel" then ipc[prefix..":cancel"]=true;return false end
        ipc[k]={seq=index,kind=r[2],player="tester",command={kind="edit"},peek=true,request={tool="bend"}}
        return true
      end,
    }
    local noop=function() end
    local read=function() return {ok=true} end
    local modules={
      ["/campaign_authority_runtime.lua"]=function()
        return {day=function() error("paused day advanced") end,frame=noop,
          passengers={frame=noop,collect=noop,collect_fares=noop}}
      end,
      ["/campaign_authority_endpoint.lua"]=function()
        return {snapshots=read,actor_frames=read,road_quote=read,command=function()
          s.authority_revision=s.authority_revision+1
          return {ok=true,revision=s.authority_revision}
        end}
      end,
      ["/campaign_checkpoint.lua"]=function()
        return {read=function() return s end,write_state=function()
          stored[#stored+1]=(now/1000000)..":"..s.authority_revision
        end}
      end,
      ["/packed_campaign.lua"]={},
      ["/sim.lua"]={},
      ["/campaign_solar_clock.lua"]={sample_interval=.1,new=function() return read end},
    }
    dofile=function(path) return modules[path:sub(#mod+1)] or orig_dofile(path) end
    local ok,why=pcall(function()
      orig_dofile(mod.."/campaign_authority_worker.lua")
      local reason,seq,day=core.luanttd_own_campaign("ignored",prefix,{
        autoplay=true,seconds_per_day=1,durable_actions=durable})
      assert(reason=="cancelled" and seq==8 and day==12)
      local expected=durable and "8:0,25:0,27:1,45:1,46:1" or "8:0,25:0,36:1,45:1,46:1"
      assert(table.concat(stored,",")==expected,table.concat(stored,","))
    end)
    core,dofile=orig_core,orig_dofile
    assert(ok,why)
  end
end
print("PASS: paused viewport polls do not save; paid edit, explicit save and shutdown remain durable")

-- Each invocation starts a freshly mounted worker with a deterministic
-- clock. An autosave occupies the owner while the host's next query arrives.
local file="mods/luanttd_core/campaign_authority_worker.lua"
local function scenario(kind,quick)
  local state={day=4,speed=1}
  local order,results,now,step={}, {},0,0
  local channel="luanttd_core:authority:1"
  local inbox,outbox,cancel=channel..":request",channel..":reply",channel..":cancel"
  local pending
  local core={get_modpath=function() return "fixture" end,get_current_modname=function()return "luanttd_core"end,
    get_us_time=function()return now end}
  local function record(text) order[#order+1]=text end
  function core.ipc_get(key)
    if key==inbox then return pending end
    if key==cancel then return step==3 end
  end
  function core.ipc_poll(key,budget)
    assert(key==inbox and budget==35);step=step+1
    if step==1 then now=8000000;return false end
    if step==2 then
      pending={seq=1,kind=kind,player="Tester",command={kind="company_open"}}
      return true
    end
    assert(step==3)
    return false
  end
  function core.ipc_set(key,value)
    if key==inbox then pending=nil end
    if key==outbox and not value.ready then record("reply");results[#results+1]={value=value,time=now} end
  end
  local runtime={day=function() state.day=state.day+1 end,
    frame=function()end,passengers={frame=function()end,collect=function()end,collect_fares=function()end}}
  local noop=function()end
  local mock={
    campaign_authority_runtime=function()return runtime end,
    campaign_authority_endpoint=function()
      local function observed() return {ok=true,day=state.day} end
      return {actor_frames=observed,snapshots=observed,
        command=function()
          record("command")
          state.authority_revision=1
          return {ok=true,revision=1,day=state.day}
        end}
    end,
    campaign_checkpoint=function()
      return {read=function()return state end,write_state=function()
        record("save");now=now+(quick and 30000 or 1200000)
      end}
    end,
    packed_campaign={},
    campaign_solar_clock={sample_interval=.1,new=function()return function()return {} end end},
    campaign_step={new=function(_,_,hooks)
      return {sample=function() return .4 end,step=function(dt)
        record("advance");hooks.advance();now=now+(quick and 20000 or 800000)
        return 0.4,1,false
      end}
    end},
    sim={rail_paid_motion_events=noop,rail_coal_loading_events=noop,rail_goods_loading_events=noop,
      rail_oil_loading_events=noop,air_paid_motion_events=noop}
  }
  local env=setmetatable({core=core,dofile=function(p) return assert(mock[p:match("([^/]+)%.lua$")]) end},{__index=_G})
  setfenv(assert(loadfile(file)),env)()
  local ended,seq=core.luanttd_own_campaign("fixture",channel,{autoplay=true,durable_actions=true})
  assert(ended=="cancelled" and seq==1 and state.day==6 and #results==1)
  return table.concat(order,","),results[1]
end
local sequence,actor=scenario("actor_frames")
assert(sequence=="advance,save,reply,advance,save",sequence)
assert(actor.time==10000000 and actor.value.day==5)
local sequence,sector=scenario("snapshots")
assert(sequence=="advance,save,reply,advance,save",sequence)
assert(sector.time==actor.time and sector.value.day==actor.value.day)
local sequence,paid=scenario("command")
assert(sequence=="advance,save,advance,command,save,reply,save",sequence)
assert(paid.time==12000000 and paid.value.day==6 and paid.value.revision==1)
local sequence,fast=scenario("actor_frames",true)
assert(sequence=="advance,save,advance,reply,save",sequence)
assert(fast.time==8070000 and fast.value.day==6)
print("PASS after long save: viewport replies before catch-up, durable commands still advance and save first")


-- Periodic encoding may read an exact presentation snapshot, but
-- a queued paid edit and its receipt both wait for a normal owner turn.
do
  local state={day=9,speed=1,authority_revision=0,campaign_day_fraction=.1}
  local channel="luanttd_core:authority:1"
  local inbox,outbox,cancel=channel..":request",channel..":reply",channel..":cancel"
  local now,polls,views=0,0,0
  local ipc,trace={},{}
  local function log(s) trace[#trace+1]=s end
  local fake={get_modpath=function() return "fixture" end,get_current_modname=function() return "luanttd_core" end,
    get_us_time=function() return now end,ipc_get=function(k) return ipc[k] end}
  function fake.ipc_set(k,v)
    ipc[k]=v
    if k==outbox and not v.ready then log("reply"..v.seq..":"..v.revision) end
  end
  function fake.ipc_poll(k)
    assert(k==inbox)
    polls=polls+1
    if polls==1 then now=8000000;return false end
    if polls==2 then now=8650000;return ipc[inbox]~=nil end
    ipc[cancel]=true
    return false
  end
  local function observe(_,f)
    views=views+1
    assert(state.authority_revision==0 and state.day==9)
    assert(math.abs(f-(.1+(views==1 and 8.3 or 8.5)/15))<1e-9)
    assert(math.abs(state.campaign_day_fraction-(.1+8/15))<1e-9)
    return {ok=true,revision=0}
  end
  local function noop() end
  local modules={
    campaign_authority_runtime=function()
      return {day=function() state.day=state.day+1 end,frame=noop,
        passengers={frame=noop,collect=noop,collect_fares=noop}}
    end,
    campaign_authority_endpoint=function()
      return {actor_frames=observe,snapshots=observe,road_quote=function(player,request)
        assert(player=="QA" and request.tool=="drag" and state.authority_revision==0 and state.day==9)
        return {ok=true,revision=0,value={cost=190}}
      end,command=function()
        assert(not ipc[inbox])
        state.authority_revision=1
        log("edit")
        return {ok=true,revision=1}
      end}
    end,
    campaign_step=M,
    campaign_checkpoint=function()
      return {read=function() return state end,write_state=function(s,pulse)
        if not pulse then log("plain:"..s.authority_revision);return end
        log("periodic:start")
        now=8300000;ipc[inbox]={seq=1,kind="actor_frames"};pulse()
        assert(ipc[inbox]==nil and ipc[outbox].actor_us==8300000)
        now=8500000;ipc[inbox]={seq=2,kind="snapshots"};pulse()
        assert(ipc[inbox]==nil and ipc[outbox].actor_us==8500000)
        now=8550000;ipc[inbox]={seq=3,kind="road_quote",peek=true,request={tool="drag"},player="QA"};pulse()
        assert(ipc[inbox]==nil and ipc[outbox].value.cost==190 and ipc[outbox].actor_us==nil)
        now=8600000;local edit={seq=4,kind="command",player="QA",command={kind="edit"}}
        ipc[inbox]=edit;pulse()
        assert(ipc[inbox]==edit and s.authority_revision==0)
        log("periodic:finish")
      end}
    end,
    packed_campaign={},
    campaign_solar_clock={sample_interval=.1,new=function() return function() return {} end end},
    sim=setmetatable({},{__index=function() return function() return {} end end}),
  }
  local env=setmetatable({core=fake,dofile=function(p) return assert(modules[p:match("([^/]+)%.lua$")]) end},{__index=_G})
  setfenv(assert(loadfile(file)),env)()
  local reason,seq,day=fake.luanttd_own_campaign("fixture",channel,{
    autoplay=true,durable_actions=true,seconds_per_day=15})
  assert(reason=="cancelled" and seq==4 and day==9 and views==2)
  assert(table.concat(trace,",")=="periodic:start,reply1:0,reply2:0,reply3:0,periodic:finish,edit,plain:1,reply4:1,plain:1",
    table.concat(trace,","))
end
print("PASS: periodic encoding serves in-order presentation and ordinary road hovers; paid edit receipt follows its separate atomic write")

-- A due day and an already queued observation can coincide even after a
-- short poll, with no previous long turn or backlog. Send the end of the
-- complete trajectory before doing the new day, but don't move a paid
-- command ahead of that day.
do
  local file="mods/luanttd_core/campaign_authority_worker.lua"
  local owner="luanttd_core:authority:1"
  local state={day=6,speed=4,authority_revision=0}
  local now,turn=0,0
  local inbox,reply=owner..":request",owner..":reply"
  local ipc,events={},{}
  local function note(e) events[#events+1]=e end
  local noop=function() end
  local sim=setmetatable({},{__index=function() return function() return {} end end})
  local modules={
    campaign_authority_runtime=function()
      return {day=function() state.day=state.day+1;note("day:"..state.day) end,
        frame=noop,passengers={frame=noop,collect=noop,collect_fares=noop}}
    end,
    campaign_authority_endpoint=function()
      return {
        actor_frames=function(_,fraction)
          assert(fraction==1 and state.day==6,"frame must sample the previous complete trajectory")
          return {ok=true}
        end,
        command=function()
          assert(state.day==7,"paid edit overtook a due day")
          state.authority_revision=1;note("edit");return {ok=true,revision=1}
        end,
      }
    end,
    campaign_checkpoint=function()
      return {read=function() return state end,write_state=function() note("save:"..state.day) end}
    end,
    packed_campaign={},
    campaign_solar_clock={sample_interval=.1,new=function() return function() return {} end end},
    sim=sim,
  }
  local saved_core,read=core,dofile
  core={
    get_modpath=function()return "fixture" end,get_current_modname=function()return "luanttd_core" end,
    get_us_time=function()return now end,ipc_get=function(k)return ipc[k] end,
    ipc_poll=function(k)
      assert(k==inbox)
      turn=turn+1
      if turn==1 then now=125000;ipc[k]={seq=1,kind="actor_frames"};return true end
      if turn==2 then ipc[k]={seq=2,kind="command",command={kind="edit"}};return true end
      assert(turn==3);ipc[owner..":cancel"]=true;return false
    end,
    ipc_set=function(k,v)
      ipc[k]=v
      if k==reply and v.seq>0 then
        if v.seq==1 then assert(v.actor_us==125000) end
        note("reply:"..v.seq)
      end
    end,
  }
  dofile=function(path)
    local k=path:match("^fixture/(.*)%.lua$")
    if k=="campaign_step" then return M end
    return assert(modules[k],path)
  end
  local ok,why=pcall(function()
    read(file)
    local reason,sequence,day=core.luanttd_own_campaign("ignored",owner,
      {autoplay=true,seconds_per_day=.5,durable_actions=true})
    assert(reason=="cancelled" and sequence==2 and day==7)
    assert(table.concat(events,",")=="reply:1,day:7,edit,save:7,reply:2,save:7")
  end)
  core,dofile=saved_core,read
  assert(ok,why)
end
print("PASS: due first day releases completed pose first, with day and durable edit order unchanged")
