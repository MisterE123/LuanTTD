local M=dofile("mods/bayline/sim.lua")
local done=0
local function check(condition,message) assert(condition,message);done=done+1 end
local function at(x,z) return assert(M.id(x,z)) end
local function empty(s,id,terrain,h)
  s.tiles[id]={terrain=terrain or "grass",h=h or 0,variant=1}
end
local function make(s,tool,list,owner)
  local ok,msg=M.build(s,owner or "A",tool,list)
  assert(ok,msg)
end
local function new()
  local s=M.new(1751)
  M.company(s,"A")
  return s
end
local function passage(s,tool,x1,x2,z,owner)
  local ids=M.line(at(x1,z),at(x2,z))
  make(s,tool,ids,owner)
end
local function station(s,tool,id,owner)
  make(s,tool,{id},owner)
  return s.tiles[id].station
end
local function dispatch(s,engine,cargo,a,b,action,owner)
  owner=owner or "A"
  local id,err=M.purchase(s,owner,engine,cargo,a)
  assert(id,err)
  assert(M.add_order(s,owner,id,b,action))
  assert(M.toggle(s,owner,id))
  return s.fleet[id]
end
local function advance(s,n)
  for _=1,n do M.daily(s) end
end
do
  for seed=1,100 do
    local s=M.new(seed)
    local dry=0
    for _,t in ipairs(s.tiles) do if t.terrain=="grass" then dry=dry+1 end end
    assert(#s.tiles==1728 and #s.sites==12 and dry>650)
    assert(M.demo(s,"A"))
    advance(s,24)
    assert(s.companies.A.revenue>0 and s.companies.A.units>=30)
    assert(s.subsidies[1].owner=="A")
    assert(not M.demo(s,"A"))
  end
  check(true,"100 distinct procedural seeds supported the starter line and first payment")
end
do
  local s=new()
  local cash=s.companies.A.cash
  local a,b=at(9,6),at(10,6)
  empty(s,a);empty(s,b,"water")
  check(not M.build(s,"A","road",{a,b}),"unbridged water should reject entire line")
  check(not s.tiles[a].build and s.companies.A.cash==cash,"failed line modified state")
  make(s,"road_bridge",{a,b})
  check(s.tiles[a].build=="road" and s.tiles[b].build=="road_bridge")
  check(not M.build(s,"B","clear",{a}),"competitor may not clear owned road")
  check(not M.build(s,"A","rail_station",{at(47,30)}),"remote station has no catchment")
  local h=at(13,6);empty(s,h,"hill",2)
  check(not M.build(s,"A","rail",{h}))
  make(s,"grade",{h});make(s,"rail_tunnel",{h})
  check(s.tiles[h].h==1 and s.tiles[h].build=="rail_tunnel")
  check(M.loan(s,"A",10000) and M.loan(s,"A",-10000))
  check(not M.loan(s,"A",123))
end
do
  local s=new()
  for x=6,17 do empty(s,at(x,18)) end
  passage(s,"rail",6,17,18)
  local a,b=station(s,"rail_station",at(6,18)),station(s,"rail_station",at(17,18))
  check(#M.path(s,s.stations[a],s.stations[b],"rail","A")==12)
  make(s,"signal",{at(11,18)})
  assert(M.signal(s,"A",at(11,18)))
  local v=dispatch(s,"steam","coal",a,b)
  local another=dispatch(s,"steam","coal",b,a)
  advance(s,3)
  check(not v.route and not another.route and v.status=="Waiting for clear track")
  assert(M.signal(s,"A",at(11,18)))
  advance(s,1)
  check((v.route~=nil)~=(another.route~=nil),"only one opposing train may reserve the single track")
  check(not M.build(s,"A","clear",{at(10,18)}),"refuse deletion underneath a reserved path")
  check(not M.edit_order(s,"A",v.id,1,"remove"))
  for _=1,80 do
    M.daily(s)
    check(not (v.route and another.route) or (table.concat(v.route,",")==table.concat(another.route,",") and math.abs(v.progress-another.progress)>=2),"unsafe train route overlap")
  end
  check(s.sites[7].stock.steel>0 and s.companies.A.revenue>0 and another.delivered>0)
  check(#s.companies.A.history==2)
  check(s.subsidies[2].owner=="A")
  check(not M.build(s,"A","clear",{s.stations[a].tile}))
end
do
  local s=new()
  empty(s,at(22,8));empty(s,at(25,8));empty(s,at(23,8),"water");empty(s,at(24,8),"water")
  -- Pin Eastport's position for the isolated water fixture.
  s.sites[3].tile=at(28,9)
  local a,b=station(s,"dock",at(22,8)),station(s,"dock",at(25,8))
  local v=dispatch(s,"ferry","passenger",a,b)
  advance(s,24)
  check(v.delivered>0,"ferry delivery")
end
do
  local s=new()
  for _,p in ipairs({{9,11},{31,11}}) do empty(s,at(p[1],p[2])) end
  local a,b=station(s,"airport",at(9,11)),station(s,"airport",at(31,11))
  local v=dispatch(s,"prop","mail",a,b)
  advance(s,35)
  check(v.delivered>0 and s.companies.A.revenue>0,"air delivery")
  check(not M.purchase(s,"A","jet","mail",a),"1950 jet shouldn’t exist")
  s.day=12*360
  check(M.purchase(s,"A","jet","mail",a),"1962 jet should be available")
end
do
  local s=new()
  for x=6,17 do empty(s,at(x,18)) end
  passage(s,"road",6,17,18)
  local a,b=station(s,"road_station",at(6,18)),station(s,"road_station",at(17,18))
  local v=dispatch(s,"truck","coal",a,b,"transfer")
  local c=s.companies.A
  advance(s,15)
  check(v.delivered==0 and c.revenue==0,"transfer must not create money")
  check(s.stations[b].stock.coal and #s.stations[b].stock.coal>0)
  empty(s,at(17,17));empty(s,at(17,19))
  local ar=station(s,"rail_station",at(17,17))
  local br=station(s,"rail_station",at(17,19))
  -- Route around the road corridor through x=18.
  for z=17,19 do empty(s,at(18,z)) end
  make(s,"rail",{at(18,17),at(18,18),at(18,19)})
  local w=dispatch(s,"steam","coal",ar,br)
  advance(s,20)
  check(w.delivered>0 and c.revenue>0,"cross-mode pickup delivered transferred stock")
end
do
  local s=new()
  -- Make a long flat signaled corridor between three original towns.
  for x=8,31 do empty(s,at(x,12)) end
  passage(s,"rail",8,31,12)
  local a=station(s,"rail_station",at(8,12))
  local b=station(s,"rail_station",at(31,12))
  make(s,"signal",{at(21,12)})
  local leader=dispatch(s,"steam","passenger",a,b)
  local follower=dispatch(s,"steam","passenger",a,b)
  local third=dispatch(s,"steam","passenger",a,b)
  local convoy=false
  for _=1,12 do
    M.daily(s)
    if leader.route and follower.route then
      convoy=true
      check(leader.progress-follower.progress>=2,"same-direction headway")
    end
    if follower.route and third.route then
      check(follower.progress-third.progress>=2,"headway also applies to the third train")
    end
  end
  check(convoy,"signals allow several trains on the same directed corridor")
  local reverse=dispatch(s,"steam","passenger",b,a)
  local used_other_way=false
  for _=1,74 do
    M.daily(s)
    local direction
    for _,v in pairs(s.fleet) do
      if v.route then
        local d=v.route[1]<v.route[#v.route]
        assert(direction==nil or direction==d,"opposing trains must not share this corridor")
        direction=d
      end
    end
    if reverse.route then used_other_way=true end
  end
  check(used_other_way and reverse.delivered>0,"reverse traffic gets its turn")
end
do
  local s=new()
  for x=8,31 do empty(s,at(x,12)) end
  passage(s,"rail",8,31,12)
  local a=station(s,"rail_station",at(8,12))
  local b=station(s,"rail_station",at(31,12))
  local lead=dispatch(s,"steam","passenger",a,b)
  local follow=dispatch(s,"steam","passenger",a,b)
  advance(s,8)
  check(lead.route and not follow.route,"no following without a signal")
end
do
  local s=new()
  local first,last,depot=at(9,12),at(18,12),at(9,13)
  empty(s,depot)
  check(not M.build(s,"A","road_depot",{depot}),"depot requires a road connection")
  passage(s,"road",9,18,12)
  local a=station(s,"road_station",first)
  local b=station(s,"road_station",last)
  make(s,"road_depot",{depot})
  local id=assert(M.purchase(s,"A","bus","passenger",nil,depot))
  local v=s.fleet[id]
  check(v.depot==depot and #v.orders==0 and not v.running,"purchase starts parked without orders")
  check(not M.build(s,"A","clear",{depot}),"occupied depot is protected")
  check(not M.purchase(s,"B","bus","passenger",nil,depot),"cannot buy at another company's depot")
  check(not M.toggle(s,"A",id),"no dispatch without orders")
  check(M.add_order(s,"A",id,a))
  check(not M.add_order(s,"A",id,a),"reject successive duplicate orders")
  check(M.add_order(s,"A",id,b))
  check(M.toggle(s,"A",id))
  M.daily(s)
  check(v.route and v.route[1]==depot and v.dest==a and not v.depot,"first trip starts at the depot")
  advance(s,25)
  check(v.delivered>0 and v.last_fare and v.last_fare.amount>0,"depot service pays after real delivery")
end
io.write(("PASS: %d assertions, including 100 generated starts and all four modes\n"):format(done))
