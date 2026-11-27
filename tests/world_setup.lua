local M=dofile("mods/luanttd_core/world_setup.lua")
local params={bayline_seed="4294967295",bayline_generated_map_size="128",
  luanttd_town_growth_rate="4",bayline_generated_relief="99",bayline_generated_town_layout="grid3"}
local settings={get=function(_,name)return params[name] end}
local defaults=M.defaults(settings)
assert(defaults.seed==4294967295 and defaults.size==128 and defaults.relief==1 and defaults.layout=="grid3" and defaults.rivers==2)
assert(defaults.growth_rate==4)
assert(defaults.larger_towns==4 and defaults.initial_city_size==2 and defaults.town_min_distance==20 and defaults.custom_towns==1)
local custom=assert(M.parse(defaults,{setup_towns="5",setup_custom_towns="123",setup_larger_towns="0",
  setup_initial_city_size="10",setup_town_min_distance="500"}))
assert(custom.towns==4 and custom.custom_towns==123 and custom.larger_towns==0 and custom.initial_city_size==10 and custom.town_min_distance==500)
for k,v in pairs{custom_towns="5001",larger_towns="256",initial_city_size="0",town_min_distance="9"} do
  assert(not M.parse(defaults,{["setup_"..k]=v}))
end
assert(M.parse(defaults,{setup_growth_rate="1"}).growth_rate==0)
assert(not M.parse(defaults,{setup_growth_rate="6"}))
local submitted={setup_seed="12345678",setup_size="1",setup_relief="3",setup_rivers="2",setup_year="1968",setup_industries="1",setup_coast="2",setup_smooth="3",setup_variety="4"}
local cfg=assert(M.parse(defaults,submitted))
assert(cfg.seed==12345678 and cfg.size==64 and cfg.relief==2 and cfg.rivers==1 and cfg.industries==0)
assert(cfg.layout=="grid3" and defaults.size==128 and cfg.year==1968 and defaults.year==1950)
assert(cfg.coast==0 and cfg.smooth==2 and cfg.variety==3)
assert(not M.parse(defaults,{setup_seed="2.5"}))
assert(not M.parse(defaults,{setup_year="1968.5"}))
assert(not M.parse(defaults,{setup_year="1949"}))
assert(M.parse(defaults,{setup_scenario="2"}).scenario=="farm")
assert(M.parse(defaults,{setup_scenario="3"}).scenario=="oil")
assert(M.parse(defaults,{setup_scenario="6",setup_survey_size="7"}).survey_size==4096)
assert(not M.parse(defaults,{setup_scenario="7"}))
assert(not M.parse(defaults,{setup_scenario="6",setup_survey_size="8"}))
assert(not M.parse(defaults,{setup_rivers="5"}))
assert(not M.parse(defaults,{setup_sea="-1"}))
assert(not M.parse(defaults,{setup_seed="4294967296"}))
local read
local core={parse_json=function(raw) assert(raw=="stored");return read end}
local storage={get_string=function(_,k) assert(k==M.storage_key);return read and "stored" or "" end}
assert(not M.read(core,storage));read=cfg;assert(M.read(core,storage)==cfg)
cfg.trees=false;assert(not M.read(core,storage))
-- Cancel exits without saving any generator options. Unlike Escape,
-- this is an explicit way to leave the untouched setup.
local fields,shown,saved,shutdown
local p={get_player_name=function()return "Player" end}
PcgRandom=function()return {} end
local shell={settings=settings,get_us_time=function()return 0 end,
  formspec_escape=function(s)return s end,show_formspec=function(_,_,f)shown=f end,
  register_on_joinplayer=function()end,
  register_on_player_receive_fields=function(fn)fields=fn end,
  write_json=function()return "valid-json" end,
  request_shutdown=function(reason,reconnect)shutdown={reason,reconnect}end}
