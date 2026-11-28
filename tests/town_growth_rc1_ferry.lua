-- A fresh RC1 port, not an imported save: use production world generation
-- and the ordinary worker's quote, buy, order and company commands.
local ref=dofile("tests/fixtures/rc1-active-ferry-town-year.lua")
local mod="mods/luanttd_core"
local function m(n) return dofile(mod.."/"..n..".lua") end
local S,T,Rebuild=m("sim"),m("openttd/terrain"),m("openttd/town_rebuild")
local native_files={settings={get=function() return nil end},get_dir_list=function(path)
  local list={}
  local stream=assert(io.popen("ls -1 "..path))
  for name in stream:lines() do list[#list+1]=name end
  stream:close()
  return list
end}
local s=m("campaign_generation")(native_files,mod,S,m("world_setup")).run({
  width=256,depth=256,year=1985,seed=1751,relief=0,sea=0,coast=0,rivers=2,trees=2,
  towns=3,larger_towns=4,industries=4,variety=0,smooth=1,layout="original",growth_rate=2,
})
local cap={road={start_year=1985,breakdowns=1,service_interval=150,foster=true},ferry={[207]=true},air={},oil_tanker=true}
s.road_coal,s.road_timber,s.road_farm,s.road_oil,s.road_heavy=true,true,true,true,true
s.ship_paid_service=true
local Mount,Endpoint,Codec=m("campaign_authority_runtime"),m("campaign_authority_endpoint"),m("packed_campaign")
local N=Mount(S,mod,s,cap)
local A=Endpoint(S,N)
local revision
local owner="Stock comparison"
local function checked(r)
  assert(r.ok,r.why)
  revision=r.revision
  return r.value
end
local function action(kind,request)
  request=request or {}
  request.kind,request.revision=kind,revision
  return checked(A.command(owner,request))
end
local function transport(request)
  local quote=checked(A.transport_quote(owner,request))
  return action("transport_commit",{token=quote.token})
end
local function build()
  action("company_open")
  s.companies[owner].cash=80000000
  local a=transport({mode="ship",operation="build",kind="dock",tile=29757,separate=true}).id
  local b=transport({mode="ship",operation="build",kind="dock",tile=31026,separate=true}).id
  assert(s.stock_ship_stations[a].stock_station_id==0 and s.stock_ship_stations[b].stock_station_id==1)
  local d=transport({mode="ship",operation="build",kind="depot",tile=29760,axis=0}).id
  assert(transport({mode="ship",operation="buy",depot=d,engine=207}).id=="ferry")
  assert(s.stock_owned_ferry.stock_pool_id==12)
  action("transport_start",{mode="ship",vehicle="ferry",depot=d,first=a,second=b})
end

local function fold(h,...)
  for i=1,select("#",...) do h=(h*65599+select(i,...))%2147483647 end
  return h
end
local function same(tick,label,value,expected)
  assert(#value==#expected)
  for i,v in ipairs(expected) do
    assert(value[i]==v,("RC1 ferry tick %d %s field %d: got %s; expected %s"):format(
      tick,label,i,tostring(value[i]),tostring(v)))
  end
end
local function snapshot(tick,expected)
  local corners,houses,towns=1,1,1
  local year=S.date(s)
  local book=s.stock_town_growth.towns
  for id,t in ipairs(s.tiles) do
    local x,y=S.xy(id)
    corners=fold(corners,T.corner(s.corner_grid,x,y))
    local h=t.source_house
    if h then houses=fold(houses,id-1,h.id,(book[h.town].stock_id or h.town-1),h.completed and 1 or 0,h.stage,h.counter,
      Rebuild.age(h,year),h.random_bits) end
  end
  for _,id in ipairs(s.stock_town_growth.order) do
    local town,site=book[id],s.sites[id]
    local p,m=town.supplied.passenger,town.supplied.mail
    towns=fold(towns,town.stock_id or id-1,site.tile-1,town.population,town.num_houses,town.grow_counter,
      town.growth_rate,town.time_until_rebuild,p.new_max or 0,p.new_act or 0,p.old_max or 0,p.old_act or 0,
      m.new_max or 0,m.new_act or 0,m.old_max or 0,m.old_act or 0)
  end
  same(tick,"ground, housing and town state",{corners,houses,towns},expected)
end

local digest,motion,ticks,poses,snapshots=1,1,0,0,0
local function tick(t)
  if t==ref.first then same(t,"startup",{#s.stock_town_growth.order,unpack(s.passenger_rating_rng)},ref.startup) end
  if t==ref.build then build() end
  digest=fold(digest,t,unpack(s.passenger_rating_rng));ticks=ticks+1
  if ref.towns[t] then snapshot(t,ref.towns[t]);snapshots=snapshots+1 end
  if t<=ref.build then return end
  local p,u=assert(s.ship_pilot),s.stock_owned_ferry
  assert(p.phase~="blocked",p.failure)
  local v=p.vehicle
  local c=s.stock_ship_commercial
  local cargo=c and c.service.vehicles[p.paid_clock]
  local row={u.stock_pool_id,v.tile-1,v.x-16,v.y-16,v.z,v.speed,v.subspeed or 0,v.progress,v.direction,
    cargo and cargo.units or 0,v.loading and 1 or 0,v.hidden and 1 or 0}
  motion=fold(motion,t,unpack(row));poses=poses+1
  if ref.sample[t] then same(t,"ferry pose and cargo",row,ref.sample[t]) end
  if ref.health[t] then same(t,"physical economy phase",
    {u.stock_pool_id,u.stock_fault.reliability,u.stock_fault.breakdown_chance},ref.health[t]) end
end

for day=1,365 do
  if day==51 or day==111 or day==233 then
    s=assert(Codec.decode(Codec.encode(s)))
    N=Mount(S,mod,s,cap)
    A=Endpoint(S,N)
    revision=s.authority_revision or 0
  end
  N.day(tick)
end
same(ref.last,"year end",{ticks,digest,poses,motion,snapshots},{ref.last-ref.first+1,ref.rng,ref.last-ref.build,ref.motion,6})
local p=s.ship_pilot
local freight=s.stock_ship_commercial.service.vehicles[p.paid_clock]
assert((freight.boarded or 0)>0 and freight.units>0 and s.stock_owned_ferry.price>0)
-- This seeded two-dock route generates passengers but neither dock
-- has the eight acceptance eighths required to collect a fare.
assert((s.companies[owner].paid_units or 0)==0)
print(("PASS RC1 owned ferry: %d world RNG ticks, %d ship pose/cargo ticks, six snapshots of 51 towns and three packed reloads")
  :format(ticks,poses))
