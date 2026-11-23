local slots,alt={},{}
local function storage(t)
  return {get_string=function(_,k) return t[k] or "" end,
    set_string=function(_,k,v) t[k]=v end}
end
local written,index={},0
local core={parse_json=function(id) return written[id] end,
  write_json=function(record) index=index+1;local k=tostring(index);written[k]=record;return k end}
local function player(n) return {get_player_name=function() return n end} end
local open=dofile("mods/luanttd_core/player_return.lua")
local a,b=player("First user"),player("Second user")
local v=open(core,storage(slots))
assert(not v.read(a) and not v.read(b))
assert(v.save(a,{x=31.5,y=13.1,z=14.25},1.41,-.36))
assert(v.save(b,{x=4.2,y=39.1,z=16.25},.66,.26))
assert(not v.save(a,{x=0/0,y=1,z=1},.5,.5))
assert(not v.save(a,{x=0,y=math.huge,z=1},.5,.5))
local restored=open(core,storage(slots))
assert(restored.read(a).pos.z==14.25 and restored.read(a).pitch==-.36 and restored.read(a).yaw==1.41)
assert(restored.read(b).pos.y==39.1 and restored.read(b).yaw==.66)
assert(not open(core,storage(alt)).read(a),"A different world inherited another world's bookmark")
slots["return_view_v1:First user"]="{ malformed"
assert(not restored.read(a))
print("PASS rejoin bookmarks isolate player and world, retain exact coordinates/angles and ignore invalid values")
