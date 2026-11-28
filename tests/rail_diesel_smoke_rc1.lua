local mod="mods/luanttd_core/openttd/"
local D=dofile(mod.."rail_diesel_smoke_rc1.lua")
local E=dofile(mod.."industry_chimney_effect.lua")
local draws=0
local function random(word)
  return function() draws=draws+1;return word end
end
assert(not D.sample(1,160,2580,137,2,random(0)))
assert(not D.sample(160,160,2580,137,2,random(0)))
assert(not D.sample(80,160,2580,137,1,random(0)))
assert(not D.sample(20,160,2580,137,0,random(0)))
assert(draws==0)
-- For a Floss '47' with one empty coach at 68/160, Chance16I is
-- floor((r*128+64)/65536)<27. Matching stock uses the low word.
assert(D.sample(68,160,2580,137,2,random(13823+65536)))
assert(not D.sample(68,160,2580,137,2,random(13824)))
assert(draws==2)
local s={}
E.add_timed(s,17,"diesel_smoke",10,20,30,30)
E.add_timed(s,33,"diesel_smoke",10,20,30,30)
for _=1,40 do E.step(s) end
assert(s.stock_effect_vehicles[17].y==30 and not s.stock_effect_vehicles[33])
E.step(s)
assert(next(s.stock_effect_vehicles)==nil)
print("PASS RC1 diesel smoke: exact admission, Chance16 word, physical effect lifetime and creator slot")
