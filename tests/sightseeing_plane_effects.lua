local logs,handles={},{}
local fake={
  sound_play=function(asset,p)
    assert(p.to_player=="Pilot")
    logs[#logs+1]={asset,p.gain}
    local id=#logs
    if p.loop then handles[id]=asset end
    return id
  end,
  sound_fade=function(id,step,gain)
    assert(handles[id] and step==.75 and gain>0)
    logs[#logs+1]={handles[id],gain}
  end,
  sound_stop=function(id)
    assert(handles[id])
    handles[id]=nil
  end,
}
local FX=dofile("mods/luanttd_core/sightseeing_plane_effects.lua")(fake)
local sound=FX.start("Pilot")
assert(#logs==3)
FX.update(sound,{mode="takeoff",throttle=1,speed=4},.2)
assert(sound.gain.prop_power>.18 and sound.gain.wind==.002 and sound.gain.prop_idle<.04)
FX.update(sound,{mode="air",throttle=1,speed=12},.2)
assert(sound.gain.wind>.18)
FX.update(sound,{mode="rollout",throttle=0,speed=4},.2)
FX.update(sound,{mode="rollout",throttle=0,speed=1},.2)
assert(sound.gain.wind==.002)
local n=0
for _,v in ipairs(logs) do if v[1]=="bl_plane_touchdown" then n=n+1 end end
assert(n==1)
FX.stop(sound);FX.stop(sound)
assert(not next(handles))
print("PASS pitch-independent propeller crossfade, in-flight wind, one touchdown and all loops released")