local store={set_string=function(_,_,s)saved=s end}
M.mount(shell,store)
fields(p,M.form,{setup_defaults="true"})
assert(shown:find("Generate world",1,true) and shown:find("Cancel setup",1,true))
fields(p,M.form,{setup_advanced="true"})
assert(shown:find("Custom town count",1,true) and shown:find("Every Nth town is a city",1,true))
assert(shown:find("Town growth speed",1,true) and shown:find("None,Slow,Normal,Fast,Very fast",1,true))
fields(p,M.form,{setup_cancel="true",setup_seed="bad"})
assert(shutdown and shutdown[2]==false and not saved)
M.mount(shell,store)
fields(p,M.form,{setup_generate="true"})
assert(shutdown and shutdown[2]==true and saved=="valid-json")
print("PASS world setup valid defaults, draft parsing, explicit choices, range and saved validation")

local queue,progress_events,reconnects={}, {}, 0
saved=nil
local player={
  get_player_name=function() return "Player" end,
}
shell.get_player_by_name=function() return player end
shell.after=function(_,fn,...) queue[#queue+1]={fn,...} end
shell.show_formspec=function(_,form,body)
  if form=="luanttd_core:generating_world" then progress_events[#progress_events+1]=body end
end
shell.request_shutdown=function(_,reconnect)
  assert(reconnect and saved=="valid-json")
  reconnects=reconnects+1
end
local status="pending"
M.mount(shell,store,function(_,progress,done)
  shell.after(.1,progress,5,"Shaping the landscape")
  shell.after(.2,progress,62,"Building towns")
  shell.after(.3,function() status="prepared";done(true) end)
  return true
end)
fields(player,M.form,{setup_generate=true})
assert(not saved and #progress_events==1 and progress_events[1]:find("0%",1,true))
fields(player,M.form,{setup_generate=true}) -- stale click must not kick twice
while #queue>0 do
  local job=table.remove(queue,1);job[1](unpack(job,2))
  if status~="prepared" then assert(not saved and reconnects==0) end
end
assert(reconnects==1 and status=="prepared" and #progress_events==4)
for i,pct in ipairs({0,5,62,90}) do assert(progress_events[i]:find(pct.."%",1,true)) end
print("PASS generation starts on submit with real progress; exactly one reconnect after the campaign is prepared")

-- A worker error or disk failure must not save options or leave the
-- setup wedged. A late second callback from the first task is ignored.
local callbacks,failures={},0
saved=nil
shell.log=function(level,text) assert(level=="error" and text:find("disk full",1,true));failures=failures+1 end
shell.close_formspec=function(_,id) assert(id=="luanttd_core:generating_world") end
M.mount(shell,store,function(_,_,done)
  callbacks[#callbacks+1]=done
  return true
end)
fields(player,M.form,{setup_generate=true})
assert(#callbacks==1)
callbacks[1](false,"disk full")
assert(failures==1 and not saved and reconnects==1)
fields(player,M.form,{setup_generate=true})
assert(#callbacks==2)
callbacks[1](true)
assert(#queue==0)
callbacks[2](true)
callbacks[2](true)
assert(#queue==1)
local resume=table.remove(queue,1)
resume[1]()
assert(saved=="valid-json" and reconnects==2)
print("PASS failed writes leave settings unchanged; retry succeeds and duplicate/stale completions do not reconnect")

-- Interactive seed is local to the new-world form. Retain it through
-- navigation, reset and invalid input; reroll and manual seeds use all 32 bits.
params.bayline_seed=nil
local i=0
PcgRandom=function()
  return {next=function(_,lo,hi)
    assert(lo==0 and hi==65535)
    i=i+1;return ({0x8123,0x4567,0xffff,0xffff})[i]
  end}
end
shell.show_formspec=function(_,form,body) if form==M.form then shown=body end end
shell.write_json=function(draft)
  assert(draft.seed==4028957751 and draft.rivers==2)
  return "valid-json"
end
M.mount(shell,store)
fields(player,M.form,{setup_advanced=true})
assert(shown:find("2166572391",1,true))
fields(player,M.form,{setup_defaults=true})
assert(shown:find("2166572391",1,true))
fields(player,M.form,{setup_random=true})
assert(shown:find("4294967295",1,true) and i==4)
fields(player,M.form,{setup_generate=true,setup_seed="4028957751"})
assert(reconnects==3 and i==4)
params.bayline_generated_rivers="0"
assert(M.defaults(settings).rivers==0)
print("PASS fresh 32-bit UI seeds, preserved reset, exact manual seed, and stock Normal rivers with an explicit off override")
