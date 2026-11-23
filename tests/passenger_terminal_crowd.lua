-- Mixed namespaces, real station queue API, model-specific placement,
-- same-position fading, and no advance fabrication at freight terminals.
local root="mods/luanttd_core/"
local function mod(name) return dofile(root..name..".lua") end
local Sim=mod("sim")
local s=Sim.new(1751)
Sim.mount_paid_ferry(s,{})
s.road_stock_house_supply=true
s.corner_grid={}
s.ship_paid_service,s.rail_paid_service,s.air_paid_service=true,true,true
local time,events=0,{}
core={
  get_modpath=function(name) assert(name=="luanttd_core");return root end,
  add_particle=function(p)
    assert(p.velocity.x==0 and p.velocity.y==0 and p.velocity.z==0 and
      p.acceleration.x==0 and p.acceleration.y==0 and p.acceleration.z==0)
    assert(p.size>=1.799 and p.size<=2.101 and p.vertical and not p.collisiondetection)
    events[#events+1]={at=time,p=p,fade=type(p.texture)=="table"}
  end,
}
local at=Sim.id
local function ground(x,z,more)
  local id=at(x,z)
  s.tiles[id]=more
  more.h=2
  return id
end
s.stations={[1]={id=1,mode="road",waiting=3,tile=ground(5,8,{build="road_station",station=1})},
  [2]={id=2,mode="road",waiting=99,stop_type="truck",tile=ground(7,8,{build="road_station",station=2})}}
s.stock_rail_stations={
  [1]={owner="A",tiles={ground(5,10,{owner="A",rail_station_id=1,rail_station_axis=0,rail_tracks=1}),
    ground(6,10,{owner="A",rail_station_id=1,rail_station_axis=0,rail_tracks=1})}},
  [2]={owner="A",coal_role="load",tiles={ground(7,10,{owner="A",rail_station_id=2,rail_station_axis=1,rail_tracks=2})}},
}
s.stock_ship_stations={
  [1]={water=ground(6,13,{ship={dir=1,station=1,kind="dock",water_part=true}})},
  [2]={water=ground(7,13,{ship={dir=0,station=2,kind="dock",water_part=true}})},
}
s.stock_coal_ship={mine=2}
s.stock_small_airports={[1]={tiles={
  {x=0,z=0,id=ground(5,15,{airfield={airport=1}})},
  {x=1,z=0,id=ground(6,15,{airfield={airport=1}})},
  {x=1,z=1,id=ground(6,16,{airfield={airport=1}})},
}}}
local count={ship=8,rail=12,air=7}
local stations={}
local keys={ship=1,rail=0x4001,air=0xC001}
for mode,key in pairs(keys) do
  -- Real paid-runtime and packets waiting functions, but a controlled
  -- serialized payload to avoid tying this visual QA to route topology.
  for i=0,1 do stations[key+i]={host_id=1+i,host_mode=mode,loading_order={},
    stock={passenger={{units=i==0 and count[mode] or 99}}}} end
end
s.stock_ship_commercial={service={stations=stations,vehicles={}}}
-- People reserved for a train are still waiting until a boarding slice
-- really transfers them from the platform into the vehicle.
stations[keys.rail].stock.passenger[1].units=count.rail-2
stations[keys.rail].loading_order={7}
local live_boarding={cargo="passenger",load_state={reserved_units=2}}
s.stock_ship_commercial.service.vehicles[7]=live_boarding
assert(Sim.commercial_passengers_waiting(s,"rail",1)==count.rail)
-- A real mixed train reserves two passenger packets and seven bags.
-- Passenger silhouettes include the reserved people, never Mail.
live_boarding.cargo="mixed"
live_boarding.carrying_parts={
  {cargo="passenger",load_state={reserved_units=2}},
  {cargo="mail",load_state={reserved_units=7}},
}
for mode,c in pairs(count) do
  assert(Sim.commercial_passengers_waiting(s,mode,1)==c,mode)
end
local api={s=s,Sim=setmetatable({
  waiting_passengers=function(_,st) return st.waiting end,
},{__index=Sim}),terrain={tile=function(id)return 0,s.tiles[id].h end},
  trackworks={surface=function(_,height)return 0,height end},
  render={platform=function(st)
    local x,z=Sim.xy(st.tile)
    return {x=x*2+.5,y=2.56,z=z*2+.5,length=1.7,width=.22,
      along={x=1,z=0},side={x=0,z=1}}
  end}}
local C=mod("passenger_crowd")(api)
local p={get_player_name=function()return "p" end,get_pos=function()return{x=11,y=4,z=23}end}
local function tick(dt) time=time+dt;C.update({p},dt) end
local function classify(p)
  local x,z=p.pos.x,p.pos.z
  if z<18 then assert(x<12 and z>16);return "road",2.56 end
  if z<23 then
    assert(z>=20.5+.55 and z<=20.5+.68 and x>9.52 and x<13.5)
    return "rail",2.78
  end
  if z<29 then
    assert(math.abs(x-12.58)<.17 and math.abs(z-26.5)<.74)
    return "ship",2.673
  end
  assert(math.abs(z-31.16)<.11 and x>9.55 and x<13.3)
  return "air",2.505
end
local fades={}
local function check()
  local live={}
  for _,e in ipairs(events) do
    local m,base=classify(e.p)
    assert(math.abs(e.p.pos.y-e.p.size/20-base-.004)<1e-8)
    if not e.fade and e.at+e.p.expirationtime>time then live[m]=(live[m] or 0)+1 end
  end
  return live
end
tick(.01)
local live=check()
assert(live.road==3 and live.rail==12 and live.ship==8 and live.air==7)
local before=#events
for mode,key in pairs(keys) do
  stations[key].stock.passenger[1].units=count[mode]-3-(mode=="rail" and 2 or 0)
  C.board_terminal(mode,1,1)
  C.board_terminal(mode,1,2)
end
for _=1,65 do tick(.02) end
live=check()
assert(live.road==3 and live.rail==9 and live.ship==5 and live.air==4)
for i=before+1,#events do
  local e=events[i]
  if e.fade then
    local m=classify(e.p)
    fades[m]=(fades[m] or 0)+1
    assert(e.p.expirationtime==.36 and e.p.texture.alpha_tween[1]==1 and e.p.texture.alpha_tween[2]==0)
  end
end
assert(not fades.road and fades.rail==3 and fades.ship==3 and fades.air==3)
print("PASS: authoritative mixed-mode queues and spatially distinct platform/pier/concourse fades")
