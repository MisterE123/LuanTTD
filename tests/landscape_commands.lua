local p="mods/luanttd_core/"
local function m(n) return dofile(p..n..".lua") end
local Sim,T,F=m("sim"),m("openttd/terrain"),m("openttd/water_flood")
local H=m("openttd/town_passengers")
local A=m("openttd/landscape_authority")
local Cmd=m("openttd/landscape_commands")(Sim,A)
local Dyn=m("openttd/landscape_dynamic")(m("openttd/landscape_index"))
local Growth=m("openttd/town_growth")
local Build=m("openttd/town_growth_build")(Growth,m("openttd/town_growth_houses"))
local GrowthWorld=m("town_growth_runtime")(Sim,T,Growth,Build,H)
local FloodWorld=m("water_flood_world")(Sim,T,F)
local Cam=m("generated_campaign")
local TGP=m("openttd/terragenesis")(m("openttd/slope"))
local Clear=m("openttd/terragenesis_clear")
local Gen={generate=function(o) return Clear.generate(TGP.generate(o),TGP.next_random) end,
  next_random=TGP.next_random,describe=Clear.describe}
local function eq(a,b,msg) assert(a==b,(msg and msg..": " or "")..tostring(a).." != "..tostring(b)) end
local function cp(t,seen)
  if type(t)~="table" then return t end
  seen=seen or {}
  if seen[t] then return seen[t] end
  local out={};seen[t]=out
  for k,v in pairs(t) do out[k]=cp(v,seen) end
  return out
end
local function same(a,b,path,seen)
  path=path or ""
  eq(type(a),type(b),path)
  if type(a)~="table" then eq(a,b,path);return end
  seen=seen or {}
  if seen[a]==b then return end
  seen[a]=b
  for k,v in pairs(a) do same(v,b[k],path.."/"..k,seen) end
  for k in pairs(b) do assert(a[k]~=nil,path.."/"..k) end
end

local s=Cam.landscape(Sim,T,Gen,{width=128,depth=128,seed=1751,terrain_type=3,quantity_sea_lakes=0,
    tgen_smoothness=1,freeform_edges=true,water_borders=15,variety=0,rng_state=TGP.startup_rng(1751)})
local t=assert(Cam.towns(Sim,T,s,Gen,m("openttd/town_worldgen")(Growth,Build),m("openttd/stock_town_name"),
  Growth,Build,{difficulty=2,layout="original",larger_towns=4,initial_city_size=2,year=1950}))
