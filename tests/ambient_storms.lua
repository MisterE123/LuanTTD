local storm=dofile("mods/luanttd_core/ambient_storms.lua")
local step,leave
local effects={}
local function player(name,x)
  local p={name=name,visible=true,at={x=x,y=6,z=5}}
  function p:get_player_name() return self.name end
  function p:get_pos() return self.at end
  function p:get_look_dir() return {x=1,y=.14,z=0} end
  return p
end
local a,b=player("a",0),player("b",0)
local group={a,b}
local core={
  add_particle=function(d) effects[#effects+1]=d end,
  add_particlespawner=function(d) effects[#effects+1]=d end,
  register_globalstep=function(f) step=f end,
  register_on_leaveplayer=function(f) leave=f end,
  get_connected_players=function() return group end,
}
storm.start(core,function(p) return p.visible end)
b.visible=false
step(59);assert(#effects==0,"calm between storms")
for i=1,12 do step(1) end
local rain,cloud,bolt=0,0,0
for _,e in ipairs(effects) do
  assert(e.playername=="a" and e.collisiondetection==false)
  local n=type(e.texture)=="table" and e.texture.name or e.texture
  if n:find("rain") then
    rain=rain+1
    assert(e.amount<=110 and e.minpos.x>=40 and e.maxvel.y<0 and e.maxexptime<=1)
  elseif n:find("cloud") then
    cloud=cloud+1
    assert(e.pos.x>=50 and e.pos.x<=52 and e.expirationtime<=1)
  else
    bolt=bolt+1
    assert(e.expirationtime<=.7 and e.glow<14)
  end
end
assert(rain*2==cloud and rain>0 and rain<=12 and bolt==22,"one sparse lightning strike per interval")
effects={}
a.at.x=40
step(1);assert(#effects==0,"no weather near player approaching a storm")
a.at.x=0;a.visible=false
step(1);assert(#effects==0,"candy toggle stops the effect")
b.visible=true
step(1);assert(#effects>0 and effects[1].playername=="b","opt-out remains individual")
effects={}
leave(b);group={a}
step(20);assert(#effects==0,"storm expires")
b.at.x=0
group={b};effects={}
step(230)
for i=1,12 do step(1) end
assert(#effects>0)
local drizzle=0
for _,e in ipairs(effects) do
  assert(not e.texture.name:find("bolt"))
  if e.amount then assert(e.amount==48);drizzle=drizzle+1 end
end
assert(drizzle>0)
effects={}
step(245)
for i=1,12 do step(1) end
assert(#effects>0)
for _,e in ipairs(effects) do
  assert(not e.amount and e.texture.name:find("mist") and e.velocity.x>0)
end
print("PASS localized cosmetic storms, opt-out, audience, particle bounds, and storm timing")
