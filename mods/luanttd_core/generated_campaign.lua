-- Native world and town adapter. Terrain, town placement, name selection
-- and initial growth budgets are delegated to the pinned OpenTTD ports.
-- The host mounts only the houses and ground construction it can render.
local M={}
M.size=64
local axis={[64]=true,[128]=true,[256]=true,[512]=true,[1024]=true,[2048]=true,[4096]=true}
function M.supports_size(width,depth)
  return axis[width]==true and axis[depth]==true and width*depth<=512*512
end
local function copy(t)
  local r={}
  for k,v in pairs(t) do r[k]=v end
  return r
end

function M.landscape(Sim,Terrain,Generator,settings)
  assert(M.supports_size(settings.width,settings.depth), "Stock campaign axes are powers of two from 64 to 4096, up to 262,144 tiles total.")
  local map,rivers=Generator.generate(settings)
  assert(map.width==settings.width and map.depth==settings.depth and type(map.rng_after)=="table")
  Sim.W,Sim.H=map.width,map.depth
  local s={version=1,seed=map.seed,day=0,tiles={},sites={},companies={},stations={},fleet={},
    next_station=1,next_vehicle=1,topology=0,subsidies={},speed=1,
    news={"A new transport charter opens in a generated region."}}
  local corner=Terrain.new(Sim.W,Sim.H,map.corner,{freeform_edges=settings.freeform_edges,max_height=255})
  s.corner_grid=corner
  for z=1,Sim.H do
    for x=1,Sim.W do
      local kind,ground,clear_ground=Generator.describe(map.tile(x,z))
      local _,base=Terrain.tile(corner,x,z)
      local t={h=base,variant=(3*x+5*z+math.floor(x*z/16))%4}
      if kind==7 then t.terrain="water";t.stock_void=true
      elseif kind==6 then
        t.terrain="water";t.water_class=ground==3 and "river" or "sea";t.coastal_water=ground==2 or nil
        if t.water_class=="river" then t.stock_river_bits=assert(map.river_bits(x,z)) end
      else
        assert(kind==0,"Unexpected stock landscape class")
        t.terrain=base>0 and "hill" or "grass"
        t.stock_clear_ground=clear_ground and clear_ground>0 and clear_ground or nil
      end
      s.tiles[Sim.id(x,z)]=t
    end
  end
  s.stock_generated_profile={version=1,width=Sim.W,depth=Sim.H,terrain="terragenesis-14.1",
    settings=copy(settings),terrain_rng=copy(map.rng_after),clear_attempts=map.clear_attempts}
  if map.river_tileloop_cursor then
    s.stock_generated_profile.river_rng_cursor=map.river_tileloop_cursor
    s.stock_generated_profile.river_stats=rivers
  end
  s.stock_coastal_profile=true
  return s
end

-- Existing purpose-made asset styles only; unsupported house types
-- remain unbuilt, not replaced with arbitrary approximations.
local art={
  [0x19]={variant=0},[0x18]={variant=1},[0x1A]={variant=2},[0x06]={variant=3},
  [0x0E]={parcel="shop"},
}
local dirx,dirz={[0]=-1,0,1,0},{[0]=0,1,0,-1}
local function has(bits,bit) return math.floor(bits/bit)%2~=0 end
local function edge(Sim,x,z)
  return math.min(x-1,z-1,Sim.W-x,Sim.H-z)
end
local function get(Sim,Terrain,s,x,z)
  local id=Sim.id(x,z)
  local t=id and s.tiles[id]
  if not t then return nil end
  if t.stock_void then return {kind="void"} end
  if t.terrain=="water" then return {kind="water",water_ground=not t.coastal_water,coast=t.coastal_water} end
  local slope,base,top=Terrain.tile(s.corner_grid,x,z)
  local kind=t.build=="road" and "road" or t.house and "house" or t.build and "object" or "clear"
  return {kind=kind,slope=slope,base=base,max_z=8*top,road_bits=t.road_bits or 0,
    road_town=t.road_town,owner=t.owner}
