-- Detached instrumentation of actual Sim.daily, replacing only the Lua
-- dependency's walker in this process. Neither game nor save is modified.
local p="mods/luanttd_core/"
local function m(n) return dofile(p..n..".lua") end
local H,Terrain,Flood=m("openttd/town_passengers"),m("openttd/terrain"),m("openttd/water_flood")
local Dynamic=m("openttd/landscape_dynamic")(m("openttd/landscape_index"))
local owner
local rules={}
for k,v in pairs(H) do rules[k]=v end
function rules.advance_houses(c,ticks,house,settings,random,emit,before,land)
  if not owner then return H.advance_houses(c,ticks,house,settings,random,emit,before,land) end
  -- This proof only mounts the interactive stock-service path. Its actual
  -- Sim early/late phases and once-per-tick owner remain untouched.
  assert(ticks==1 and c==owner.state.passenger_house_clock)
  local update=owner
  local n=update.scheduler.advance(c,ticks,function(id,tick,slot,x,z)
    if land then land(x,z,tick) end
    local h=house(x,z)
    if h then H.produce_tile(id,tick,h,settings,random,function(name,amount) emit(name,amount,x,z,h,tick) end) end
    update.reconcile()
  end,function(tick)
    update.reconcile() -- includes growth/planting between landscape ticks
    if before then before(tick) end
  end)
  update.calls=update.calls+n
  update.scans=update.scans+2^(c.log_x+c.log_y-8)
end
local LuaSim=assert(loadfile(p.."sim.lua"))
setfenv(LuaSim,setmetatable({dofile=function(path)
  if path:match("openttd/town_passengers%.lua$") then return rules end
  return dofile(path)
end},{__index=_G}))
local Sim=LuaSim()
local function cp(t,memo)
  if type(t)~="table" then return t end
  memo=memo or {}
  if memo[t] then return memo[t] end
  local out={};memo[t]=out
  for k,v in pairs(t) do out[k]=cp(v,memo) end
  return out
end
local function same(a,b,k,seen)
  k=k or "root"
  assert(type(a)==type(b),k..": types "..type(a).." != "..type(b))
  if type(a)~="table" then assert(a==b,k..": "..tostring(a).." != "..tostring(b));return end
  seen=seen or {}; if seen[a]==b then return end; seen[a]=b
  for i,v in pairs(a) do same(v,b[i],k.."."..i,seen) end
  for i in pairs(b) do assert(a[i]~=nil,k.." missing "..i) end
end

local W=m("water_flood_world")(Sim,Terrain,Flood)
local function candidate(s,board,id,potential)
  local t=s.tiles[id]
  if t.house or potential[id] or s.stock_farm_fields and s.stock_farm_fields[id] then return true end
  if not s.stock_coastal_flood or t.terrain~="water" or not t.coastal_water and (t.stock_canal or
      t.water_class=="river" or t.water_class=="canal" or t.build=="canal") then return false end
  local x,z=Sim.xy(id)
  return #Flood.visit(board,x,z)>0
