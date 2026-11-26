local function clone(t)
  if not t then return end
  local out={};for k,v in pairs(t) do out[k]=v end;return out
end
_G.vector={rotate=function(v,r)
  local c,s=math.cos(r.y),math.sin(r.y)
  return {x=v.x*c-v.z*s,y=v.y,z=v.x*s+v.z*c}
end}
local function object(pos)
  local o={pos=clone(pos)}
  function o:get_pos() return clone(self.pos) end
  function o:move_to(p) self.pos=clone(p) end
  o.set_pos=o.move_to
  function o:remove() self.pos=nil end
  function o:set_rotation(r) self.rotation=clone(r) end
  function o:get_rotation() return self.rotation or {x=0,y=0,z=0} end
  function o:set_properties(v) self.props=clone(v) end
  function o:get_properties() return self.props end
  function o:get_observers() return clone(self.observers) end
  function o:set_observers(users) self.observers=clone(users) end
  function o:get_attach() return self.parent end
  function o:set_attach(parent,_,at,rot,visible)
    self.parent,self.attachment_pos,self.attachment_rot,self.visible=parent,at,rot,visible
  end
  function o:set_detach() self.parent=nil end
  return o
end
local function player(n)
  local p=object({x=11,y=15,z=17})
  p.yaw,p.pitch=.33,-.09
  p.inventory="Original formspec"
  p.flags={hotbar=true,crosshair=false,healthbar=false}
  p.eye={x=1,y=2,z=3};p.third={x=4,y=5,z=6}
  p.keys={}
  function p:get_player_name() return n end
  function p:get_properties() return {eye_height=1.625} end
  function p:get_player_control() return self.keys end
  function p:get_look_dir() return {x=0,y=0,z=1} end
  function p:get_look_horizontal() return self.yaw end
  function p:get_look_vertical() return self.pitch end
  function p:set_look_horizontal(yaw) self.yaw=yaw;self.look_changes=(self.look_changes or 0)+1 end
  function p:set_look_vertical(pitch) self.pitch=pitch end
  function p:get_inventory_formspec() return self.inventory end
  function p:set_inventory_formspec(body) self.inventory=body end
  function p:get_eye_offset() return clone(self.eye),clone(self.third) end
  function p:set_eye_offset(eye,third) self.eye,self.third=eye,third end
  function p:hud_get_flags() return clone(self.flags) end
  function p:hud_set_flags(flags) self.flags=clone(flags) end
  function p:hud_add(def) self.label=def.text;return 3 end
  function p:hud_remove(id) assert(id==3);self.label=nil end
  return p
