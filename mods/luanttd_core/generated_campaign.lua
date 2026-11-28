-- Native world and town adapter. Terrain, town placement, name selection
-- and initial growth budgets are delegated to the pinned OpenTTD ports.
-- The host mounts only the houses and ground construction it can render.
local M={}
M.size=64
local axis={[64]=true,[128]=true,[256]=true,[512]=true,[1024]=true,[2048]=true,[4096]=true}
function M.supports_size(width,depth)
  return axis[width]==true and axis[depth]==true
end
local function copy(t)
  local r={}
  for k,v in pairs(t) do r[k]=v end
  return r
end

function M.landscape(Sim,Terrain,Generator,settings)
  assert(M.supports_size(settings.width,settings.depth), "Stock campaign axes are powers of two from 64 to 4096.")
  local map,rivers=Generator.generate(settings)
  assert(map.width==settings.width and map.depth==settings.depth and type(map.rng_after)=="table")
  Sim.W,Sim.H=map.width,map.depth
  local s={version=1,seed=map.seed,day=0,tiles={},sites={},companies={},stations={},fleet={},
    next_station=1,next_vehicle=1,topology=0,subsidies={},speed=1,
    news={"A new transport charter opens in a generated region."}}
  local corner=Terrain.new(Sim.W,Sim.H,map.corner,{freeform_edges=settings.freeform_edges,max_height=255,
    pulse=settings.corner_progress})
  s.corner_grid=corner
  local dry_count=0
  for z=1,Sim.H do
    if settings.host_progress and (z-1)%16==0 then settings.host_progress((z-1)/Sim.H) end
    for x=1,Sim.W do
      local kind,ground,clear_ground,water_rocks=Generator.describe(map.tile(x,z))
      -- RC1 CountLandTiles uses IsWaterTile, not just TileType::Water.
      -- Coast and both rock subtypes are not plain water. Void is
      -- also counted by the original Map::Iterate loop.
      if kind~=6 or ground==2 or water_rocks then dry_count=dry_count+1 end
      local _,base=Terrain.tile(corner,x,z)
      local t={h=base,variant=(3*x+5*z+math.floor(x*z/16))%4}
      if kind==7 then t.terrain="water";t.stock_void=true
      elseif kind==6 then
        t.terrain="water";t.water_class=ground==3 and "river" or "sea";t.coastal_water=ground==2 or nil
        t.stock_water_rocks=water_rocks or nil
        if t.water_class=="river" then t.stock_river_bits=assert(map.river_bits(x,z)) end
      else
        assert(kind==0 or kind==4 and map.river_tree,"Unexpected stock landscape class")
        t.terrain=base>0 and "hill" or "grass"
        t.stock_clear_ground=clear_ground and clear_ground>0 and clear_ground or nil
        if kind==4 then t.wood=assert(map.river_tree(x,z)) end
      end
      s.tiles[Sim.id(x,z)]=t
    end
  end
  local persisted=copy(settings)
  persisted.progress,persisted.corner_progress,persisted.host_progress=nil,nil,nil
  s.stock_generated_profile={version=1,width=Sim.W,depth=Sim.H,terrain="terragenesis-16.0-RC1",
    settings=persisted,terrain_rng=copy(map.rng_after),clear_attempts=map.clear_attempts,
    initial_land_count=math.min(Sim.W*Sim.H,dry_count+math.floor(dry_count/12)),
    map_height_limit=settings.map_height_limit and settings.map_height_limit>0 and settings.map_height_limit or
      math.max(30,math.min(255,(map.estimated_max_height or 0)+15))}
  if map.river_tileloop_cursor then
    s.stock_generated_profile.river_rng_cursor=map.river_tileloop_cursor
    s.stock_generated_profile.river_stats=rivers
  end
  s.stock_coastal_profile=true
  return s
end

local source=debug and debug.getinfo(1,"S").source
local path=(core and core.get_modpath and core.get_modpath("luanttd_core") and core.get_modpath("luanttd_core").."/")
  or assert(source and source:sub(2):match("^(.+[\\/])"),"Cannot locate stock town assets")
local art=dofile(path.."stock_town_art.lua")
local Lift=dofile(path.."openttd/town_lift.lua")
local growth_board=dofile(path.."town_generation_board.lua")
local function get(Sim,Terrain,s,x,z)
  local id=Sim.id(x,z)
  local t=id and s.tiles[id]
  if not t then return nil end
  if t.stock_void then return {kind="void"} end
  local slope,base,top=Terrain.tile(s.corner_grid,x,z)
  if t.terrain=="water" then
    return {kind="water",water_ground=not t.coastal_water,coast=t.coastal_water,
      slope=slope,base=base,max_z=8*top,sea=t.water_class=="sea" and not t.coastal_water,water_rocks=t.stock_water_rocks}
  end
  local kind=t.build=="road" and "road" or t.house and "house" or t.build and "object" or t.wood and "trees" or "clear"
  return {kind=kind,slope=slope,base=base,max_z=8*top,road_bits=t.road_bits or 0,
    road_town=t.road_town,owner=t.owner,rough=t.stock_clear_ground==1}
