local L=dofile("mods/luanttd_core/openttd/town_lift.lua")
local a=L.new()
local h={[11]={id=0x04},[74]={id=0x05,lift_position=36},[1]={id=3}}
local function house(i)return h[i]end
local function word(n)return math.ceil(n*4294967296/7)end
local stream={word(0),word(1),word(2),word(6),word(5),word(0)}
local used=0
local function random()
  used=used+1
  return assert(stream[used],"An unplanned stock random word was consumed")
end
L.add(a,11);L.add(a,74);L.add(a,1);L.add(a,11)
assert(#a.order==3)
L.step(a,3,house,random)
assert(used==0 and not h[11].lift_position)
L.step(a,4,house,random)
assert(used==5 and h[11].lift_position==1 and h[74].lift_position==35)
assert(a.states[1]=="delete" and h[11].lift_destination==2 and h[74].lift_destination==5)
for t=5,24 do L.step(a,t,house,random) end
assert(a.states[1]==nil and a.states[74]=="delete" and h[74].lift_position==30 and not h[74].lift_has_destination)
L.add(a,74);assert(#a.order==2)
L.step(a,25,house,random)
L.step(a,28,house,random)
assert(h[74].lift_destination==0 and h[74].lift_position==29 and used==6)
L.erase(a,11)
assert(#a.order==1 and a.order[1]==74)
h[74]=nil;L.step(a,32,house,random);L.step(a,33,house,random)
assert(#a.order==0 and used==6)
print("PASS RC1 lift rejects missing floor and current floor, advances each fourth tick, preserves animated list RNG order")