assert(t.success and #s.sites>=2)
Cam.forests(Sim,T,s,Gen,m("openttd/tree_worldgen"),2)
s.road_economy,s.road_stock_house_supply,s.road_stock_loading,s.road_stock_clock=true,true,true,true
Sim.mount_coastal_flood(s)
Sim.mount_stock_town_growth(s,GrowthWorld,true)
local name="Proof Railway"
local c=Sim.company(s,name)
-- Pre-existing visual garbage is intentionally irrelevant to authority.
s.changed={2,350,2000,2,12345}
local visual=table.concat(s.changed,",")
local function make(s)
  local D=Dyn.new(7,7)
  local B=FloodWorld.board(s)
  local function candidate(k,x,z,host)
    local t=s.tiles[host]
    if not t then return nil end
    if t.house then return true end
    if t.terrain~="water" or not t.coastal_water and (t.stock_canal or t.water_class=="river" or
       t.water_class=="canal" or t.build=="canal") then return false end
    return #F.visit(B,x,z)>0
  end
  local function verify(seed)
    local n=0
    for id in ipairs(s.tiles) do
      local x,z=Sim.xy(id)
      if candidate(id-1,x,z,id) then
        n=n+1
        if seed then D.set(id-1,true) else assert(D.contains(id-1),id) end
      end
    end
    eq(D.count(),n)
  end
  verify(true)
  local O=A.new({world="natural-128",width=128,depth=128,log_x=7,log_z=7},D,candidate)
  return Cmd.bind(s,"natural-128",name,O),O,D,verify
end
local C,O,D,verify=make(s)
local ordinary=cp(s)
Sim.mount_coastal_flood(ordinary)
Sim.mount_stock_town_growth(ordinary,GrowthWorld,true)
local function compare(spec)
  local q=assert(C.quote(spec))
  assert(#q.dirty>0 and q.cost>0)
  local before=s.companies[name].cash
  local yes,result,status=C.run(spec)
  assert(yes,result)
  eq(status,"sparse");eq(result.cost,q.cost);eq(before-s.companies[name].cash,q.cost)
  local expected,desc,ids,peak
  if spec.ids then expected,desc,ids=Sim.build(ordinary,name,spec.tool,spec.ids)
  else expected,desc,ids,peak=Sim.landscape(ordinary,name,spec.tool,spec.x,spec.z) end
  assert(expected,desc)
  same(q.dirty,ids);same(result.dirty,ids);eq(peak,q.peak);eq(result.message,desc)
  same(ordinary,s)
  eq(table.concat(s.changed,","),visual)
  verify(false)
  return q,result
end

-- Existing source-grown house, real nearest-town ratings and population.
local home
for id,tile in ipairs(s.tiles) do if tile.house and tile.source_house then home=id;break end end
assert(home)
local root=s.tiles[home].source_house.town
local building=s.tiles[home].source_house
local before_pop=s.sites[root].population
local house=compare({tool="clear",ids={home,home}})
eq(#house.dirty,1);assert(house.cost>=240 and not s.tiles[home].house and not s.tiles[home].source_house)
assert(not D.contains(home-1))
if building.completed and H.specs[building.id][1]>0 then assert(s.sites[root].population<before_pop) end

local road
for z=51,110 do
  for x=7,117 do
    local ids=Sim.line(Sim.id(x,z),Sim.id(x+2,z))
    local spec={tool="road",ids=ids}
    local quote=C.quote(spec)
    if quote and #quote.dirty==3 and s.tiles[ids[1]].build==nil then road=spec;break end
  end
  if road then break end
end
assert(road)
local q=compare(road)
for _,id in ipairs(q.dirty) do eq(s.tiles[id].build,"road");eq(s.tiles[id].owner,name) end
local rev=O.revision()
local unchanged,receipt,mode=C.run(road)
assert(unchanged,receipt);eq(mode,"unchanged");eq(#receipt.dirty,0);eq(O.revision(),rev)
compare({tool="clear",ids=road.ids})
for _,id in ipairs(q.dirty) do eq(s.tiles[id].build,nil) end

-- Stronger corner witness: the native quote must include propagated
-- dependent corners or ordinary sea/shore clearance, not just the click.
local corner,corner_quote
for z=2,126 do
  for x=2,126 do
    local spec={tool="raise",x=x,z=z}
    local proposed=C.quote(spec)
    if proposed then
      local sea=false
      for _,i in ipairs(proposed.dirty) do if s.tiles[i].terrain=="water" then sea=true;break end end
      if sea and #proposed.changes>1 then corner,corner_quote=spec,proposed;break end
      if not corner and sea then corner,corner_quote=spec,proposed end
    end
  end
  if corner and #corner_quote.changes>1 then break end
end
assert(corner and #corner_quote.changes>1 and #corner_quote.dirty>4)
local before=cp(s)
local n=select("#",Sim.landscape(s,name,corner.tool,corner.x,corner.z,nil,nil,nil,true))
local yes,price=Sim.landscape(s,name,corner.tool,corner.x,corner.z,nil,nil,nil,true)
assert(yes);eq(n,2);eq(price,corner_quote.cost);same(before,s)
local quoted,footprice,detail=Sim.landscape(s,name,corner.tool,corner.x,corner.z,nil,nil,nil,"footprint")
assert(quoted and type(detail)=="table");eq(footprice,price);eq(#detail.corners,#corner_quote.changes)
eq(detail.terrain_revision,s.corner_grid.revision);same(before,s)
local ghost=cp(s)
local new=Sim.landscape(ghost,"Unopened",corner.tool,corner.x,corner.z,nil,nil,nil,"footprint")
eq(new,false);same(ghost,s)
-- Previous boolean behavior deliberately opens a new company.
Sim.landscape(ghost,"Unopened",corner.tool,corner.x,corner.z,nil,nil,nil,true)
assert(ghost.companies.Unopened and #ghost.news>#s.news)
eq(ghost.corner_grid.revision,s.corner_grid.revision)

local coast=compare(corner)
local lowered=compare({tool="lower",x=corner.x,z=corner.z})
local wood
for id,tile in ipairs(s.tiles) do
  if tile.wood and C.quote({tool="clear",ids={id}}) then wood=id;break end
end
assert(wood)
local forest=compare({tool="clear",ids={wood}})
assert(not s.tiles[wood].wood)
eq(forest.cost,Sim.tools.clear.price)

print(("128² actual native receipts: house $%d, tree $%d, road $%d, coast raise $%d/%d propagated corners/%d dirty tiles and lower $%d; all dense authority matched")
  :format(house.cost,forest.cost,q.cost,coast.cost,#coast.changes,#coast.dirty,lowered.cost))

-- Reject special tiles/routes/layers before asking the writer to act.
-- Isolated synthetic sentinels are removed before the full reference check.
local id=road.ids[1]
local function reject(spec,why)
  local n,topo,cash=O.revision(),s.topology,c.cash
  local ok,err,mode=C.run(spec)
  eq(ok,nil);eq(err,why);eq(mode,"unsupported")
  eq(O.revision(),n);eq(s.topology,topo);eq(c.cash,cash)
end
local edit={tool="clear",ids={id}}
local tile=s.tiles[id]
local old=tile.build
tile.build="road_station";reject(edit,"UNSUPPORTED_FACILITY");tile.build=old
local original_density,original_visits=tile.stock_clear_density,tile.stock_clear_visits
tile.stock_clear_density=3;reject(edit,"UNREVIEWED_GROUND")
tile.stock_clear_density=0;tile.stock_clear_visits=8;reject(edit,"UNREVIEWED_GROUND")
tile.stock_clear_density,tile.stock_clear_visits=original_density,original_visits
tile.rail_tracks=5;reject(edit,"UNREVIEWED_TILE");tile.rail_tracks=nil
tile.bridge_hook=0;reject(edit,"UNREVIEWED_TILE");tile.bridge_hook=nil
tile.road_town=1;reject(edit,"PUBLIC_ROAD");tile.road_town=nil
tile.stock_void=true;reject(edit,"UNREVIEWED_TILE");tile.stock_void=nil
s.rail_bridge_above={[id]=91};reject(edit,"PROTECTED_LAYER");s.rail_bridge_above=nil
s.custom_overlays={[id]=1};reject(edit,"UNREVIEWED_LAYER");s.custom_overlays=nil
local ux,uz=Sim.xy(id)
local adjacent=s.tiles[Sim.id(ux,uz-1)]
local old_adjacent=adjacent.build
adjacent.build="road_depot";reject(road,"UNSUPPORTED_FACILITY");adjacent.build=old_adjacent
local flagged=Cmd.bind(s,"natural-128",name,O,{additional_layers={"unrecognized_layer"}})
local _,denial,kind=flagged.run(road)
eq(denial,"UNREVIEWED_LAYER");eq(kind,"unsupported")
local ephemeral=Cmd.bind(s,"natural-128",name,O,{untracked=function() return true end})
local _,ephemeral_denial=ephemeral.run(road)
eq(ephemeral_denial,"ROUTED_WORLD")
s.fleet[1]={route={id}};reject(edit,"ROUTED_WORLD");s.fleet[1]=nil
reject({tool="clear",ids={[2]=id}},"UNSUPPORTED_COMMAND")
reject({tool="level",x=corner.x,z=corner.z},"UNSUPPORTED_COMMAND")
local balance=c.cash
c.cash=0
local denied,not_cash,denied_kind=C.run(road)
eq(denied,nil);eq(not_cash,"Not enough cash.");eq(denied_kind,"denied");eq(c.cash,0)
c.cash=balance
local dropped=Cmd.bind(s,"wrong-world",name,O)
local r,err,disposition=dropped.run(road)
eq(r,nil);eq(err,"WRONG_WORLD");eq(disposition,"abort")
same(ordinary,s);verify(false)
print("strict pre-write gate: facilities, rail/bridge, public roads, void, unknown overlays, malformed commands and fleet refused")