end
local function session(s)
  local c=assert(s.passenger_house_clock)
  local X=Dynamic.new(c.log_x,c.log_y)
  local board=W.board(s)
  local potential={}
  local coals,timbers,farms,oils=s.stock_coal_industries,s.stock_timber_industries,s.stock_farm_industries,s.stock_oil_industries
  for _,industries in pairs{coals,timbers,farms,oils} do
    for _,ind in pairs(industries) do
      if not ind.removed then
        for _,tile in ipairs(ind.tiles) do potential[assert(Sim.id(tile.x+1,tile.z+1))]=true end
      end
    end
  end
  local function tag(id)
    local x,z=Sim.xy(id)
    X.set((z-1)*2^c.log_x+x-1,candidate(s,board,id,potential))
  end
  assert(#s.tiles==Sim.W*Sim.H and Sim.W<=2^c.log_x and Sim.H<=2^c.log_y)
  for id in ipairs(s.tiles) do tag(id) end
  local old,j=s.changed,#(s.changed or {})
  return {state=s,scheduler=X,calls=0,scans=0,reconcile=function()
    -- Test-only splice over the acknowledged native visual dirty append.
    -- Production needs a dedicated authority journal for every command.
    if old~=s.changed then old,j=s.changed,0 end
    if not old then return end
    while j<#old do
      j=j+1
      local x,z=Sim.xy(old[j])
      for dz=-1,1 do for dx=-1,1 do
        local n=Sim.id(x+dx,z+dz)
        if n then tag(n) end
      end end
    end
  end}
end

local Cam,TGP,Clear=m("generated_campaign"),m("openttd/terragenesis")(m("openttd/slope")),m("openttd/terragenesis_clear")
local Rivers=m("openttd/river_worldgen")(m("openttd/slope"))
local G=m("openttd/town_growth")
local Build=m("openttd/town_growth_build")(G,m("openttd/town_growth_houses"))
local Growth=m("town_growth_runtime")(Sim,Terrain,G,Build,H)
local Packets,Rating=m("openttd/passengers"),m("openttd/station_rating")
local Cat=m("openttd/station_catchment")(Packets,Rating,function() return 0 end,function() return 0 end)
local Coal=m("openttd/coal_industry")(Packets,Rating,Cat,m("openttd/income"))
local Timber=Sim.timber_rules()
local width=128
local Gen={next_random=TGP.next_random,describe=Clear.describe}
function Gen.generate(o)
  local t,stats=Rivers.generate(TGP.generate(o),TGP.next_random,{original=false,terrain=Terrain,
    amount_of_rivers=1,min_river_length=16})
  return Clear.generate(t,TGP.next_random),stats
end
local function stock(s)
  s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply,s.road_economy=true,true,true,true
end
local function s128()
  local s=Cam.landscape(Sim,Terrain,Gen,{
    width=width,depth=width,seed=1751,terrain_type=3,quantity_sea_lakes=0,
    tgen_smoothness=1,freeform_edges=true,water_borders=15,variety=0,rng_state=TGP.startup_rng(1751)})
  assert(Cam.towns(Sim,Terrain,s,Gen,m("openttd/town_worldgen")(G,Build),m("openttd/stock_town_name"),G,Build,{
    difficulty=2,layout="original",larger_towns=4,initial_city_size=2,year=1950}).success)
  local industries=Cam.industries(Sim,Terrain,s,Gen,m("openttd/industry_worldgen")(Coal,Timber),
    m("coal_industry_world")(Sim,Terrain,Coal),4,nil,m("timber_world")(Sim,Terrain,Timber))
  assert(#industries.placed==13)
  Cam.landmarks(Sim,Terrain,s,Gen,m("openttd/scenery_object_worldgen"),m("openttd/stock_engine_calendar").date(1950))
  Cam.forests(Sim,Terrain,s,Gen,m("openttd/tree_worldgen"),2)
  stock(s)
  s.road_coal,s.road_timber,s.road_mail=true,true,true
  assert(Sim.road_coal_active(s) and Sim.road_timber_active(s))
  return s
end
local function coast_growth(s)
  Sim.mount_stock_town_growth(s,Growth,true)
  Sim.mount_coastal_flood(s)
end
local function run(label,s,mount,days,assertions,between)
  mount(s)
  local a,b=s,cp(s)
  local seen={oil_animation=false,new_field=false}
  local initial_fields=cp(s.stock_farm_fields or {})
  mount(b)
  local function period(first,last,where)
    local prior=os.clock()
    local ctx=session(b)
    for day=first,last do
      if between then between(a,day);between(b,day) end
      Sim.daily(a)
      owner=ctx
      Sim.daily(b)
      owner=nil
      same(a,b)
      if b.stock_oil_animated and next(b.stock_oil_animated) then seen.oil_animation=true end
      for id in pairs(b.stock_farm_fields or {}) do
        if not initial_fields[id] then seen.new_field=true;break end
      end
    end
    assert(ctx.calls<ctx.scans and ctx.calls>0)
    print(("%s %s days %d–%d: %d selected physical visits vs %d stock slots; head %d / tick %d; %.3fs differential total")
      :format(label,where,first,last,ctx.calls,ctx.scans,b.passenger_house_clock.head,b.passenger_house_clock.counter,os.clock()-prior))
  end
  period(1,4,"fresh")
  a,b=cp(a),cp(b);mount(a);mount(b)
  period(5,days,"reloaded")
  assertions(a,seen)
end
run("128² generated coast/house/coal/timber/mail",s128(),coast_growth,12,function(s)
  assert(s.passenger_house_clock.counter==888 and s.passenger_rating_rng)
  assert(s.stock_timber_industries and s.stock_coal_industries)
end)

-- Authored 48×36 farms and oil use stock 64×64 slots. Host/saved IDs
-- stay 1-based with stride 48; convert physical coordinates only.
Sim.W,Sim.H=48,36
local function authored(tag)
  local s=Sim.new(1751)
  stock(s)
  s.road_junction_clearance,s["road_"..tag]=true,true
  m("town_layout")(Sim,s)
  s.corner_grid=m("terrain_preview")(Sim,Terrain,s)
  local mount=function(world)
    local adapter,rng
    if tag=="oil" then adapter=assert(Sim.mount_oil_world(world,Terrain,true))
    else adapter,rng=Sim.mount_farm_world(world,Terrain,true);assert(adapter and rng) end
    if not world["stock_"..tag.."_industries"] then assert(adapter.default_1751(world,rng)) end
  end
  return s,mount
end
do
  local s,mount=authored("farm")
  mount(s)
  local before=cp(s.stock_farm_fields)
  local adapter=assert(Sim.mount_farm_world(s,Terrain,true))
  local seeded_field
  local function introduce_field(w,day)
    if day~=7 then return end
    local board=adapter.field_board(w)
    for z=2,Sim.H-2 do for x=2,Sim.W-2 do
      local id=Sim.id(x+1,z+1)
      local t=board.tile(x,z)
      if t.kind=="clear" and t.ground=="grass" and not w.stock_farm_fields[id] then
        seeded_field=id
        local farm=assert(w.stock_farm_industries[8192])
        board.make_field(x,z,2,farm.id,0) -- actual native planting writer/journal
        return
      end
    end end
    error("No unallocated grass for field dependency fixture")
  end
  run("authored farm/factory/fields",s,mount,22,function(after,seen)
    assert(after.stock_farm_fields)
    local differed=false
    for id,r in pairs(after.stock_farm_fields) do
      if not before[id] or before[id].last_tick~=r.last_tick then differed=true;break end
    end
    assert(differed and seen.new_field,"No real field was advanced or newly planted")
    assert(after.stock_farm_fields[seeded_field].last_tick)
  end,introduce_field)
end
do
  local s,mount=authored("oil")
  mount(s)
  run("authored oil/refinery/animation",s,mount,22,function(after,seen)
    assert(after.stock_oil_animated and after.passenger_rating_rng and seen.oil_animation)
  end)
end
do
  local s=Sim.new(1751)
  stock(s)
  m("town_layout")(Sim,s);s.corner_grid=m("terrain_preview")(Sim,Terrain,s)
  local mount=function(w) Sim.mount_stock_town_growth(w,Growth,true) end
  mount(s)
  local q=dofile("tests/town_growth_live_fixture.lua").prepare(Sim,s)
  assert(Sim.toggle(s,"GrowthQA",q.id))
  run("authored serviced town",s,mount,140,function(out)
    local town=out.stock_town_growth.towns[q.town]
    local built=assert(town.last_build,"No service-backed construction")
    local h=out.tiles[built.tile].source_house
    assert(out.fleet[q.id].last_fare and h.built_tick==built.tick)
    print(("real bus fare and an actual new house admitted at stock tick %d; current source construction stage %d"):format(built.tick,h.stage))
  end)
end
