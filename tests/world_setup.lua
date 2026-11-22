local M=dofile("mods/luanttd_core/world_setup.lua")
local params={bayline_seed="4294967295",bayline_generated_map_size="128",
  bayline_generated_relief="99",bayline_generated_town_layout="grid3"}
local settings={get=function(_,name)return params[name] end}
local defaults=M.defaults(settings)
assert(defaults.seed==4294967295 and defaults.size==128 and defaults.relief==1 and defaults.layout=="grid3")
local submitted={setup_seed="12345678",setup_size="1",setup_relief="3",setup_rivers="2",setup_industries="1",setup_coast="2",setup_smooth="3",setup_variety="4"}
local cfg=assert(M.parse(defaults,submitted))
assert(cfg.seed==12345678 and cfg.size==64 and cfg.relief==2 and cfg.rivers==1 and cfg.industries==0)
assert(cfg.layout=="grid3" and defaults.size==128)
assert(cfg.coast==0 and cfg.smooth==2 and cfg.variety==3)
assert(not M.parse(defaults,{setup_seed="2.5"}))
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
assert(shown:find("Save and return",1,true) and shown:find("Cancel setup",1,true))
fields(p,M.form,{setup_cancel="true",setup_seed="bad"})
assert(shutdown and shutdown[2]==false and not saved)
M.mount(shell,store)
fields(p,M.form,{setup_generate="true"})
assert(shutdown and shutdown[2]==true and saved=="valid-json")
print("PASS world setup valid defaults, draft parsing, explicit choices, range and saved validation")
