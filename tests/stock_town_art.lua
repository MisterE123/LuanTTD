-- Stock source catalogue, ordinary generated worlds, occupancy gates, and lifecycle.
local path="mods/luanttd_core/"
local function load(name) return dofile(path..name..".lua") end
local Sim,Terrain=load("sim"),load("openttd/terrain")
local TG=load("openttd/terragenesis")(load("openttd/slope"))
local Clear=load("openttd/terragenesis_clear")
local Cam,Names=load("generated_campaign"),load("openttd/stock_town_name")
local G,Catalog=load("openttd/town_growth"),load("openttd/town_growth_houses")
local Build=load("openttd/town_growth_build")(G,Catalog)
local Worldgen=load("openttd/town_worldgen")(G,Build)
local Passengers=load("openttd/town_passengers")
local Runtime=load("town_growth_runtime")(Sim,Terrain,G,Build,Passengers)
local Art=load("stock_town_art")
local gen={generate=function(o) return Clear.generate(TG.generate(o),TG.next_random) end,
  describe=Clear.describe,next_random=TG.next_random}
local stock,count={},0
for _,v in ipairs(Catalog) do
  assert(Art[v[1]] and (Art[v[1]].width or 1)==v[6] and (Art[v[1]].depth or 1)==v[7])
  stock[v[1]]=v
  count=count+1
end
assert(count==31)
local all,rendered={},{}
-- Compare the low native bits with the full upstream pixel hash using an
-- independent width-agnostic XOR implementation (plain Lua 5.1).
local function xor(a,b)
  local n,bit=0,1
  while a>0 or b>0 do
    if (a%2)~=(b%2) then n=n+bit end
    a,b,bit=math.floor(a/2),math.floor(b/2),bit*2
  end
  return n
end
for x=1,512 do
  for z=1,512,7 do
    local px,py=(x-1)*16,(z-1)*16
    local stock=(xor(xor(math.floor(px/16),math.floor(px/64)),math.floor(py/16))-math.floor(py/64))%4
    assert(Art.tile_hash(x,z)==stock)
  end
end
local appearances={[0x06]={0,2},[0x0E]={0},[0x18]={0,1,2,3},[0x19]={0},[0x1A]={0,1,2,3}}
local Front=load("house_frontage")
local first_world,first_root
local sloped={single=0,part=0}
for _,year in ipairs({1950,1975,2020}) do
  local cases={}
  for _,seed in ipairs({9,89,1451,1751,2027,65217}) do
    local s=Cam.landscape(Sim,Terrain,gen,{width=128,depth=128,seed=seed,terrain_type=0,
      quantity_sea_lakes=0,tgen_smoothness=1,freeform_edges=true,water_borders=0,variety=0,
      rng_state=TG.startup_rng(seed)})
    assert(Cam.towns(Sim,Terrain,s,gen,Worldgen,Names,G,Build,
      {difficulty=3,layout="original",larger_towns=2,initial_city_size=3,year=year}))
    for id,tile in ipairs(s.tiles) do
      local h=tile.source_house
      if h then
        local x,z=Sim.xy(id)
        local shape,base,top=Terrain.tile(s.corner_grid,x,z)
        assert(shape<16 and tile.h==base)
        if top>base then
          local key=h.asset_root and "part" or "single"
          sloped[key]=sloped[key]+1
        end
        if h.root then
          local expected=assert(stock[h.id])
          assert(year>=expected[3] and year<=expected[4],"House outside its stock construction years")
          cases[h.id],all[h.id]=true,true
          if h.completed and appearances[h.id] then
            assert(Art[h.id].asset)
            local x,z=Sim.xy(id)
            local name=Art.asset_name(h.id,Art.look(h.id,x,z))
            assert(io.open(path.."models/bl_"..name..".obj","rb")):close()
            local dir=Front.road(Sim,s,id,tile)
            if dir then
              local dx,dz,f=Front.placement(Sim,s,id,tile,false,h.render_parcel)
              assert(dx==(f>=2 and 1 or 0) and dz==((f==1 or f==2) and 1 or 0))
              assert(f==({2,1,0,3})[dir])
              rendered[name]=true
            end
          end
        end
        if h.asset_root then
          local members=assert(Art.footprint(Sim,s,h))
          for _,entry in ipairs(members) do
            local p=entry.record
            local _,root_base,root_top=Terrain.tile(s.corner_grid,h.x,h.z)
            local shape,base,top=Terrain.tile(s.corner_grid,p.x,p.z)
            assert(shape<16 and tile.h==root_base and s.tiles[entry.id].h==base and top==root_top)
            assert(p.stage==h.stage and p.counter==h.counter and p.completed==h.completed)
          end
          if h.root and h.id==0x14 and not first_root then first_world,first_root=s,h end
        end
      end
    end
  end
  local ids={}
  for id in pairs(cases) do ids[#ids+1]=("%02X"):format(id) end
  table.sort(ids)
  print(year..": "..table.concat(ids," "))
end
assert(sloped.single>0 and sloped.part>0)
print(("PASS generated clear slopes host %d single-tile houses and %d multipart cells at their stock levels"):format(sloped.single,sloped.part))
for _,v in ipairs(Catalog) do
  assert(all[v[1]],("stock root %02X not placed in seed coverage"):format(v[1]))
end
for id,looks in pairs(appearances) do
  for _,look in ipairs(looks) do
    local name=Art.asset_name(id,look)
    assert(rendered[name],name.." was not generated, complete and road-facing")
  end
end
print("PASS 12 RC1 stock residential/retail appearances generated complete with native roadside frontage")
local s,h=assert(first_world),assert(first_root)
s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading,s.road_economy=true,true,true,true
Sim.mount_stock_town_growth(s,Runtime,true)
local members=assert(Art.footprint(Sim,s,h))
assert(#members==4)
-- Put all parts at the last construction visit and ensure child visits are
-- inert. The first root tick completes all parts and dirties all tiles.
local town=s.stock_town_growth.towns[h.town]
local before_pop=town.population
for _,part in ipairs(members) do
  local p=part.record
  if p.completed then before_pop=before_pop-Passengers.specs[p.id][1] end
  p.stage,p.counter,p.completed=2,3,false
end
town.population=before_pop;s.sites[h.town].population=before_pop;s.changed={}
assert(Runtime.advance_house(s,members[2].id,members[2].record))
assert(not h.completed and h.counter==3 and #s.changed==0)
assert(Runtime.advance_house(s,members[1].id,h))
assert(town.population==before_pop+65 and #s.changed==4)
for _,part in ipairs(members) do assert(part.record.completed and part.record.completed_tick and part.record.stage==3) end
local company=Sim.company(s,"Town art QA")
local clear=assert(Sim.plan(s,"Town art QA","clear",{members[4].id,members[1].id}))
assert(#clear==1 and #clear[1].house_parts==4)
local _,cost=Sim.plan(s,"Town art QA","clear",{members[4].id})
assert(cost>0)
local quote=assert(Sim.clear_area(s,"Town art QA",members[1].id,members[4].id,false,false))
assert(quote.cost==cost and #quote.ids==1)
local cash=company.cash
local ok,note,changed=Sim.build(s,"Town art QA","clear",{members[4].id})
assert(ok,note)
assert(#changed==4 and company.cash==cash-cost and town.population==before_pop)
for _,part in ipairs(members) do assert(not s.tiles[part.id].house and not s.tiles[part.id].source_house) end
print("PASS 31/31 stock temperate roots, full footprint, source dates, shared stage clock and one-debit child bulldoze")
