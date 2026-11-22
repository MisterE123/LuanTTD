local script=dofile("mods/bayline/passenger_crowd.lua")
local clock,events=0,{}
local last={}
core={
  add_particle=function(p)
    assert(p.playername~=nil and p.vertical and not p.collisiondetection)
    assert(p.velocity.x==0 and p.velocity.y==0 and p.velocity.z==0)
    assert(p.acceleration.x==0 and p.acceleration.y==0 and p.acceleration.z==0)
    assert(p.size>=1.8-1e-9 and p.size<=2.10+1e-9)
    local fade=type(p.texture)=="table"
    local texture=fade and p.texture.name or p.texture
    assert(texture:match("^bl_waiting_[1-6]%.png$"))
    local id=("%s/%.8f/%.8f"):format(p.playername,p.pos.x,p.pos.z)
    if last[id] then assert(last[id].expires<=clock+1e-9,"Duplicate rider in the exact same spot") end
    if fade then
      assert(p.expirationtime==.36 and p.texture.alpha_tween[1]==1 and p.texture.alpha_tween[2]==0)
      assert(last[id] and not last[id].fade and last[id].texture==texture,
        "Boarding fade must replace the now-expired rider at the same position")
    else assert(p.expirationtime>.41 and p.expirationtime<.56) end
    local event={pos=p.pos,who=p.playername,time=clock,expires=clock+p.expirationtime,size=p.size,
      fade=fade,texture=texture}
    last[id]=event
    events[#events+1]=event
  end,
}
local function player(name,x,y,z)
  local p={pos={x=x,y=y,z=z}}
  function p:get_player_name() return name end
  function p:get_pos() return self.pos end
  return p
end
local states={stations={},tiles={}}
local st=states.stations
local function station(id,x,z,c,mode,build)
  states.tiles[id*10]={station=id,build=build or "road_station"}
  st[id]={id=id,tile=id*10,mode=mode or "road",waiting=c,x=x,z=z}
end
station(1,9,12,15)
station(2,10,16,5,"rail")
station(3,29,28,40,"road")
station(4,10,5,9,"road","road")
station(5,10,7,8)
states.tiles[50].station=999
local api={s=states,Sim={waiting_passengers=function(_,at) return at.waiting end},render={}}
function api.render.platform(at)
  return {x=at.x,y=1.5,z=at.z,length=1.70,width=.22,
    side={x=0.0,z=1.0},along={x=1.0,z=0.0}}
end
local scene=script(api)
local a=player("a",9,3,0)
local b=player("b",70,3,70)
local c=player("c",9,40,0)
local view={a,b,c}
local function tick(dt)
  clock=clock+dt
  scene.update(view,dt)
end
local function live(n,fade)
  local count=0
  for _,p in ipairs(events) do
    if p.who==n and p.expires>clock and (fade==nil or p.fade==fade) then count=count+1 end
  end
  return count
end

tick(.02)
assert(#events==15 and live("a")==15 and live("b")==0 and live("c")==0)
local first=events[1]
local first_set={}
for _,e in ipairs(events) do
  assert(math.abs(e.pos.x-st[1].x)<1.70/2 and math.abs(e.pos.z-st[1].z)<.22/2)
  assert(math.abs(e.pos.y-e.size/20-1.504)<1e-9)
  first_set[e.texture.."/"..e.pos.x.."/"..e.pos.z]=true
end
for _=1,100 do tick(.017);assert(live("a")==15 and live("a",true)==0) end
assert(#events>45 and not first_set[events[17].texture.."/"..events[17].pos.x.."/"..events[17].pos.z],
  "Renewed riders should use a new small stationary offset")
assert(first.pos.x~=nil)
local at=#events
st[1].waiting=4
scene.board(st[1],11)
local saw_fade=false
for _=1,62 do
  tick(.017)
  saw_fade=saw_fade or live("a",true)>0
  assert(live("a")<=15, "Fading riders must never stack over original seats")
end
local fades=0
for i=at+1,#events do if events[i].fade then fades=fades+1 end end
assert(saw_fade and fades==11 and live("a")==4 and live("a",true)==0)
local before=#events
st[1].waiting=0
scene.board(st[1],4)
for _=1,65 do tick(.017) end
fades=0
for i=before+1,#events do if events[i].fade then fades=fades+1 end end
assert(fades==4 and live("a")==0)
local seen=#events
for _=1,10 do tick(.05) end
assert(#events==seen)

-- A congested station uses the real curb capacity, and only the nearest
-- four stops draw. Each viewer has a separate, finite particle budget.
for i=10,19 do station(i,10,15+i*.2,99) end
b.pos.x,b.pos.z=10,17
view={b}
scene.leave("a")
tick(.14)
assert(live("b")==128)
local congestion=#events
st[10].waiting=69
scene.board(st[10],30)
for _=1,70 do tick(.021);assert(live("b")<=128) end
local congestion_fades=0
for i=congestion+1,#events do if events[i].fade then congestion_fades=congestion_fades+1 end end
assert(congestion_fades==10 and live("b",false)==128)
scene.leave("b")
view={}
tick(.92)
assert(live("b")==0)
print("PASS: real counts, stationary jittered positions, same-position boarding fades, viewer budget")
