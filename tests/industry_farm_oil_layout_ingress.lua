-- Check exact source placement for all remaining Farm/Factory/Oil plans.
-- Testing ingress is separate from enabling a layout's native artwork.
local root="mods/luanttd_core/"
local function m(n) return dofile(root..n..".lua") end
local Sim,Terrain=m("sim"),m("openttd/terrain")
local Packet,Rating,Income=m("openttd/passengers"),m("openttd/station_rating"),m("openttd/income")
local P=m("openttd/station_catchment")(Packet,Rating)
local Coal=m("openttd/coal_industry")(Packet,Rating,P,Income)
local Timber=Sim.timber_rules()
local FarmFactory=m("openttd/farm_factory_industry")
local Farm=FarmFactory(Packet,P,Rating,Income,Coal,Timber)
local Oil=m("openttd/oil_industry")(FarmFactory,Packet,P,Rating,Income,Coal,Timber)
local OilWorld=m("oil_industry_world")(Sim,Terrain,Oil)
local Fields=m("openttd/farm_factory_fields")(Coal)
local FarmWorld=m("farm_factory_world")(Sim,Terrain,Farm,Fields,P)
Sim.W,Sim.H=64,64
local function new()
  local s=Sim.new(414)
  s.tiles,s.sites={},{}
  s.corner_grid=Terrain.new(64,64,function() return 2 end,{freeform_edges=true})
  s.stock_generated_profile={width=64,depth=64}
  for i=1,64*64 do s.tiles[i]={terrain="hill",variant=1,h=2} end
  return s
end
local function check(kind,variant,K,World)
  local s=new()
  local x,z=9,18
  local origin=Sim.id(x+1,z+1)
  local record=K.new(kind,0,x,z,{layout=variant,original=true,completed=true,generating_world=true,economy_year=1950})
  local calls=0
  local function rnd() calls=calls+1;return calls*23496503%4294967296 end
  local r,cells,site=assert(World.place_generated(s,kind,origin,{record=record,name="Exact alternate"},rnd))
  assert(r.layout==variant and r.x==x and r.z==z and site.tile==origin)
  local available={}
  for i,cell in ipairs(K.layout[kind][variant]) do
    local id=Sim.id(x+1+cell[1],z+1+cell[2])
    assert(cells[i].id==id)
    local ref=s.tiles[id].stock_industry
    assert(ref and ref.gfx==cell[3] and ref.layout==variant)
    assert(ref.style:match((kind=="forest" and "_" or "_l")..variant.."$"))
    available[id]=true
  end
  for dx=0,5 do for dz=0,5 do
    local id=Sim.id(x+1+dx,z+1+dz)
    if not available[id] then assert(not s.tiles[id].stock_industry and not s.tiles[id].site) end
  end end
end
for kind,variants in pairs({farm={1,2},factory={1},oil_well={1},oil_refinery={1}}) do
  local is_oil=kind:match("^oil_")
  for _,variant in ipairs(variants) do check(kind,variant,is_oil and Oil or Farm,is_oil and OilWorld or FarmWorld) end
end
for i,cell in ipairs(Oil.layout.oil_well[1]) do
  local role,atlas=OilWorld.visual_asset("industry_oil_well_l1",cell,i)
  local expected=Oil.layout.oil_well[0][i]
  assert(role==("industry_oil_well_%d_%d"):format(expected[1],expected[2]))
  assert(atlas=="industry_oil_well_atlas")
  local mesh=assert(io.open(root.."models/bl_"..role..".obj","rb"));mesh:close()
end
local Art=m("industry_layout_art")
local function present(style,layout,resolve)
  for index,cell in ipairs(layout) do
    local mesh,atlas=resolve(style,cell,index)
    local f=assert(io.open(root.."models/bl_"..mesh..".obj","rb"));assert(f:read(2));f:close()
    f=assert(io.open(root.."textures/bl_"..atlas..".png","rb"));assert(f:read(2));f:close()
  end
end
for style,layout in pairs(Art.farm_footprint) do
  present(style,layout,function(id,cell) return Art.farm_asset(id,cell[1],cell[2]) end)
end
present("industry_oil_refinery_l1",Oil.layout.oil_refinery[1],OilWorld.visual_asset)
local TimberWorld=m("timber_world")(Sim,Terrain,Timber)
check("forest",1,Timber,TimberWorld)
present("forest_1",Timber.layout.forest[1],function(id,cell)
  return ("%s_%d_%d"):format(id,cell[1],cell[2]),"forest_atlas"
end)
local core_files={}
function core_files.get_dir_list(path)
  local rows={}
  local fd=assert(io.popen("ls "..path))
  for name in fd:lines() do rows[#rows+1]=name end
  fd:close()
  return rows
end
local heavy=m("openttd/iron_steel_rules")(Farm,m("openttd/iron_steel_data"))
local W=m("openttd/industry_worldgen")(Coal,Timber,Oil,heavy,true,Art.available(core_files,root:sub(1,-2)))
local types,footprints=0,0
for _,spec in pairs(W.specs) do
  types=types+1
  for variant in pairs(spec.layout) do
    assert(spec.available[variant],spec.kind.." source layout missing: "..variant)
    footprints=footprints+1
  end
end
assert(types==10 and footprints==23)
print("PASS all 23 pinned RC1 layouts ready for generation; six alternate Farm/Factory/Oil/Forest placements preserve source cells and real art")