end
local function growth_board(Sim,Terrain,s)
  local B={}
  function B.tile(x,z) return get(Sim,Terrain,s,x,z) end
  function B.distance_to_edge(x,z) return edge(Sim,x,z) end
  function B.house_supported(id,x,z)
    local t=B.tile(x,z)
    return art[id]~=nil and t and t.slope==0
  end
  function B.road_allowed(town,x,z,d)
    local t=B.tile(x,z)
    if not t or (t.kind~="clear" and t.kind~="road") or t.slope~=0 or edge(Sim,x,z)<=0 then return false end
    if t.road_town and t.road_town~=town.id then return false end
    -- IsNeighborRoadTile (town_cmd.cpp), for ordinary flat tile layouts.
    local dist=town.layout=="original" and 1 or 2
    for pos=4,(dist+1)*4-1 do
      local side=(d+(pos%2==1 and 1 or 3))%4
      local back=math.floor(pos/2)%2==1
      local n=math.floor(pos/4)
      local u,v=x+dirx[side]*n,z+dirz[side]*n
      if back then u,v=u-dirx[d],v-dirz[d] end
      local neighbor=B.tile(u,v)
      local bit=2^(3-(back and d or (d+2)%4))
      if neighbor and neighbor.kind=="road" and has(neighbor.road_bits,bit) then return false end
    end
    return true
  end
  function B.clean_road_bits(_,x,z,bits)
    -- road.cpp CleanUpRoadBits, supported clear/normal road/shore classes.
    for d=0,3 do
      local b=2^(3-d)
      if has(bits,b) then
        local t=B.tile(x+dirx[d],z+dirz[d])
        if not t or (t.kind~="clear" and t.kind~="road" and not t.coast) then bits=bits-b end
      end
    end
    return bits
  end
  function B.road_quote(town,x,z,bits)
    local t=B.tile(x,z)
    if not t or t.slope~=0 or (t.kind~="clear" and t.kind~="road") or
        t.owner or t.road_town and town.id~=t.road_town then return end
    for e=0,3 do
      local bit=2^e
      if has(bits,bit) and not has(t.road_bits,bit) then return Sim.id(x,z) end
    end
  end
  return B
end

