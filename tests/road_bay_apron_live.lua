-- Compound native issue: a parked two-bay terminus needs its entire
-- turning apron clear, not just a free logic tile, beside a three-arm road.
local mod="mods/luanttd_core/"
local Sim=dofile(mod.."sim.lua")
local T=dofile(mod.."openttd/terrain.lua")
local s=Sim.new(1751)
s.road_economy,s.road_stock_clock,s.road_stock_loading,s.road_stock_house_supply=true,true,true,true
s.road_bay_build,s.road_junction_clearance=true,true
dofile(mod.."town_layout.lua")(Sim,s)
s.corner_grid=dofile(mod.."terrain_preview.lua")(Sim,T,s)
local a,b,d=Sim.id(11,12),Sim.id(17,12),Sim.id(12,13)
assert(Sim.build(s,"A","road",Sim.line(a,b)))
assert(Sim.build(s,"A","road_bay_pair",{a,b}))
assert(Sim.build(s,"A","road_depot",{d}))
local buses={}
for _=1,3 do
  local id=assert(Sim.purchase(s,"A","bus","passenger",nil,d))
  buses[#buses+1]=id
  assert(Sim.add_order(s,"A",id,s.tiles[a].station,"full"))
  assert(Sim.add_order(s,"A",id,s.tiles[b].station))
end
for _,id in ipairs(buses) do assert(Sim.toggle(s,"A",id));Sim.daily(s) end
local function copy(t)
  if type(t)~="table" then return t end
  local out={}
  for k,v in pairs(t) do out[k]=copy(v) end
  return out
end
local saved
for _=1,140 do
  Sim.daily(s)
  local x,y,z=s.fleet[1],s.fleet[2],s.fleet[3]
  if x.road_bay_claim and y.road_bay_claim and x.road_bay_claim.phase=="parked"
      and y.road_bay_claim.phase=="parked" and not z.last_road_arrival_tick and
      (z.road_bay_guard_waits or 0)>0 then
    assert(z.road_speed_state.waiting=="bay" and Sim.position(s,z)~=Sim.id(12,12))
    local r=z.road_motion_frames[z.road_speed_state.index]
    saved=copy(s)
    assert(saved.fleet[3].road_motion_frames[z.road_speed_state.index][4]==r[4])
    break
  end
end
assert(saved,"The physical approach never yielded while both bays loaded")
s=saved
for _=1,250 do
  Sim.daily(s)
  local z=s.fleet[3]
  if z.last_road_arrival_tick and s.companies.A.paid_units>0 then
    print("PASS: guards the 3D bay apron; two real parked buses, third resumes and pays after saved wait")
    return
  end
end
error("3D bay apron deadlock after restore")
