-- Exact OpenTTD effect mapping and user-scoped presentation state.
local mod="mods/luanttd_core"
local S=dofile(mod.."/openttd/sound_rc1.lua")
local n,visited=0,{}
for _,sample in pairs(S.sample) do assert(not visited[sample]);visited[sample]=true;n=n+1 end
assert(n==73)
for i=0,72 do assert(visited[i]) end
assert(S.sample.GOOD_YEAR==0 and S.sample.BEEP==0x15 and S.gain[S.sample.BEEP]==.625)
assert(S.sample.BAD_YEAR==1 and S.gain[1]==nil)
assert(S.departure("rail",0)==0x04 and S.departure("rail",1)==0x0A and S.departure("rail",27)==nil)
assert(S.departure("road",116,1)==0x19 and S.departure("road",116,4)==0x1A and S.departure("road",118)==0x1B)
assert(S.departure("ship",204)==0x06 and S.departure("ship",206)==0x07)
assert(S.departure("air",215)==0x08 and S.departure("air",217)==0x09 and S.departure("air",215,nil,true)==0x18)
local at=1000000
local events,form,fields,joined,leaving,step={}
local function emit(name,args)
  events[#events+1]={name,args}
  return #events
end
local function player(name,x)
  local meta={}
  return {get_player_name=function() return name end,get_pos=function() return {x=x,y=0,z=0} end,
    get_meta=function() return {get_string=function(_,k) return meta[k] or "" end,
      set_string=function(_,k,v) meta[k]=v end} end}
end
local a,b=player("near",1),player("far",80)
local core={get_us_time=function() return at end,sound_play=emit,
  sound_stop=function(id) emit("stopped",id) end,sound_fade=function(id,step,gain) emit("fade",{id,step,gain}) end,
  get_connected_players=function() return {a,b} end,formspec_escape=function(s) return s end,
  show_formspec=function(_,name,ui) form=ui;assert(name=="luanttd_core:stock_audio") end,
  register_on_player_receive_fields=function(f) fields=f end,
  register_on_joinplayer=function(f) joined=f end,register_on_leaveplayer=function(f) leaving=f end,
  register_globalstep=function(f) step=f end}
local A=dofile(mod.."/stock_audio.lua")(core,mod,{
  {name="title",slot="theme",duration=2,title="Menu",author="Artist"},
  {name="t1",slot="old_0",duration=2,title="Old",author="Artist"},
  {name="t2",slot="new_0",duration=3,title="New",author="Artist"},
})
local function latest(id,player)
  local e=events[#events]
  assert(e[1]==id,e[1].." ~= "..id)
  if player then assert(e[2].to_player==player,e[2].to_player) end
end
joined(a);latest("t1","near")
joined(b);latest("t1","far")
A.open(a);assert(form:find("Now playing: Old",1,true))
at=at+2500000;step()
assert(events[#events][1]=="t2")
fields(a,"luanttd_core:stock_audio",{audio_list="3"});latest("t2","near")
fields(a,"luanttd_core:stock_audio",{audio_music="CHG:20"});latest("fade")
assert(events[#events][2][3]==.20)
local pos={x=2,y=0,z=0}
A.effect("LEVEL_CROSSING",{pos=pos});latest("stock_sfx_0e","near")
local road={mode="road",engine=116,pos=pos,sound_idle=true}
local events_before=#events
A.observe_vehicles({v=road});assert(#events==events_before)
road.sound_idle=false;road.sound_tick=4
A.observe_vehicles({v=road});latest("stock_sfx_1a","near")
A.observe_vehicles({v=road});assert(#events==events_before+1)
road.breakdown_smoke=true
A.observe_vehicles({v=road});latest("stock_sfx_0f","near")
A.observe_vehicles({})
events_before=#events
A.observe_vehicles({v=road});assert(#events==events_before)
fields(a,"luanttd_core:stock_audio",{audio_sfx="CHG:0"})
A.effect("LEVEL_CROSSING",{pos=pos});assert(#events==events_before)
leaving(a);latest("stopped")
print("PASS: all 73 sound IDs, per-engine selection, positional culling, one-shot transition playback, themed playlists and persistent personal audio UI.")
