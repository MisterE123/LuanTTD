-- Regression for invalidation during the ordered pregame landscape pass.
local mod="mods/luanttd_core/"
local H=dofile(mod.."openttd/town_passengers.lua")
local Sim={W=64,H=64}
function Sim.id(x,z)
  if x>=1 and z>=1 and x<=64 and z<=64 then return (z-1)*64+x end
end
function Sim.xy(id) return (id-1)%64+1,math.floor((id-1)/64)+1 end
local st={tiles={},fleet={},stations={},stock_town_growth={towns={}},stock_generated_profile={},
  passenger_house_clock=H.new_clock(6,6)}
for id=1,64*64 do st.tiles[id]={terrain="water",water_class="sea"} end
st.tiles[1].coastal_water=true
local affected,neighbor,quiet=Sim.id(11,11),Sim.id(12,11),Sim.id(52,49)
local hits={}
local weakened,saw=false,false
local function change(id,kind)
  local t=st.tiles[id]
  t.terrain,t.water_class=kind,kind=="water" and "sea" or nil
  st.changed=st.changed or {}
  st.changed[#st.changed+1]=id
end
local function water(x,z,tick)
  local id=Sim.id(x+1,z+1)
  hits[id]=(hits[id] or 0)+1
  if id==1 and tick==256 then
    assert(hits[affected]==1)
    weakened=true
    -- A flood result may change a neighboring tile, not just its source.
    change(neighbor,"grass")
    return 1
  end
  if id==affected and weakened and st.tiles[neighbor].terrain=="grass" then
    saw=true
    change(neighbor,"water")
    return 1
  end
  return 0
end
local function unexpected() error("No houses, trees or fields in this fixture") end
local M=dofile(mod.."initial_landscape_world.lua")(Sim,H)
local _,stats=M.settle(st,{reconstruction={decorate=unexpected}},
  {field_board=function()return {} end},water,unexpected,unexpected)
assert(saw and hits[affected]>1 and hits[quiet]==1)
assert(stats.tide_changes==2 and stats.ticks==1280)
assert(st.tiles[neighbor].terrain=="water" and #st.changed==2)
print("PASS bounded pregame open-sea cache clears around a changed tile and does not skip later flooding")
