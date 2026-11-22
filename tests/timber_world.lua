-- Actual default 1751 geometry with unmodified town houses, public
-- streets, shared corners and the separate established coal footprint.
local root="mods/luanttd_core/"
local function load(p)return dofile(root..p..".lua")end
local Sim,Terrain,P,I,K=load("sim"),load("openttd/terrain"),load("openttd/passengers"),load("openttd/income"),load("openttd/station_rating")
local House,Goods=load("openttd/town_passengers"),load("openttd/town_goods")
local C=load("openttd/station_catchment")(P,K)
local Coal=load("openttd/coal_industry")(P,K,C,I)
local T=load("openttd/timber_industry")(P,C,K,I,Coal,Goods)
local W=load("timber_world")(Sim,Terrain,T)
local id=Sim.id
local function copy(t)
  if type(t)~="table" then return t end
  assert(not getmetatable(t))
  local out={}
  for k,v in pairs(t) do out[k]=copy(v) end
  return out
end
local function equal(a,b)
  if type(a)~="table" or type(b)~="table" then return a==b end
  for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
local s=Sim.new(1751)
load("town_layout")(Sim,s)
s.corner_grid=load("terrain_preview")(Sim,Terrain,s)
load("town_passenger_runtime")(Sim,House).start(s)
local coal=assert(load("coal_industry_world")(Sim,Terrain,Coal).seed(s,id(30,11),id(40,12)))
local scene=assert(W.scenario_1751(s))
assert(not W.default_1751(Sim.new(1750)))
assert(#W.facilities.stock_forest.produces==0 and next(W.facilities.stock_sawmill.takes)==nil)
local untouched=copy(s)
local p=assert(W.quote_pair(s,scene.forest,scene.sawmill))
assert(p.forest.level==0 and p.sawmill.level==0 and #p.forest.cells==18 and #p.sawmill.cells==8)
assert(equal(s,untouched),"Quote mutated the native world")
local function reject(action,reason)
  local result,code,bad=action()
  assert(not result and code==reason,tostring(result)..":"..tostring(code).." expected "..reason)
  return bad
end
local bad_occupied=id(14,17)
s.rail_bridge_above={[bad_occupied]=147}
assert(reject(function()return W.commit_pair(s,p)end,"INDUSTRY_SITE_OCCUPIED")==bad_occupied)
s.rail_bridge_above=nil
assert(equal(s,untouched),"Failing second footprint must not write first")
local changed=copy(p);changed.sawmill.cells[1].gfx=19
reject(function()return W.commit_pair(s,changed)end,"STALE_INDUSTRY_QUOTE")
local old=s.topology;s.topology=old+1
reject(function()return W.commit_pair(s,p)end,"STALE_INDUSTRY_QUOTE")
s.topology=old
reject(function()return W.quote(s,"sawmill",id(9,9))end,"INDUSTRY_SITE_OCCUPIED")
reject(function()return W.quote(s,"sawmill",coal.tiles[1])end,"INDUSTRY_SITE_OCCUPIED")
reject(function()return W.quote(s,"sawmill",id(48,36))end,"INDUSTRY_OUTSIDE_REGION")
assert(equal(s,untouched))
s.stock_coal_industries[W.INDUSTRY_ID_BASE+1]={}
reject(function()return W.commit_pair(s,p)end,"INDUSTRY_ID_COLLISION")
s.stock_coal_industries[W.INDUSTRY_ID_BASE+1]=nil
assert(equal(s,untouched),"Preflight of both IDs must happen before writes")
local placed=assert(W.commit_pair(s,p))
assert(s.topology==old+1 and #placed.tiles==26 and placed.forest~=coal.mine and placed.sawmill~=coal.power)
local inds=s.stock_timber_industries
assert(inds[placed.forest].produced.rate==13 and inds[placed.forest].produced.last.production==104)
assert(inds[placed.sawmill].produced.rate==0 and inds[placed.sawmill].accepted.waiting==0)
assert(s.sites[placed.forest_site].tile==scene.forest and s.sites[placed.sawmill_site].tile==scene.sawmill)
local occupied={}
for _,i in ipairs(placed.tiles) do
  assert(not occupied[i]);occupied[i]=true
  local meta,industry=W.record(s,i)
  assert(meta.id==industry.id and meta.chain=="timber" and meta.layout==0)
  local x,z=Sim.xy(i)
  assert(industry.x+meta.x==x-1 and industry.z+meta.z==z-1 and meta.site==industry.site)
  local t=s.tiles[i]
  assert(t.terrain==untouched.tiles[i].terrain and t.h==untouched.tiles[i].h and not t.build)
  if i~=scene.forest and i~=scene.sawmill then assert(not t.site) end
end
assert(W.record(s,scene.sawmill_intake).gfx==13)
assert(W.record(s,id(13,5)).gfx==16 and not W.protected(s,id(12,5)) and not W.protected(s,id(14,18)))
for i in ipairs(s.tiles) do if not occupied[i] then assert(equal(s.tiles[i],untouched.tiles[i]),i) end end
assert(equal(s.corner_grid,untouched.corner_grid) and equal(s.stock_coal_industries,untouched.stock_coal_industries))
for i,v in ipairs(untouched.sites) do assert(equal(v,s.sites[i])) end
reject(function()return W.seed(s,scene.forest,scene.sawmill)end,"INDUSTRY_SITE_OCCUPIED")
local reloaded=copy(s)
assert(W.record(reloaded,scene.sawmill_intake).style=="sawmill_0")
local owner="Timber Shipping"
-- Shared M.plan naturally guards every non-origin timber cell because
-- the same general stock-industrial protection marker is present.
assert(not Sim.build(s,owner,"clear",{scene.sawmill_intake}))
assert(not Sim.build(s,owner,"road",{scene.sawmill_intake}))
assert(not Sim.build(s,owner,"road_station",{scene.sawmill_intake}))
assert(not Sim.landscape(s,owner,"raise",14,17))
s.road_economy=true;s.road_coal=true;s.road_stock_loading=true;s.road_stock_clock=true;s.road_stock_house_supply=true
local function list(points)
  local out={}
  for j=2,#points do
    local piece=Sim.line(points[j-1],points[j])
    for k,i in ipairs(piece) do if j==2 or k>1 then out[#out+1]=i end end
  end
  return out
end
for _,route in ipairs(scene.road_waypoints) do
  local operations,why=Sim.plan(s,owner,"road",list(route));assert(operations,why)
  local ok,msg=Sim.build(s,owner,"road",list(route));assert(ok,msg)
end
local road_stop={}
for _,tile in ipairs({scene.forest_stop,scene.sawmill_stop,scene.goods_stop}) do
  local ok,error_=Sim.build_truck_stop(s,owner,tile);assert(ok,error_)
  local st=assert(s.stations[s.tiles[tile].station])
  assert(st.stop_type=="truck")
  local x,z=Sim.xy(tile)
  road_stop[tile]={station=st,record={id=st.id,owner=owner,x=x-1,z=z-1,
    tiles={{x=x-1,y=z-1,kind="truck"}},tile=tile}}
end
assert(Sim.build(s,owner,"road_depot",{scene.depot}))
local function footprint(tile,cargo)
  local st=road_stop[tile].record
  local c=C.build(st,Sim.W,Sim.H)
  local a=T.acceptance(st,c,cargo,inds,function(x,z)
    return s.tiles[id(x+1,z+1)].source_house
  end)
  return a,c
end
local function touched(c,ind)
  for _,tile in ipairs(ind.tiles) do if C.contains(c,tile.x,tile.z) then return true end end
  return false
end
local f,fcover=footprint(scene.forest_stop,"wood")
assert(not f.accepts and touched(fcover,inds[placed.forest]) and not touched(fcover,inds[placed.sawmill]))
local wood,mcover=footprint(scene.sawmill_stop,"wood")
assert(wood.eighths==8 and wood.accepts and wood.near[1].id==placed.sawmill)
assert(touched(mcover,inds[placed.sawmill]))
local goods,gcover=footprint(scene.goods_stop,"goods")
assert(goods.accepts and goods.eighths==9 and goods.always_accepted and not touched(gcover,inds[placed.sawmill]))
assert(goods.house_eighths_by_town[1]==3 and goods.house_eighths_by_town[2]==6)
local function leg(a,b,kind,prior,expected)
  local p,td,_,frames=Sim.path(s,road_stop[a].station,road_stop[b].station,"road",owner,nil,
    {cargo=kind,engine="truck",road_arrival_td=prior})
  assert(p and p[1]==a and p[#p]==b and #frames==expected,
    ("Source %s leg %s to %s has %s frames"):format(kind,a,b,frames and #frames or "none"))
  return td
end
local a=leg(scene.forest_stop,scene.sawmill_stop,"wood",nil,371)
local b=leg(scene.sawmill_stop,scene.forest_stop,"wood",a,373)
assert(leg(scene.forest_stop,scene.sawmill_stop,"wood",b,371)==a)
local c=leg(scene.sawmill_stop,scene.goods_stop,"goods",nil,247)
local d=leg(scene.goods_stop,scene.sawmill_stop,"goods",c,255)
assert(leg(scene.sawmill_stop,scene.goods_stop,"goods",d,247)==c)

-- Refuse overlapping, too-close, exterior, sloped, and conflicting
-- quotes without making compensating writes to a partially seeded pair.
local blank=Sim.new(1751)
blank.sites={};for j in ipairs(blank.tiles) do blank.tiles[j]={h=0,terrain="grass",variant=1} end
blank.corner_grid=Terrain.new(Sim.W,Sim.H,function(x) return x>=25 and 1 or 0 end)
reject(function()return W.seed(blank,id(4,4),id(6,5))end,"INDUSTRIES_OVERLAP")
reject(function()return W.seed(blank,id(4,4),id(18,14))end,"INDUSTRIES_TOO_CLOSE")
reject(function()return W.quote(blank,"forest",id(47,12))end,"INDUSTRY_OUTSIDE_REGION")
reject(function()return W.quote(blank,"sawmill",id(23,12))end,"INDUSTRY_NEEDS_LEVEL_LAND")
assert(not blank.stock_timber_industries and #blank.sites==0)
local only=assert(W.commit(blank,assert(W.quote(blank,"forest",id(4,4)))))
assert(only.kind=="forest" and only.prod_level==16)
reject(function()return W.quote(blank,"sawmill",id(18,14))end,"INDUSTRIES_TOO_CLOSE")
print("stock timber scenario seed1751: 26 exact protected tiles; towns/coal untouched; forest↔sawmill 371/373, sawmill↔Goods 247/255")