function M.towns(Sim,Terrain,s,Generator,Worldgen,Names,G,Build,settings)
  local profile=s.stock_generated_profile
  assert(profile and not profile.towns,"Stock towns should be generated once")
  local state=copy(profile.terrain_rng)
  local function random() return Generator.next_random(state) end
  local save={version=1,order={},towns={}}
  local growth=growth_board(Sim,Terrain,s)
  local board={width=Sim.W,height=Sim.H,freeform=s.corner_grid.freeform_edges,towns={}}
  function board.tile(x,z) return get(Sim,Terrain,s,x+1,z+1) end
  local opts=copy(settings)
  opts.random,opts.name=random,Names.generate
  function opts.create(candidate,rnd)
    local id=#s.sites+1
    local x,z=candidate.x+1,candidate.z+1
    local site={id=id,kind="town",name=assert(candidate.name),nameparts=candidate.nameparts,
      tile=Sim.id(x,z),stock={},produced={},received={},population=0,service=0,larger_town=candidate.city}
    local town=G.new(id,x,z,{layout=candidate.layout,larger_town=candidate.city,grow_counter=(id-1)%G.TOWN_TICKS})
    s.sites[id]=site
    local prior={}
    local had=s.has_town_roads
    local function remember(tile)
      if not prior[tile] then prior[tile]=copy(s.tiles[tile]) end
    end
    local function commit(p)
      if p.kind=="road" then
        local tile=Sim.id(p.x,p.z)
        remember(tile)
        local ok=Sim.seed_town_road(s,id,tile,p.bits)
        if ok then s.tiles[tile].stock_clear_ground=nil end
        return ok
      end
      if p.kind~="house" or #p.parts~=1 or not art[p.id] then return false end
      local h=p.parts[1]
      local tile=Sim.id(h.x,h.z)
      local t=s.tiles[tile]
      remember(tile)
      h.town_growth,h.random_bits=true,p.random_bits
      h.render_variant,h.render_parcel=art[p.id].variant,art[p.id].parcel
      t.house,t.source_house,t.wood,t.stock_clear_ground=true,h,nil,nil
      return true
    end
    Worldgen.initialize(town,growth,{year=settings.year,allow_roads=true,
      initial_city_size=settings.initial_city_size,growth_setting=2,commit=commit},rnd)
    if town.population==0 then
      for i,t in pairs(prior) do s.tiles[i]=t end
      s.has_town_roads=had
      s.sites[id]=nil
      return nil
    end
    site.population=town.population
    save.towns[id],save.order[#save.order+1]=town,id
    return {x=candidate.x,z=candidate.z,id=id,name=site.name,population=town.population}
  end
  local result,why=Worldgen.generate(board,opts)
  if not result or #s.sites==0 then return nil,why or "OpenTTD's placement rules found no viable town on this seed." end
  s.stock_town_growth=save
  profile.towns=#s.sites
  profile.town_settings=copy(settings)
  profile.town_rng=copy(state)
  s.passenger_rating_rng=copy(state)
  return result
end

function M.industries(Sim,Terrain,s,Generator,Industry,World,density,custom_count,Timber,Oil,Farm)
  local profile=assert(s.stock_generated_profile)
  assert(profile.town_rng and not profile.industry_rng)
  if density==6 then
    -- The playable adapter can represent only a few layouts and has
    -- few towns. Avoid hundreds of millions of pointless failed queries.
    custom_count=math.max(1,math.min(64,math.floor(custom_count or 1)))
  end
  local state=copy(profile.town_rng)
  local board={width=Sim.W,height=Sim.H,freeform=s.corner_grid.freeform_edges,towns={}}
  for _,site in ipairs(s.sites) do
    if site.kind=="town" then
      local x,z=Sim.xy(site.tile)
      board.towns[#board.towns+1]={id=site.id,x=x-1,z=z-1}
    end
  end
  function board.tile(x,z)
    local u,v=x+1,z+1
    local id=Sim.id(u,v)
    local native=id and s.tiles[id]
    if not native then return end
    local tile=get(Sim,Terrain,s,u,v)
    tile.slope,tile.base=Terrain.tile(s.corner_grid,u,v)
    tile.corner_height=Terrain.corner(s.corner_grid,u,v)
    if native.stock_industry then tile.kind="industry";tile.industry=true end
    return tile
  end
  local choices={}
  local function commit(plan)
    local record=Industry.record(plan,0,{year=Sim.date(s)})
    local site=s.sites[plan.town]
    local id=Sim.id(plan.x+1,plan.z+1)
    local opts={record=record,name=site.name.." "..plan.name}
    local placed,cells
    local chain
    if plan.type==2 or plan.type==3 then
      chain="timber"
      assert(Timber,"Generated Timber needs its native industry world")
      placed,cells=Timber.place_generated(s,plan.kind,id,opts)
    elseif plan.type==4 or plan.type==11 then
      chain="oil"
      assert(Oil,"Generated Oil needs its native industry world")
      placed,cells=Oil.place_generated(s,plan.kind,id,opts)
    elseif plan.type==6 or plan.type==9 then
      chain="farm"
      assert(Farm,"Generated Farm needs its native industry world")
      placed,cells=Farm.place_generated(s,plan.kind,id,opts,function() return Generator.next_random(state) end)
    else
      chain="coal"
      placed,cells=World.place(s,plan.kind,id,opts)
    end
    if not placed then return false end
    for _,c in ipairs(cells) do s.tiles[c.id].stock_clear_ground=nil end
    choices[#choices+1]={industry=placed.id,site=placed.site,kind=plan.kind,tile=id,near=plan.town,
      chain=chain}
    return true
  end
  local result=Industry.generate(board,{random=function() return Generator.next_random(state) end,
    density=density,custom_count=custom_count,commit=commit})
  profile.industry_rng=copy(state)
  profile.industries=choices
  profile.timber_generation=Timber and true or nil
  profile.industry_stats={target=result.target,shortfall=result.shortfall,attempted=result.attempted}
  return result
end

function M.landmarks(Sim,Terrain,s,Generator,Objects,date)
  local profile=assert(s.stock_generated_profile)
  assert(profile.industry_rng and not profile.object_rng)
  local board={width=Sim.W,depth=Sim.H,freeform=s.corner_grid.freeform_edges,towns={}}
  for _,site in ipairs(s.sites) do
    if site.kind=="town" then
      local x,z=Sim.xy(site.tile)
      board.towns[#board.towns+1]={id=site.id,x=x,z=z}
    end
  end
  function board.tile(x,z)
    local id=Sim.id(x,z)
    local t=id and s.tiles[id]
    if not t then return end
    local slope,base=Terrain.tile(s.corner_grid,x,z)
    local class=t.stock_void and 7 or t.stock_landmark and 10 or t.stock_industry and 8 or t.terrain=="water" and 6 or
      t.house and 3 or t.build=="road" and 2 or (t.site or t.build) and 10 or 0
    return {class=class,slope=slope,height=base,bridge_above=s.bridge_above and s.bridge_above[id]~=nil or
      s.rail_bridge_above and s.rail_bridge_above[id]~=nil,
      object_type=t.stock_landmark and t.stock_landmark.type}
  end
  local result=Objects.generate(board,profile.industry_rng,Generator.next_random,{date=date})
  result.each(function(x,z,record)
    local t=s.tiles[Sim.id(x,z)]
    t.stock_landmark,t.stock_clear_ground=record,nil
  end)
  profile.object_rng,profile.object_stats=copy(result.rng_after),result.stats
  return result
end

function M.forests(Sim,Terrain,s,Generator,Trees,tree_placer)
  local profile=assert(s.stock_generated_profile)
  assert(not profile.forest,"Stock forests should be generated once")
  local start=profile.object_rng or profile.industry_rng or profile.town_rng
  local board={width=Sim.W,depth=Sim.H,freeform=s.corner_grid.freeform_edges}
  function board.tile(x,z)
    local id=Sim.id(x,z)
    local t=id and s.tiles[id]
    if not t or t.stock_void or t.build or t.house or t.site or t.stock_industry or t.stock_landmark then return end
    local slope,base=Terrain.tile(s.corner_grid,x,z)
    return {class=t.terrain=="water" and 6 or 0,ground=t.stock_clear_ground or 0,
      slope=slope,height=base,coast=t.coastal_water==true,
      bridge_above=s.bridge_above and s.bridge_above[id]~=nil or
        s.rail_bridge_above and s.rail_bridge_above[id]~=nil}
  end
  local result=Trees.generate(board,start,Generator.next_random,{tree_placer=tree_placer})
  result.each(function(x,z,record)
    -- The existing construction/clearance paths clear wood; storing the
    -- source record here makes the whole tree tile disappear atomically.
    s.tiles[Sim.id(x,z)].wood=record
  end)
  profile.forest=copy(result.rng_after)
  profile.forest_stats=copy(result.stats)
  s.passenger_rating_rng=copy(result.rng_after)
  return result
end
return M
