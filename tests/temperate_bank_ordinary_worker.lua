local root="mods/luanttd_core/"
local function m(s)return dofile(root..s..".lua") end
local Sim,Terrain=m("sim"),m("openttd/terrain")
local mode=arg[1] or "early"
local profiles={early={1950,"valuables_balogh",12},mid={1985,"valuables_uhl",15},late={2025,"valuables_foster",16}}
local local_profile=assert(profiles[mode])
local name="QA Valuables"
local s=Sim.new(1751)
Sim.W,Sim.H=64,64
s.tiles={};for id=1,64^2 do s.tiles[id]={h=1,terrain="grass",variant=1} end
s.corner_grid=Terrain.new(64,64,function()return 1 end)
s.stock_generated_profile={width=64,depth=64}
s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply,s.road_economy=true,true,true,true
s.road_mail,s.road_junction_clearance=true,true
local id=Sim.id
s.sites={{id=1,kind="town",name="Banktown",tile=id(8,12),population=1500,stock={},received={},produced={},service=0},
  {id=2,kind="town",name="Stationfield",tile=id(45,12),population=1500,stock={},received={},produced={},service=0}}
s.stock_town_growth={version=1,order={},towns={}}
for _,p in ipairs(s.sites) do
  local q=m("openttd/town_growth").new(p.id,Sim.xy(p.tile))
  q.population,q.num_houses,q.house_counts=1500,2,{[0x06]=2}
  s.stock_town_growth.towns[p.id]=q
end
for _,p in ipairs({{10,12,1},{11,12,1},{42,12,2},{43,12,2}}) do
  local t=s.tiles[id(p[1],p[2])]
  t.house=true
  t.source_house={id=0x06,root=true,completed=true,town_growth=true,town=p[3],x=p[1],z=p[2]}
end
local cap={temperate_bank=true,road={start_year=local_profile[1],foster=true,breakdowns=0,service_interval=0,
  extra={[local_profile[2]]=true}},ferry={},air={},oil_tanker=true}
local World,A
local function mount()
  World=m("campaign_authority_runtime")(Sim,root:sub(1,-2),s,cap)
  A=m("campaign_authority_endpoint")(Sim,World)
end
mount()
local c=Sim.company(s,name);c.cash=3000000
local function command(kind,p)
  p.kind,p.revision=kind,s.authority_revision or 0
  local r=A.command(name,p);assert(r.ok,r.why);return r.value
end
local function build(req)
  local q=A.road_quote(name,req)
  assert(q.ok,q.why)
  return command("road_commit",{request=req,quote=q.value})
end
for _,x in ipairs({10,42}) do assert(#build({tool="fund_bank",first=id(x,12)})==2) end
assert(c.expense==996093*2 and Sim.road_bank_active(s))
local stretches={{7,15,46,15},{7,15,7,16},{7,16,13,16},{13,16,13,15},{39,15,39,16},{39,16,46,16},{46,16,46,15}}
for _,r in ipairs(stretches) do assert(Sim.build(s,name,"road",Sim.line(id(r[1],r[2]),id(r[3],r[4])))) end
local stop={}
for _,x in ipairs({10,42}) do
  local t=id(x,15)
  build({tool="truck_stop",first=t})
  stop[#stop+1]=s.tiles[t].station
  local q=A.truck_stop(name,t)
  assert(q.ok,q.why)
  for _,r in ipairs(q.value.cargo) do if r.cargo=="valuables" then
    assert(r.collects and r.accepts);break
  end end
end
local depot=id(17,16);build({tool="road_depot",first=depot})
local shop=A.depot(name,"road",depot);assert(shop.ok,shop.why)
local v
for _,o in ipairs(shop.value.offers) do if o.request.engine==local_profile[2] then
  assert(o.request.cargo=="valuables");v=command("road_buy",o.request);break
end end
assert(v and Sim.vehicle_capacity(s.fleet[v])==local_profile[3])
for _,st in ipairs(stop) do command("road_order_add",{vehicle=v,station=st}) end
command("road_toggle",{vehicle=v})
local function clone(x)
  if type(x)~="table" then return x end
  local out={};for k,z in pairs(x) do out[k]=clone(z) end;return out
end
local function advance(before)
  for _=1,600 do
    World.day()
    local unit=s.fleet[v]
    if unit.delivered>before then
      assert(unit.revenue>0 and unit.expense>0 and unit.delivered==s.companies[name].paid_units)
      return unit.delivered
    end
  end
  error("No paid Valuables route: "..s.fleet[v].status)
end
local first=advance(0)
s=clone(s);mount()
local units=advance(first)
print(("PASS %s: funded two native-layout stock Banks, opened a paid %s service (%d bags), and restored ordinary worker route")
 :format(mode,local_profile[2],units))
