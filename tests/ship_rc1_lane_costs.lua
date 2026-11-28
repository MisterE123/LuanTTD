local mod="mods/luanttd_core/openttd/"
local T=dofile(mod.."rail_track.lua")
local W=dofile(mod.."ship_follow.lua")(T)
local Y=dofile(mod.."ship_yapf.lua")(T,W,dofile(mod.."yapf_road_search.lua"))
-- IsPreferredShipDirection from 16.0-RC1 yapf_ship.cpp: even/even,
-- odd/even, even/odd, odd/odd. Reverse directions prefer opposite lanes.
local preferred={
  [0]={[1]=true,[3]=true,[4]=true,[8]=true,[10]=true,[13]=true},
  [1]={[2]=true,[5]=true,[8]=true,[9]=true,[11]=true,[12]=true},
  [2]={[0]=true,[1]=true,[2]=true,[5]=true,[11]=true,[12]=true},
  [3]={[0]=true,[3]=true,[4]=true,[9]=true,[10]=true,[13]=true},
}
for y=0,1 do for x=0,1 do
  local e=preferred[y*2+x]
  for td=0,13 do
    if T.valid_trackdir(td) then
      assert(Y.preferred_direction(x,y,td)==not not e[td])
      assert(Y.preferred_direction(x,y,td)~=Y.preferred_direction(x,y,T.reverse_trackdir(td)))
    end
  end
end end
local B={stock_rc1_ship_cost=true,xy=function() return 1,1 end,
  tile=function() return {kind="lock",part="middle",water_class="canal"} end}
local ferry={max_speed=128,canal_speed_frac=32}
assert(Y.tile_cost(B,ferry,1,0,0,0)==914)
B.stock_rc1_ship_cost=false
assert(Y.tile_cost(B,ferry,1,0,0,0)==114)
print("PASS RC1 ship lane parity and integer middle-lock penalty")

local Fault=dofile(mod.."road_breakdowns.lua")
local road,ship=Fault.new(20000,0,7300,0,0),Fault.new(20000,0,7300,0,0)
road.breakdown_chance,ship.breakdown_chance=25,25
local rnd=function() return 32768 end
assert(Fault.economy_day(road,{cur_speed=128,difficulty=Fault.NORMAL},rnd))
assert(not Fault.economy_day(ship,{ship=true,cur_speed=128,difficulty=Fault.NORMAL},rnd))
assert(ship.breakdown_chance==26)
print("PASS RC1 ship-only reliability bonus under the same stock draw")
