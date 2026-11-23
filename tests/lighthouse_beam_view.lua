local path="mods/luanttd_core/"
local entities,calls={},0
local time,seconds=.5,0
local native_node
local Sim={W=256,H=256,id=function(x,z) return (z-1)*256+x end}
local seen={}
local s={tiles=setmetatable({},{
  __index=function(_,id) seen[id]=true end
})}
local core={
  get_timeofday=function() return time end,
  get_us_time=function() return seconds*1e6 end,
  get_node_or_nil=function(p)
    assert(p.x==20 and p.y==4 and p.z==20)
    return native_node
  end,
  register_entity=function(name,d)
    assert(name=="luanttd_core:lighthouse_beam")
    local p=d.initial_properties
    assert(p.visual=="mesh" and p.use_texture_alpha and not p.pointable and not p.static_save)
    assert(math.abs(p.automatic_rotate*32-2*math.pi)<.001)
    assert(p.visual_size.x==10 and p.visual_size.y==10 and p.visual_size.z==10)
  end,
  add_entity=function(p,name)
    calls=calls+1
    local e={pos=p}
    function e:set_yaw(y) self.yaw=y end
    function e:get_pos() return self.pos end
    function e:remove() self.pos=nil end
    assert(name=="luanttd_core:lighthouse_beam")
    entities[#entities+1]=e
    return e
  end,
}
local view=dofile(path.."lighthouse_beam_view.lua")(core,Sim)
local at={x=20.755,y=4.849,z=20.525}
local id=Sim.id(10,10)
s.tiles[id]={h=3,stock_landmark={kind="lighthouse"}}
s.tiles[Sim.id(10,11)]={h=3,stock_landmark={kind="transmitter"}}
local function step(dt,players)
  view.step(dt or .5,s,players or {at,at})
end
step()
assert(calls==0 and not next(seen),"daylight must not scan terrain or spawn")
time=.02
step()
assert(calls==0,"unpainted tower has no beam")
native_node={name="luanttd_core:stock_lighthouse"}
step()
assert(calls==1 and entities[1].pos.x==at.x and entities[1].pos.y==at.y and entities[1].pos.z==at.z)
local phase=entities[1].yaw
step()
assert(calls==1,"stationary viewer caused the beam to refresh")
step(.5,{{x=at.x+53,y=at.y,z=at.z}})
assert(entities[1].pos,"crossing the enter radius churned an existing beam")
step(.5,{{x=at.x,y=at.y+60,z=at.z}})
assert(not entities[1].pos,"vertical distance did not despawn")
step(.5,{{x=at.x+53,y=at.y,z=at.z}})
assert(calls==1,"new beams must use the smaller enter radius")
seconds=8
step()
assert(calls==2 and math.abs((entities[2].yaw-phase)%(2*math.pi)-math.pi/2)<1e-8)
s.tiles[id]=nil
step()
assert(not entities[2].pos,"an unsubscribed lighthouse must turn off even while the old host node persists")
s.tiles[id]={h=3,stock_landmark={kind="lighthouse"}}
time=.78
step()
assert(calls==3)
time=.765
step(.01)
assert(not entities[3].pos,"sunrise must immediately disable the effect even before the next interest scan")
time=.98
step(.01)
assert(calls==4,"sunset should not wait on an old interest timer")
step(.01,{})
assert(not entities[4].pos,"last viewer departure must release the beam")
local scanned=0
for _ in pairs(seen) do scanned=scanned+1 end
assert(scanned<3000,"lighthouse searched too much of the generated map")
print("PASS lighthouse optics: exact lantern, painted worker tile only, native continuous yaw, night-only, hysteresis and cleanup")