end
local a,b,c=player("Rider"),player("Other"),player("Late")
local name_bank={}
local attachments={}
local core={get_dir_list=function(path)
  local ext=path:find("/models",1,true) and ".obj" or ".png"
  return {"bl_ride_bus_interior"..ext,"bl_ride_train_interior"..ext,"bl_ride_train_cab"..ext,
    "bl_ride_airliner_interior"..ext,"bl_ride_ferry_interior"..ext}
end,register_entity=function(name,def) name_bank[name]=def end,add_entity=function(pos,name)
  local o=object(pos);o.name=name;attachments[#attachments+1]=o;return o
end}
local api={world={may_board=function()return true end,follow_hud=function(p,active)
  if active then p:hud_set_flags({hotbar=false}) else p:hud_set_flags({hotbar=true,crosshair=true}) end
end}}
local R=dofile("mods/luanttd_core/vehicle_ride.lua")(core,api,"mods/luanttd_core")
local zero={x=0,y=0,z=0}
local function equal(a,b) return math.abs(a-b)<.00001 end
local bus=object({x=20,y=5,z=22})
bus:set_properties({visual="mesh",mesh="real_bus.obj",textures={"own_livery.png"}})
local function track_vehicle(ref,at,cargo,running)
  R.track("road",2,ref,at,{x=0,y=math.pi,z=0},{passenger=cargo,running=running})
end
local old_pos=a:get_pos()
R.step(.05,{a,b})
track_vehicle(bus,bus:get_pos(),false,true)
assert(not R.enter(a,"ride",{kind="road",id=2}),"cargo truck must not receive passenger interior")
track_vehicle(bus,bus:get_pos(),true,false)
assert(not R.enter(a,"ride",{kind="road",id=2}),"parked bus must not receive passenger interior")
track_vehicle(bus,bus:get_pos(),true,true)
assert(R.enter(a,"ride",{kind="road",id=2}))
local camera,inside,third=attachments[1],attachments[2],attachments[3]
assert(third.parent==a and third.visible==false and third.props.mesh=="real_bus.obj")
assert(third.observers.Rider and not third.observers.Other)
assert(inside:get_attach()==camera and a:get_attach()==camera)
assert(inside:get_observers().Rider and not inside:get_observers().Other and not inside:get_observers().Late)
assert(bus:get_observers().Other and not bus:get_observers().Rider)
assert(equal(camera:get_pos().y,5+.071+.117-1.625) and a:get_inventory_formspec():find("Leave ride"))
R.step(.05,{a,b,c})
assert(bus:get_observers().Late and not bus:get_observers().Rider)
a:set_look_horizontal(1.2);a:set_look_vertical(-.3)
bus:set_pos({x=21,y=5,z=25})
track_vehicle(bus,bus:get_pos(),true,true)
R.step(.05,{a,b,c})
assert(equal(camera:get_pos().x,21-.02) and equal(camera:get_pos().z,25-.042))
assert(a:get_look_horizontal()==1.2 and a:get_look_vertical()==-.3)
local stable=a.look_changes
for _=1,5 do track_vehicle(bus,bus:get_pos(),true,true);R.step(.11,{a,b,c}) end
assert(a.look_changes==stable,"a straight stretch continuously sent look corrections")
R.track("road",2,bus,bus:get_pos(),{x=0,y=math.pi+.40,z=0},{passenger=true,running=true})
R.step(.11,{a,b,c})
assert(equal(a:get_look_horizontal(),1.60) and a:get_look_vertical()==-.3,
  "a vehicle turn lost the passenger's independent look angle")
local turning=a.look_changes
a:set_look_horizontal(2.05)
R.track("road",2,bus,bus:get_pos(),{x=0,y=-math.pi+.41,z=0},{passenger=true,running=true})
R.step(.11,{a,b,c})
assert(a.look_changes==turning+1 and equal(a:get_look_horizontal(),2.05),"tiny wraparound motion recentered the view")
assert(R.enter(b,"ride",{kind="road",id=2}) and not bus:get_observers().Other)
assert(R.controls(a,{aux1=true,place=true}) and R.active(a)
  and a.label:find("Inventory: leave ride",1,true),"ordinary controls must not eject a rider")
assert(R.exit(a) and not R.active(a))
assert(bus:get_observers().Rider and not bus:get_observers().Other)
assert(a:get_pos().x==old_pos.x and a:get_pos().y==old_pos.y and a:get_pos().z==old_pos.z)
assert(a:get_look_horizontal()==.33 and a:get_look_vertical()==-.09)
assert(a:get_eye_offset().z==3 and a:get_inventory_formspec()=="Original formspec" and not a.flags.crosshair)
assert(not inside:get_pos() and not third:get_pos())
assert(R.exit(b) and not bus:get_observers(),"unmanaged observers must be restored, not a stale player list")

local cab,coach,collector=object({x=30,y=6,z=30}),object({x=30,y=6,z=31}),object({x=30,y=7,z=30})
local function rail(c,w,travel_cab,travel_coach)
  R.track("rail",9,c,c:get_pos(),zero,{body=7,engine=true,travel=travel_cab,running=true})
  R.track("rail",9,w,w:get_pos(),zero,{body=31,passenger=true,travel=travel_coach,running=true})
  if collector:get_pos() then
    R.track("rail",9,collector,collector:get_pos(),zero,{body=7,auxiliary=true})
  end
end
cab:set_observers({Rider=true,Other=true})
rail(cab,coach,1,2)
-- Using a coach as the selection can reach the operating cab, but only
-- that exact body (plus its collector) becomes hidden for the rider.
assert(R.enter(a,"cab",{kind="rail",id=9,body=31}))
assert(not cab:get_observers().Rider and cab:get_observers().Other and not cab:get_observers().Late)
assert(not collector:get_observers().Rider and not coach:get_observers())
assert(R.exit(a))
assert(cab:get_observers().Rider and cab:get_observers().Other and not cab:get_observers().Late)
assert(not collector:get_observers())

assert(R.enter(a,"ride",{kind="rail",id=9,body=7}))
assert(not coach:get_observers().Rider and cab:get_observers().Rider)
local interior=attachments[#attachments]
coach:remove()
local seat=a:get_attach()
local frozen=seat:get_pos()
R.step(.1,{a,b,c});R.step(1.75,{a,b,c})
assert(interior:get_pos() and R.active(a) and a:get_attach()==seat and seat:get_pos().x==frozen.x
  and seat:get_pos().y==frozen.y and seat:get_pos().z==frozen.z,
  "a short worker cull must freeze the same cabin and seat, not detach the rider")
local rebuilt=object({x=29,y=6,z=31})
rail(cab,rebuilt,2,1)
R.step(.1,{a,b,c})
assert(R.active(a) and rebuilt:get_observers().Other and not rebuilt:get_observers().Rider)
assert(cab:get_observers().Rider and cab:get_observers().Other,
  "travel-order reversal must not mask the unoccupied locomotive")
assert(equal(a:get_attach():get_pos().x,rebuilt:get_pos().x+.091),
  "after reversal the seat must follow the same physical coach rather than the new front")
rebuilt:remove()
R.step(.1,{a,b,c});R.step(3.1,{a,b,c})
assert(not R.active(a) and not a:get_attach() and not interior:get_pos(),
  "a truly lost target must remove its private cabin and restore builder mode")
-- Running passenger airplanes and ferries share the actual geometry and
-- visibility lifecycle, including the gear-up mesh change in chase view.
local air=object({x=40,y=21,z=55})
air:set_properties({visual="mesh",mesh="stock_gear.obj",textures={"flight.png"}})
local air_pick={kind="air",id=12}
local i=#attachments
R.track("air",12,air,air:get_pos(),zero,{running=true,passenger=false})
assert(not R.enter(a,"ride",air_pick) and not R.enter(a,"cab",air_pick))
R.track("air",12,air,air:get_pos(),zero,{running=false,passenger=true})
assert(not R.enter(a,"ride",air_pick))
R.track("air",12,air,air:get_pos(),zero,{running=true,passenger=true,mesh="stock_gear.obj"})
assert(R.enter(a,"ride",air_pick))
assert(attachments[i+2].name=="luanttd_core:ride_airliner_interior" and a.label:find("Window seat",1,true))
assert(math.abs(a:get_look_horizontal()-math.pi)>1,"air passenger seated straight ahead instead of looking out")
local plane_pos=a:get_attach():get_pos()
air:set_pos({x=42,y=25,z=57})
R.track("air",12,air,air:get_pos(),zero,{running=true,passenger=true,mesh="flight_gear_up.obj"})
R.step(.12,{a,b,c})
assert(a:get_attach():get_pos().y==plane_pos.y+4 and attachments[i+3].props.mesh=="flight_gear_up.obj")
assert(not air:get_observers().Rider and air:get_observers().Other and R.exit(a) and not air:get_observers())

local ferry=object({x=8,y=3,z=5})
ferry:set_properties({visual="mesh",mesh="paid_ferry.obj",textures={"ferry.png"}})
local i=#attachments
R.track("ship","coal",ferry,ferry:get_pos(),zero,{running=true,passenger=true})
assert(not R.enter(a,"ride",{kind="ship",id="coal"}))
R.track("ship","ferry",ferry,ferry:get_pos(),zero,{running=true,passenger=true})
assert(R.enter(a,"ride",{kind="ship",id="ferry"}))
assert(attachments[i+2].name=="luanttd_core:ride_ferry_interior" and a:get_attach()==attachments[i+1])
assert(R.controls(a,{place=true}) and R.active(a))
assert(R.exit(a) and not ferry:get_observers() and a:get_pos().y==old_pos.y)

-- Exercise the real Luanti command registration and target fallback,
-- not merely the internal presenter entry point.
local commands,receive={}
core.formspec_escape=tostring
core.close_formspec=function() end
core.register_on_player_receive_fields=function(f) receive=f end
core.register_chatcommand=function(command,def) commands[command]=def end
core.get_player_by_name=function(n) return n=="Rider" and a end
core.get_connected_players=function() return {a,b,c} end
core.raycast=function() return function() end end -- no actor directly under cursor
_G.core=core
api.s,api.Sim={},{}
local V=dofile("mods/luanttd_core/vehicle_ui.lua")(api)
V.ride_track("road",2,bus,bus:get_pos(),zero,{running=true,passenger=true})
V.ride_track("rail",9,cab,cab:get_pos(),zero,{body=7,running=true,engine=true,travel=1})
V.step(.05)
V.remember(a,{kind="road",id=2})
assert(commands.ride.func("Rider","") and V.riding(a))
assert(commands.ride.func("Rider","") and not V.riding(a))
V.remember(a,{kind="rail",id=9})
assert(commands.train.func("Rider","") and V.riding(a))
assert(receive(a,"",{luanttd_leave_ride=true}) and not V.riding(a))
V.ride_track("air",12,air,air:get_pos(),zero,{running=true,passenger=true})
V.ride_track("ship","ferry",ferry,ferry:get_pos(),zero,{running=true,passenger=true})
for _,target in ipairs({air_pick,{kind="ship",id="ferry"}}) do
  V.remember(a,target)
  assert(commands.ride.func("Rider","") and V.riding(a))
  assert(receive(a,"",{luanttd_leave_ride=true}) and not V.riding(a))
end
assert(not commands.train.func("Disconnected",""))
_G.core=nil
print("PASS /ride and /train use the selected real vehicle; repeating the command and the inventory button exit")
_G.vector=nil
print("PASS seated body, private observers, two riders, freelook, hard cull/reappearance, stable train body, touch-like control and exact restore")
