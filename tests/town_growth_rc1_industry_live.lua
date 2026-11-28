-- Real 16.0-RC1 Normal industry/rivers, four towns and default subsidies.
-- Source tick traces and save snapshots through the first running year,
-- without a company and with one newly opened human company. No routes.
local expected={
  {{1281,7541,1469947224,2242462710,815929123,1755659935,606552607,1895352048},{5931,477080829,0,0,11269,10,17,24,10,12},{11571,3683487949,1,0,5669,10,64,88,25,44},{1890,4280403754,0,1,11269,10,14,30,8,15},{13708,1201640385,0,2,11269,10,44,84,20,42}},
  {{1354,331,1971220149,1006027529,815929123,979708375,305615703,1895352048},{5931,477080829,0,0,11269,10,19,24,10,12},{11571,3683487949,1,0,5669,10,69,88,27,44},{1890,4280403754,0,1,11269,10,14,30,8,15},{13708,1201640385,0,2,11269,10,48,84,20,42}},
  {{3574,6145,1992897415,1645079432,815929123,1240953723,1567645,1895352048},{5931,477080829,0,0,11269,10,0,49,0,21},{11571,3683487949,1,0,5669,10,0,171,0,77},{1890,4280403754,0,1,11269,10,0,54,0,21},{13708,1201640385,0,2,11269,10,0,146,0,56}},
  {{5646,873,3356907187,3634553275,815929123,997650306,576288490,1895352048},{5931,477080829,0,0,11269,10,0,40,0,13},{11571,3683487949,1,0,5669,10,0,99,0,41},{1890,4280403754,0,1,11269,10,0,33,0,14},{13708,1201640385,0,2,11269,10,0,117,0,51}},
  {{7940,9366,2810378813,1763362360,815929123,32571012,28744566,1895352048},{5931,477080829,0,0,11269,10,0,33,0,19},{11571,3683487949,1,0,5669,10,0,81,0,46},{1890,4280403754,0,1,11269,10,0,35,0,19},{13708,1201640385,0,2,11269,10,0,137,0,68}},
  {{10160,12061,303337152,369300715,815929123,1538157168,28744566,1895352048},{5931,477080829,0,0,11269,10,0,33,0,16},{11571,3683487949,1,0,5669,10,0,113,0,51},{1890,4280403754,0,1,11269,10,0,46,0,17},{13708,1201640385,0,2,11269,10,0,149,0,75}},
  {{12454,12945,4007647140,1002764322,815929123,1093106023,28744566,1895352048},{5931,477080829,0,0,11269,10,0,28,0,14},{11571,3683487949,1,0,5669,10,0,106,0,52},{1890,4280403754,0,0,11269,10,0,40,0,14},{13708,1201640385,0,2,11269,10,0,154,0,51}},
  {{14674,3656,2965021880,599800745,815929123,100474282,1702281079,1895352048},{5931,477080829,0,0,11269,10,0,39,0,20},{11571,3683487949,1,0,5669,10,0,99,0,53},{1890,4280403754,0,9051,11269,131,0,31,0,12},{13708,1201640385,0,2,11269,10,0,137,0,50}},
  {{16968,4743,2362518800,4072226223,815929123,496168809,1227036937,1895352048},{5931,477080829,0,0,11269,10,0,48,0,17},{11571,3683487949,1,0,5669,10,0,116,0,44},{1890,4280403754,0,9051,11269,131,0,32,0,22},{13708,1201640385,0,2,11269,10,0,149,0,73}},
  {{19262,930,30384888,3969908000,815929123,900471199,2022899063,1895352048},{5931,477080829,0,69,11269,10,0,30,0,21},{11571,3683487949,1,0,5669,10,0,94,0,50},{1890,4280403754,0,9050,11269,131,0,39,0,18},{13708,1201640385,0,2,11269,10,0,150,0,66}},
  {{21482,12571,2254188919,1175546055,815929123,1298980659,2012339253,1895352048},{5931,477080829,0,9190,11269,182,0,27,0,10},{11571,3683487949,1,0,5669,10,0,107,0,47},{1890,4280403754,0,6831,11269,27,0,56,0,22},{13708,1201640385,0,2,11269,10,3,144,1,56}},
  {{23776,15490,3997594769,1285327339,815929123,85015052,1496134482,1895352048},{5931,477080829,0,9190,11269,182,0,42,0,14},{11571,3683487949,1,0,5669,10,0,91,0,46},{1890,4280403754,0,6831,11269,27,0,28,0,16},{13708,1201640385,0,2,11269,10,0,151,0,67}},
  {{25996,8009,2491137328,2400595644,815929123,256151601,1366794291,1895352048},{5931,477080829,0,9190,11269,182,0,38,0,14},{11571,3683487949,1,69,5669,10,0,119,0,61},{1890,4280403754,0,6831,11269,27,0,33,0,13},{13708,1201640385,0,2,11269,10,0,125,0,51}},
  {{28290,7305,48255024,2016678500,815929123,1643436274,204586389,1895352048},{5931,477080829,0,9190,11269,182,0,39,0,18},{11571,3683487949,1,3586,5669,156,0,98,0,37},{1890,4280403754,0,6831,11269,27,0,40,0,22},{13708,1201640385,0,1,11269,10,0,141,0,66}},
}
local function compare(with_company,expected,source_digest)
  local check={}
  for _,sample in ipairs(expected) do check[sample[1][1]]=sample end
  local F=dofile("tests/town_growth_rc1_industry_start.lua")
  local Sim,T,s,mod=F.Sim,F.Terrain,F.world,F.mod
  local Rebuild=dofile(mod.."/openttd/town_rebuild.lua")
  local mount,Codec=dofile(mod.."/campaign_authority_runtime.lua"),dofile(mod.."/packed_campaign.lua")
  local cap={road={start_year=1950,breakdowns=1,service_interval=150},ferry={},air={},oil_tanker=true}
  -- The same industry chain admissions as init.lua, all five proven present
  -- in this actual generated map. There are no owned services to mount.
  s.road_coal,s.road_timber,s.road_farm,s.road_oil,s.road_heavy=true,true,true,true,true
  local owner=mount(Sim,mod,s,cap)
  local Endpoint=dofile(mod.."/campaign_authority_endpoint.lua")
  local name="Stock reference company"
  local function open_comp()
    local A=Endpoint(Sim,owner)
    local reply=A.command(name,{kind="company_open"})
    assert(reply.ok,reply.why)
  end
  if with_company then
    open_comp()
    local c=assert(s.companies[name])
    local b=assert(c.stock_start)
    assert(b.id==0 and b.year==1950 and b.colour==8 and b.face_style==2 and b.face_bits==304505525)
    assert(b.president=="B. Gordon" and b.president_seed==1497927443)
    assert(c.cash==100000 and c.loan==100000)
    assert(s.passenger_rating_rng[1]==1594137858 and s.passenger_rating_rng[2]==1497927443)
    open_comp() -- reconnecting must not reroll a company's identity
  end
  local function fold(h,...)
    for i=1,select("#",...) do h=(h*65599+select(i,...))%2147483647 end
    return h
  end
  local function eq(a,b,tick,k)
    assert(a==b,("RC1 live tick %d %s, got %s expected %s"):format(tick,k,tostring(a),tostring(b)))
  end
  local function same(tick,k,a,b)
    assert(#a==#b)
    for i,v in ipairs(b) do eq(a[i],v,tick,k.." "..i) end
  end
  local digest,seen,snapshots=1,0,0
  local function observe(tick)
    digest=fold(digest,tick,unpack(s.passenger_rating_rng))
    seen=seen+1
    local ref=check[tick]
    if not ref then return end
    local hh,tt,house,road=1,1,1,1
    local year=Sim.date(s)
    for id,t in ipairs(s.tiles) do
      local x,z=Sim.xy(id)
      local typ=t.stock_void and 7 or t.stock_industry and 8 or t.stock_landmark and 10 or t.wood and 4
        or t.terrain=="water" and 6 or t.build=="road" and 2 or t.source_house and 3 or 0
      hh=fold(hh,T.corner(s.corner_grid,x,z));tt=fold(tt,typ)
      local r=t.source_house
      if r then house=fold(house,id-1,r.id,r.town-1,r.completed and 1 or 0,r.stage,r.counter,Rebuild.age(r,year),r.random_bits) end
      if typ==2 then road=fold(road,id-1,t.road_bits,t.road_town-1) end
    end
    same(tick,"map/timer",{tick,s.passenger_house_clock.head,s.passenger_rating_rng[1],s.passenger_rating_rng[2],
      hh,tt,house,road},ref[1])
    for i,t in ipairs(s.stock_town_growth.towns) do
      local site=s.sites[i]
      local p,q=t.supplied.passenger,t.supplied.mail
      same(tick,"town "..i,{site.tile-1,site.nameparts,t.larger_town and 1 or 0,t.grow_counter,t.growth_rate,
        t.time_until_rebuild,p.new_max,p.old_max,q.new_max,q.old_max},ref[i+1])
    end
    snapshots=snapshots+1
  end
  for day=1,365 do
    if day==32 or day==138 or day==267 then
      s=assert(Codec.decode(Codec.encode(s)))
      owner=mount(Sim,mod,s,cap)
      if with_company then
        local b=assert(s.companies[name].stock_start)
        assert(b.id==0 and b.president_seed==1497927443)
        local a,b=unpack(s.passenger_rating_rng)
        open_comp()
        assert(s.passenger_rating_rng[1]==a and s.passenger_rating_rng[2]==b)
      end
    end
    owner.day(observe)
  end
  assert(seen==27010 and snapshots==14)
  eq(digest,source_digest,28290,"27010-tick digest")
  print("PASS Normal-industry live region ("..(with_company and "one idle company" or "no company").."): 27,010 matching RC1 ticks, 14 map and town cargo/clock snapshots, three packed reopens")
end
compare(false,expected,859417629)
compare(true,dofile("tests/fixtures/rc1-stock-company-town-year.lua"),1679927514)

-- Run the separate ordinary dual-service replay in the same CI job.
dofile("tests/town_growth_rc1_corridor.lua")
