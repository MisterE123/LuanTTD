local bank,near={},{}
local register
local core={register_entity=function(_,def) register=def.initial_properties end,
  get_objects_inside_radius=function(_,_)return near end}
local Sim={}
function Sim.id(x,z) if x>=1 and x<=30 and z>=1 and z<=30 then return (z-1)*30+x end end
function Sim.xy(id) return (id-1)%30+1,math.floor((id-1)/30)+1 end
function Sim.adjacent(id,d)
  local x,z=Sim.xy(id)
  local a=({{0,-1},{1,0},{0,1},{-1,0}})[d]
  return Sim.id(x+a[1],z+a[2])
end
local view={host_tile=function(id)return bank[id] end}
local dir="mods/luanttd_core/"
local V=dofile(dir.."ambient_shop_traffic.lua")(core,Sim,view,dofile(dir.."road_lanes.lua"),
  dofile(dir.."road_motion.lua"),function()return true end)
local id=Sim.id
local function road(x,z,bits) bank[id(x,z)]={build="road",road_bits=bits,road_town=1} end
for x=5,12 do road(x,15,x==5 and 2 or x==12 and 8 or 10) end
bank[id(5,14)]={source_house={id=0x0e,completed=true}}
bank[id(12,16)]={source_house={id=0x1e,completed=true}}
local line=assert(V.plan(id(5,15)))
assert(#line==8 and line[8]==id(12,15))
bank[id(8,15)].road_disallowed=1;assert(not V.plan(id(5,15)))
bank[id(8,15)].road_disallowed=nil;bank[id(8,15)].level_crossing={};assert(not V.plan(id(5,15)))
bank[id(8,15)].level_crossing=nil;bank[id(12,16)].source_house.completed=false;assert(not V.plan(id(5,15)))
local actor=function(data) return {get_luaentity=function()return data end} end
local origin={x=10,y=1,z=15}
near={actor({luanttd_vehicle={kind="road"}})};assert(not V.clear(origin,6))
near={actor({name="luanttd_core:sightseeing_car"})};assert(not V.clear(origin,6))
near={actor({luanttd_vehicle={kind="rail"}})};assert(V.clear(origin,6))
assert(not register.static_save and not register.physical and not register.pointable)
print("PASS scenic shop traffic requires two completed shop frontages and ordinary reciprocal streets, yields to real road traffic")
bank={}
for z=5,25,4 do
  for x=5,24 do
    road(x,z,x==5 and 2 or x==24 and 8 or 10)
    if x%3==1 then bank[id(x,z-1)]={parcel="shop"} end
  end
end
local created={}
function core.add_entity(pos)
  local o={pos=pos}
  function o:get_pos() return self.pos end
  function o:remove() self.pos=nil end
  function o:move_to(p) self.pos=p end
  function o:set_yaw() end
  function o:set_observers(q) self.viewers=q end
  created[#created+1]=o
  return o
end
function view.surface() return 1 end
near={}
local observer={get_pos=function()return{x=29,y=4,z=29}end,get_player_name=function()return "Local" end}
for _=1,70 do V.step(.24,{observer}) end
local visible
for _,o in ipairs(created) do if o.pos then visible=o end end
assert(visible and visible.viewers.Local,"town with multiple shop frontages did not spawn a scenic car")
local real=actor({luanttd_vehicle={kind="road"}})
near={real}
V.step(.24,{observer})
assert(not visible.pos,"scenic car stayed when a working vehicle entered its guard radius")
print("PASS scenic car moves only inside its visual system, then yields completely to a real vehicle")

near={}
V.step(.24,{})
local function find_live()
  for _,o in ipairs(created) do if o.pos then return o end end
end
for _=1,45 do V.step(.24,{observer});if find_live() then break end end
local c=assert(find_live(),"route did not spawn a new visual car")
local lookback,other_back=false,false
-- Keep the camera twelve nodes behind the car, then turn away without
-- changing the road or camera distance. The same actor must stay parked
-- while watched, even after a second spectator turns away.
observer.get_pos=function() return c.pos and {x=c.pos.x-12,y=c.pos.y+1,z=c.pos.z} or origin end
observer.get_look_dir=function() return {x=lookback and -1 or 1,y=0,z=0} end
local other={get_pos=observer.get_pos,get_player_name=function()return "Other" end,
  get_look_dir=function()return {x=other_back and -1 or 1,y=0,z=0} end}
local start_x=c.pos.x
for _=1,120 do V.step(.24,{observer});assert(c.pos,"looked-at car popped during the trip or while parked") end
local parked=c.pos
assert(math.abs(parked.x-start_x)>4)
V.step(.24,{observer})
assert(c.pos==parked,"car did not remain at the shop after arriving")
lookback=true
for _=1,8 do V.step(.24,{observer,other});assert(c.pos and c.viewers.Other,"first user cannot hide the car from a second watcher") end
other_back=true
for _=1,3 do V.step(.24,{observer,other});assert(c.pos,"one glance removed the car too early") end
lookback=false
V.step(.24,{observer,other});assert(c.pos)
lookback=true
for _=1,4 do V.step(.24,{observer,other}) end
assert(not c.pos,"parked car did not retire after leaving view")
print("PASS ambient car completes a slower trip, pulls over and despawns after a sustained look-away")