end

function M.towns(Sim,Terrain,s,Generator,Worldgen,Names,G,Build,settings)
  local profile=s.stock_generated_profile
  assert(profile and not profile.towns,"Stock towns should be generated once")
  local growth_setting=tonumber(settings.growth_setting) or 2
  growth_setting=math.max(0,math.min(4,math.floor(growth_setting)))
  local state=copy(profile.terrain_rng)
  local function random() return Generator.next_random(state) end
  local save={version=1,order={},towns={}}
  local lifts=Lift.new(s.stock_world_animations)
  local growth=growth_board(Sim,Terrain,s,G,Worldgen,function(x,z)return get(Sim,Terrain,s,x,z) end)
  local board={width=Sim.W,height=Sim.H,freeform=s.corner_grid.freeform_edges,towns={},
    initial_land_count=profile.initial_land_count}
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
    local placed,built_lifts,spans={},{},{}
    local had=s.has_town_roads
    local function commit(p)
      if p.kind=="road" then
        local tile=Sim.id(p.x,p.z)
        if not Sim.town_road_piece(s,id,tile,p.bits,true) then return false end
        placed[tile]=true
        return true
      end
      if p.kind=="bridge" or p.kind=="tunnel" then
        local a,b=Sim.id(p.x,p.z),Sim.id(p.u,p.v)
        local ok
        if p.kind=="bridge" then ok=Sim.road_bridge(s,"town",a,b,p.style,false,id)
        else ok=Sim.road_tunnel(s,"town",a,false,id,growth.excavation,rnd) end
        if ok then spans[#spans+1]=a end
        return ok
      end
      if p.kind~="house" then return false end
      local parts=art.inspect(Sim,p,function(id)
        local x,z=Sim.xy(id)
        local ground=growth.tile(x,z)
        if ground and not ground.bridge_above and ground.slope and ground.slope<16 and
            growth.clear_quote(x,z,"house") then
          return ground.max_z/8
        end
      end)
      if not parts then return false end
      for _,part in ipairs(parts) do
        local tile,h=part.id,part.record
        local t=s.tiles[tile]
        if t.coastal_water then assert(Sim.town_clear_coast(s,tile,true)) end
        if t.build=="road" then
          assert(Sim.town_clear_road_tip(s,tile,true))
        end
        placed[tile]=true
        art.stamp(h,p,art[p.id],part.index)
        if h.completed then h.age,h.age_epoch=0,settings.year end
        local x,z=Sim.xy(tile)
        local _,base=Terrain.tile(s.corner_grid,x,z)
        t.house,t.source_house,t.wood,t.stock_clear_ground,t.h=true,h,nil,nil,base
        if Lift.supports(h) then built_lifts[#built_lifts+1]=tile end
      end
      return true
    end
    Worldgen.initialize(town,growth,{year=settings.year,allow_roads=true,
      initial_city_size=settings.initial_city_size,growth_setting=growth_setting,commit=commit},rnd)
    if town.population==0 then
      -- CmdDeleteTown removes failed town buildings and roads, not
      -- previously executed corner shaping or shore clearing.
      for _,tile in ipairs(spans) do assert(Sim.discard_generated_town_span(s,tile,id)) end
      for tile in pairs(placed) do
        local t=s.tiles[tile]
        t.build,t.road_bits,t.road_town,t.house,t.source_house=nil,nil,nil,nil,nil
        t.stock_clear_ground,t.stock_clear_density,t.stock_clear_visits=nil,nil,nil
      end
      s.has_town_roads=had
      s.sites[id]=nil
      return nil
    end
    for _,id in ipairs(built_lifts) do Lift.install(lifts,id,Sim) end
    site.population=town.population
    save.towns[id],save.order[#save.order+1]=town,id
    return {x=candidate.x,z=candidate.z,id=id,name=site.name,population=town.population}
  end
  local result,why=Worldgen.generate(board,opts)
  if not result or #s.sites==0 then return nil,why or "OpenTTD's placement rules found no viable town on this seed." end
  s.stock_town_growth,s.stock_town_lifts=save,lifts
  profile.towns=#s.sites
  profile.town_settings=copy(settings)
  profile.town_settings.progress=nil
  profile.town_settings.growth_setting=growth_setting
  profile.town_rng=copy(state)
  s.passenger_rating_rng=copy(state)
  return result
end

function M.industries(Sim,Terrain,s,Generator,Industry,World,density,custom_count,Timber,Oil,Farm,progress,Heavy)
  local profile=assert(s.stock_generated_profile)
  assert(profile.town_rng and not profile.industry_rng)
  if density==6 then
    -- The playable adapter can represent only a few layouts and has
    -- few towns. Avoid hundreds of millions of pointless failed queries.
    custom_count=math.max(1,math.min(64,math.floor(custom_count or 1)))
  end
  local state=copy(profile.town_rng)
  local board={width=Sim.W,height=Sim.H,freeform=s.corner_grid.freeform_edges,towns={},
    initial_land_count=profile.initial_land_count}
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
    tile.bridge_above=Sim.bridge_deck_at(s,id)
    tile.bridge=tile.bridge_above~=nil
    return tile
  end
  local Platform=dofile(path.."openttd/industry_platform_level.lua")(Terrain)
  if Platform then
    local function terraform_options()
      return {capture_stock_tops=true,void=function(x,z)return s.tiles[Sim.id(x,z)].stock_void end,
        validate_tile=function(_,x,z)
        local t=board.tile(x-1,z-1)
        local id=Sim.id(x,z)
        return t and (t.kind=="clear" or t.kind=="trees" or t.coast) and not t.owner and not t.bridge_above
          and not (s.tunnel_below and s.tunnel_below[id]) and 0 or nil
      end}
    end
    function board.terraform_quote(x,z,raise)
      return Terrain.plan(s.corner_grid,x+1,z+1,8,raise,terraform_options())~=nil
    end
    function board.level_platform(kind,platform,cells)
      local receipt,shadow=Platform.plan(s.corner_grid,platform,terraform_options)
      for _,c in ipairs(cells) do
        local slope,h=Terrain.tile(shadow,c.x+1,c.z+1)
        if slope~=0 or h~=platform.level then return nil,"PLATFORM_NOT_LEVEL" end
      end
      return receipt
    end
  end
  local function platform_draws(plan,random)
    if not plan.leveling then return end
    local height_limit=profile.map_height_limit
    local ground={}
    for _,cmd in ipairs(plan.leveling.commands) do
      for pass=0,1 do
        for _,t in ipairs(cmd.touched or {}) do
          local rocky=math.floor(random()*height_limit/4294967296)<=t.top
          if pass==1 then ground[Sim.id(t.x,t.z)]=not cmd.raise and rocky and 2 or false end
        end
      end
    end
    plan.platform_ground=ground
  end
  local choices={}
  local function commit(plan)
    local record=Industry.record(plan,0,{year=Sim.date(s)})
    local site=s.sites[plan.town]
    local id=Sim.id(plan.x+1,plan.z+1)
    local opts={record=record,name=site.name.." "..plan.name}
    local placed,cells
    local chain
    if plan.leveling then
      assert(Platform.apply(s.corner_grid,plan.leveling))
      for _,d in ipairs(plan.leveling.dirty) do
        local tile=Sim.id(d.x,d.z)
        local t=s.tiles[tile]
        if t.coastal_water then
          t.coastal_water,t.water_class,t.stock_water_rocks,t.stock_river_bits=nil,nil,nil,nil
        end
        local _,base=Terrain.tile(s.corner_grid,d.x,d.z)
        t.h,t.terrain,t.wood,t.stock_clear_ground=base,base>0 and "hill" or "grass",nil,
          plan.platform_ground and plan.platform_ground[tile] or nil
        if s.stock_farm_fields then s.stock_farm_fields[tile]=nil end
      end
    end
    -- The exact placement quote already admitted these tree tiles.
    -- Upstream clears each occupied layout cell before writing industry
    -- tiles, even when no platform leveling was needed. River generation
    -- can leave live trees on level footprint cells before GenerateTrees.
    local cleared_trees={}
    for _,c in ipairs(plan.cells) do
      local tile=Sim.id(c.x+1,c.z+1)
      local t=s.tiles[tile]
      if t.wood then
        cleared_trees[tile],t.wood=t.wood,nil
      end
    end
    if plan.type==2 or plan.type==3 then
      chain="timber"
      assert(Timber,"Generated Timber needs its native industry world")
      placed,cells=Timber.place_generated(s,plan.kind,id,opts)
    elseif plan.type==4 or plan.type==11 then
      chain="oil"
      assert(Oil,"Generated Oil needs its native industry world")
      placed,cells=Oil.place_generated(s,plan.kind,id,opts)
    elseif plan.type==8 or plan.type==18 then
      chain="heavy"
      placed,cells=assert(Heavy).place_generated(s,plan.kind,id,opts)
    elseif plan.type==6 or plan.type==9 then
      chain="farm"
      assert(Farm,"Generated Farm needs its native industry world")
      placed,cells=Farm.place_generated(s,plan.kind,id,opts,function() return Generator.next_random(state) end)
    else
      chain="coal"
      placed,cells=World.place(s,plan.kind,id,opts)
    end
    if not placed then
      for tile,tree in pairs(cleared_trees) do s.tiles[tile].wood=tree end
      return false
    end
    for _,c in ipairs(cells) do s.tiles[c.id].stock_clear_ground=nil end
    choices[#choices+1]={industry=placed.id,site=placed.site,kind=plan.kind,tile=id,near=plan.town,
      chain=chain,leveled=plan.leveling and #plan.leveling.changes>0 or nil}
    return true
  end
  local result=Industry.generate(board,{random=function() return Generator.next_random(state) end,
    density=density,custom_count=custom_count,commit=commit,progress=progress,
    prepare=platform_draws,rc1=true})
  profile.industry_rng=copy(state)
  profile.industry_density=density
  profile.rc1_industry_phase=true
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
      local town=s.stock_town_growth and s.stock_town_growth.towns[site.id]
      board.towns[#board.towns+1]={id=site.id,x=x,z=z,edge_radius_squared=town and town.radii[1]}
    end
  end
  function board.tile(x,z)
    local id=Sim.id(x,z)
    local t=id and s.tiles[id]
    if not t then return end
    local slope,base=Terrain.tile(s.corner_grid,x,z)
    local class=t.stock_void and 7 or t.stock_landmark and 10 or t.stock_industry and 8 or t.wood and 4 or t.terrain=="water" and 6 or
      t.house and 3 or t.build=="road" and 2 or (t.site or t.build) and 10 or 0
    local field=s.stock_farm_fields and s.stock_farm_fields[id]
    return {class=class,slope=slope,height=base,bridge_above=s.bridge_above and s.bridge_above[id]~=nil or
      s.rail_bridge_above and s.rail_bridge_above[id]~=nil,
      object_type=t.stock_landmark and t.stock_landmark.type,ground=field and 3 or t.stock_clear_ground,
      water=t.coastal_water and "coast" or t.water_class,rocky=t.stock_water_rocks}
  end
  local result=Objects.generate(board,profile.industry_rng,Generator.next_random,{date=date})
  result.each(function(x,z,record)
    local id=Sim.id(x,z)
    local t=s.tiles[id]
    t.stock_landmark,t.stock_clear_ground=record,nil
    if s.stock_farm_fields then s.stock_farm_fields[id]=nil end
  end)
  if result.each_rock then
    result.each_rock(function(x,z,ground,wet)
      local id=Sim.id(x,z)
      local t=s.tiles[id]
      t.stock_clear_ground,t.stock_water_rocks=ground,wet
      if ground and s.stock_farm_fields then s.stock_farm_fields[id]=nil end
    end)
  end
  profile.object_rng,profile.object_stats=copy(result.rng_after),result.stats
  return result
end

function M.forests(Sim,Terrain,s,Generator,Trees,tree_placer,pulse)
  local profile=assert(s.stock_generated_profile)
  assert(not profile.forest,"Stock forests should be generated once")
  local start=profile.object_rng or profile.industry_rng or profile.town_rng
  local board={width=Sim.W,depth=Sim.H,freeform=s.corner_grid.freeform_edges}
  function board.tile(x,z)
    local id=Sim.id(x,z)
    local t=id and s.tiles[id]
    if not t or t.stock_void or t.build or t.house or t.wood or t.site or t.stock_industry or t.stock_landmark then return end
    local slope,base=Terrain.tile(s.corner_grid,x,z)
    local field=s.stock_farm_fields and s.stock_farm_fields[id]
    return {class=t.terrain=="water" and 6 or 0,ground=field and 3 or t.stock_clear_ground or 0,
      slope=slope,height=base,coast=t.coastal_water==true,rocky=t.stock_water_rocks==true,
      bridge_above=s.bridge_above and s.bridge_above[id]~=nil or
        s.rail_bridge_above and s.rail_bridge_above[id]~=nil}
  end
  local result=Trees.generate(board,start,Generator.next_random,{tree_placer=tree_placer,pulse=pulse,
    map_height_limit=profile.map_height_limit or 30})
  local n=0
  result.each(function(x,z,record)
    n=n+1
    if pulse and n%2048==0 then pulse() end
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
