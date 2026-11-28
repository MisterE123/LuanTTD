local mod="mods/luanttd_core"
local function m(n)return dofile(mod.."/"..n..".lua")end
local Sim,T,G=m("sim"),m("openttd/terrain"),m("openttd/town_growth")
local C,Codec=m("campaign_generation"),m("packed_campaign")
local settings=m("world_setup")
local cap={road={start_year=1950,breakdowns=1,service_interval=150},ferry={},air={},oil_tanker=true}
local ref=dofile("tests/fixtures/rc1-manual-founded-year.lua")
local core={settings={get=function() return nil end},get_dir_list=function(path)
  local out={}
  local p=assert(io.popen("ls -1 "..path))
  for line in p:lines() do out[#out+1]=line end
  p:close()
  return out
end}
local s=C(core,mod,Sim,settings).run({
  width=128,depth=128,year=1950,seed=1751,relief=1,sea=0,coast=16,rivers=2,
  trees=2,towns=4,custom_towns=4,larger_towns=3,industries=0,variety=0,smooth=1,layout="original",growth_rate=2,found_town=2,
})
local mount,Endpoint=m("campaign_authority_runtime"),m("campaign_authority_endpoint")
local runtime=mount(Sim,mod,s,cap)
local A=Endpoint(Sim,runtime)
s.stock_economy_subsidies.duration=0
local req={tile=Sim.id(69,64),size="medium",city=true,layout="random",name="Rivermark",nameparts=0xC0FFEE}
assert(not A.town_found_quote("Builder",req).ok,"A company is required")
assert(A.command("Builder",{kind="company_open"}).ok)
local rng=s.passenger_rating_rng
local before={rng[1],rng[2],s.topology}
local opts=s.stock_generated_profile.town_settings
local function policy(n)
  local prior=s.authority_revision or 0
  local change={kind="town_founding_setting",policy=n,revision=prior}
  assert(not A.command("Visitor",change).ok and (s.authority_revision or 0)==prior)
  assert(A.command("Builder",change).ok and opts.founding_policy==n)
end
policy(0)
assert(not A.town_found_quote("Builder",req).ok)
policy(1)
assert(not A.town_found_quote("Builder",req).ok,"Allowed mode must use the world's default road layout")
policy(2)
local quote=A.town_found_quote("Builder",req)
assert(quote.ok and quote.value.cost==26250000 and not quote.value.affordable and quote.value.resolved_layout=="grid2")
local cmd={kind="town_found",request=req,cost=quote.value.cost,revision=quote.revision}
assert(not A.command("Builder",cmd).ok,"No cash for founding")
for _,entry in ipairs{{"size","large"},{"size",true},{"tile",1},{"tile",s.sites[1].tile},{"name",string.rep("a",32)}} do
  local key,value=unpack(entry)
  local before=req[key]
  req[key]=value
  assert(not A.town_found_quote("Builder",req).ok)
  req[key]=before
end
assert(#s.sites==4 and rng[1]==before[1] and rng[2]==before[2] and s.topology==before[3])
s.companies.Builder.cash=80000000
assert(not Sim.road_tree_authority().nearest_in(s,req.tile,20))
local found=A.command("Builder",cmd)
assert(found.ok,found.why)
local town,snapshot_count=found.value,0
assert(town.id==5 and town.name=="Rivermark" and town.population==804)
assert(Sim.road_tree_authority().nearest_in(s,req.tile,20).id==5)
assert(s.companies.Builder.cash==53750000 and s.companies.Builder.expense==26250000)
assert(not A.command("Builder",cmd).ok,"A found-town receipt cannot be replayed")
assert(not A.town_found_quote("Builder",req).ok,"Cannot reuse a custom name or crowd a town")

local function fold(h,...)
  for i=1,select("#",...) do h=(h*65599+select(i,...))%2147483647 end
  return h
end
local Rebuild=m("openttd/town_rebuild")
local function compare(got,expected,label)
  assert(#got==#expected)
  for i,v in ipairs(expected) do assert(got[i]==v,("%s field %d, found %s want %s"):format(label,i,tostring(got[i]),v)) end
end
local seen,digest=0,1
local function observe(tick)
  if tick>1280 then
    seen=seen+1
    digest=fold(digest,tick,unpack(s.passenger_rating_rng))
  end
  local expected=ref[tick]
  if not expected then return end
  local tmp={1,1,1,1,1}
  local year=Sim.date(s)
  for id,t in ipairs(s.tiles) do
    local x,z=Sim.xy(id)
    local br,tu=t.road_bridge_id,t.road_tunnel_id
    local class=t.stock_void and 7 or t.stock_industry and 8 or t.stock_landmark and 10 or t.wood and 4
      or (br or tu) and 9 or t.terrain=="water" and 6 or t.build=="road" and 2 or t.source_house and 3 or 0
    tmp[1]=fold(tmp[1],T.corner(s.corner_grid,x,z));tmp[2]=fold(tmp[2],class)
    local h=t.source_house
    if h then tmp[3]=fold(tmp[3],id-1,h.id,h.town-1,h.completed and 1 or 0,h.stage,h.counter,Rebuild.age(h,year),h.random_bits) end
    if class==2 then tmp[4]=fold(tmp[4],id-1,t.road_bits,t.road_town and t.road_town-1 or -1) end
    if class==9 then
      local span=br and s.stock_road_bridges[br] or s.stock_road_tunnels[tu]
      local u,v=Sim.xy(id==span.start and span["end"] or span.start)
      tmp[5]=fold(tmp[5],id-1,br and 1 or 0,u>x and 2 or u<x and 0 or v>z and 1 or 3)
    end
  end
  compare({s.passenger_house_clock.head,s.passenger_rating_rng[1],s.passenger_rating_rng[2],unpack(tmp)},expected[1],"Map tick "..tick)
  for i,t in ipairs(s.stock_town_growth.towns) do
    local site=s.sites[i]
    local p,q=t.supplied.passenger,t.supplied.mail
    local layouts={original=0,better=1,grid2=2,grid3=3}
    compare({site.tile-1,site.nameparts,t.larger_town and 1 or 0,t.grow_counter,t.growth_rate,t.time_until_rebuild,
      layouts[t.layout],p.new_max or 0,p.old_max or 0,q.new_max or 0,q.old_max or 0},expected[i+1],"Town "..i.." tick "..tick)
  end
  snapshot_count=snapshot_count+1
end
observe(1280)
for day=1,365 do
  if day==32 or day==138 or day==267 then
    s=assert(Codec.decode(Codec.encode(s)))
    runtime=mount(Sim,mod,s,cap)
    assert(s.stock_town_growth.towns[5].stock_id==4 and s.sites[5].custom_name=="Rivermark")
  end
  runtime.day(observe)
end
assert(snapshot_count==6 and seen==27010 and digest==ref.rng)
print("PASS 6 RC1 manual town snapshots and all 27,010 RNG ticks, exact cost/quotes, 3 packed reopens")
