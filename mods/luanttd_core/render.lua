return function(api)
  local Sim,S=api.Sim,api.s
  local modpath=core.get_modpath("luanttd_core")
  local road_motion=dofile(modpath.."/road_motion.lua")
  local road_lanes=dofile(modpath.."/road_lanes.lua")
  local source_motion=dofile(modpath.."/road_motion_presentation.lua")(road_lanes)
  local source_pose_model=dofile(modpath.."/road_source_pose.lua")(Sim,source_motion)
  local road_fault_view=dofile(modpath.."/road_fault_view.lua")(function(p) return core.add_particle(p) end)
  local R={}
  local visual=dofile(modpath.."/campaign_visual_state.lua")(Sim,S)
  local terrain=api.terrain
  local terrain_view=terrain and setmetatable({},{__index=function(_,k) return terrain[k] end})
  local projected=false
  local rail_track=dofile(modpath.."/openttd/rail_track.lua")
  local diagonal=dofile(modpath.."/rail_diagonal.lua")(Sim,rail_track,terrain_view,api.trackworks and api.trackworks.surface)
  function R.rail_diagonal_pose(id,td,f)
    local mode=diagonal.mode(S,id)
    if mode~=0 then return diagonal.sample(td,f,mode) end
  end
  local ids={}
  local modes={rail="railv",road="roadv",water="waterv",air="airv"}
  local function png(n) return "bl_"..n..".png" end
  local function overlay(tex,n) return tex.."^"..png(n) end
  local function ground(t) return png(t.terrain..t.variant) end
  function R.mask(id,mode)
    local mask=0
    local t=S.tiles[id]
    if mode=="road" and S.corner_grid and Sim.road_edge then
      for d=1,4 do if Sim.road_edge(S,id,d) then mask=mask+2^(d-1) end end
      return mask
    end
    local function matching(j)
      local q=S.tiles[j]
      local b=q and Sim.tools[q.build]
      if q and q.build=="road_depot" and q.depot_dir and not (Sim.adjacent(j,q.depot_dir)==id) then return false end
      if t.build=="road_depot" and t.depot_dir and Sim.adjacent(id,t.depot_dir)~=j then return false end
      return b and b.mode==mode and q.owner==t.owner
    end
    for d=1,4 do local j=Sim.adjacent(id,d);if j and matching(j) then mask=mask+2^(d-1) end end
    return mask
  end
  function R.texture(id,vehicles,selected,anchor,cov)
    local t=S.tiles[id]
    local tex=ground(t)
    if t.site then
      local kind=S.sites[t.site].kind
      tex=overlay(tex,kind=="stock_coal_mine" and "mine" or kind=="stock_power_station" and "mill" or kind)
    elseif t.house then tex=overlay(tex,"house")
    elseif t.build then
      local mode=Sim.tools[t.build] and Sim.tools[t.build].mode or t.rail_span_id and "rail"
      if mode=="road" or mode=="rail" then tex=overlay(tex,mode..R.mask(id,mode)) end
      if t.station or t.build=="canal" then tex=overlay(tex,t.build)
      elseif t.build:find("_bridge") then tex=overlay(tex,"bridge")
      elseif t.build:find("_tunnel") then tex=overlay(tex,"tunnel") end
      if t.signal then tex=overlay(tex,t.closed and "closed" or "signal") end
    elseif t.wood then tex=overlay(tex,"wood"..t.variant) end
    if cov then tex=overlay(tex,"coverage") end
    if vehicles then tex=overlay(tex,modes[vehicles]) end
    if selected then tex=overlay(tex,"sel") end
    if anchor then tex=overlay(tex,"anchor") end
    return tex
  end
  local Bore=dofile(modpath.."/tunnel_bore.lua")
  local bore_ground_defs={}
  local function reg(n,tiles,def)
    local full="luanttd_core:"..n
    local d={description=n,tiles=tiles,diggable=false,pointable=not api.road_first,drop="",groups={not_in_creative_inventory=1},is_ground_content=false}
    for k,v in pairs(def or {}) do d[k]=v end
    core.register_node(full,d)
    if Bore.cover_candidate(n) then bore_ground_defs[full]=d end
    return full
  end
  local function water_tile(name,seconds,world)
    return {name=name,animation={type="vertical_frames",aspect_w=64,aspect_h=64,length=seconds},
      align_style=world and "world" or "node",scale=world or 1}
  end
  local function water_definition(mesh)
    return {drawtype=mesh and "mesh" or "nodebox",mesh=mesh,waving=3,
      use_texture_alpha="opaque",paramtype="light",sunlight_propagates=true,walkable=false,
      pointable=false,node_box=not mesh and {type="fixed",fixed={-.5,-.5,-.5,.5,.5,.5}} or nil}
  end
  local sea_top=water_tile("bl_water_sea_anim.png",4,4)
  local sea_top_phased=water_tile("bl_water_sea_anim.png",4)
  local sea_mesh={}
  for v=0,3 do for u=0,3 do
    local name=("ocean_top_%d_%d"):format(u,v)
    -- Native waving changes Y only and evaluates shared world vertices
    -- identically. Baked UV phases preserve the 4-node animation period.
    sea_mesh[v*4+u]=reg(name,{sea_top_phased},water_definition("bl_"..name..".obj"))
  end end
  local function ocean(x,z) return sea_mesh[(z%4)*4+x%4] end
  local water_side=png("water_side")
  local rock_side={name=png("hill_side"),align_style="world",scale=4}
  local gnames={}
  for _,t in ipairs({"grass","hill","water"}) do
    gnames[t]={}
    for v=0,3 do
      if t=="water" then
        gnames[t][v]=reg(t..v,{sea_top,water_side,water_side},water_definition())
      else
        gnames[t][v]=reg(t..v,{png(t..v),png(t..v),t=="hill" and rock_side or png("grass_side")})
      end
    end
  end
  local infrastructure={}
  local road_foundation_flat={}
  for _,mode in ipairs({"rail","road"}) do
    for mask=0,15 do
      for _,kind in ipairs({"plain","bridge","tunnel"}) do
        local n=mode.."_"..mask.."_"..kind
        local top=overlay(png(kind=="bridge" and "water0" or kind=="tunnel" and "hill0" or "grass0"),mode..mask)
        if kind~="plain" then top=overlay(top,kind) end
        infrastructure[n]={}
        if mode=="road" and kind=="plain" then road_foundation_flat[mask]={} end
        for j=0,3 do
          local surface=png(n.."_q"..j)
          -- Luanti tile slot 3 is all vertical faces, never a second road.
          local side=mode=="road" and png("grass_side") or top
          infrastructure[n][j]=reg(n.."_"..j,{surface,png("hill0"),side})
          if mode=="road" and kind=="plain" then
            road_foundation_flat[mask][j]=reg("road_foundation_"..mask.."_"..j,
              {surface,png("hill0"),png("road_surface_retaining")})
          end
        end
      end
    end
  end
  local town_streets,town_foundation_flat={},{}
  for mask=0,15 do
    town_streets[mask],town_foundation_flat[mask]={},{}
    for j=0,3 do
      local n="town_street_"..mask.."_"..j
      town_streets[mask][j]=reg(n,{png(n),png("hill0"),png("grass_side")})
      town_foundation_flat[mask][j]=reg(n.."_foundation",{png(n),png("hill0"),png("road_surface_retaining")})
    end
  end
  local props={}
  for _,n in ipairs({"rail_station","dock","airport","canal","signal","closed"}) do
    local base=n=="canal" and "water0" or "grass1"
    local color=({rail_station="#b18263",dock="#859a94",airport="#7f8ba3"})[n]
    local raised=color~=nil and n~="canal"
    local fixed={-.5,-.5,-.5,.5,n=="town" and .5 or .18,.5}
    local face=overlay(png(base),n)
    local side=color and "bl_panel.png^[colorize:"..color..":250" or png(base)
    props[n]=reg(n,{{name=face,align_style="world",scale=2},png(base),side},
      raised and {drawtype="nodebox",node_box={type="fixed",fixed=fixed}} or nil)
  end
  local function architecture(name,asset,palette,rotates,solid)
    return reg(name,{png(palette or "road_architecture")},{drawtype="mesh",mesh="bl_"..asset..".obj",
      paramtype="light",paramtype2=rotates and "facedir" or nil,sunlight_propagates=true,walkable=not not solid,pointable=false,
      collision_box=solid and {type="fixed",fixed=solid} or nil,
      selection_box={type="fixed",fixed={-.5,-.50,-.5,1.5,.60,1.5}}})
  end
  local crossing_mesh={}
  if api.crossings then
    for axis=0,1 do
      crossing_mesh[axis]={}
      for _,gate in ipairs({"open","closed"}) do
        local asset="level_crossing_"..axis.."_"..gate
        crossing_mesh[axis][gate]=architecture(asset,asset,"level_crossing_atlas")
      end
    end
  end
  local road_marks={}
  if api.oneway then
    local function mark(asset)
      road_marks[asset]=architecture(asset,asset,"oneway_atlas")
    end
    for d=0,3 do
      local shapes=d%2==0 and {0,3,12} or {0,6,9}
      for _,g in ipairs(shapes) do
        mark("oneway_"..d.."_g"..g)
        mark("oneway_paint_"..d.."_g"..g)
      end
    end
    for axis=0,1 do
      for _,g in ipairs(axis==0 and {0,3,12} or {0,6,9}) do
        mark("oneway_both_"..axis.."_g"..g)
      end
    end
  end
  local function one_way_node(id,y)
    local W=api.oneway
    local m=W and W.marking(S,id)
    if not m or y~=m.base+2 then return end
    if m.kind=="no-entry" then return road_marks["oneway_both_"..m.axis.."_g"..m.slope] end
    if not m.dir then return end
    local d1=4-m.dir
    local d2=(d1+1)%4+1
    local rear,front=Sim.adjacent(id,d1),Sim.adjacent(id,d2)
    local d=m.disallowed
    local interior=W.read(S.tiles[rear])==d and W.read(S.tiles[front])==d and
      rear and front and Sim.road_edge(S,id,d1) and Sim.road_edge(S,id,d2) and
      Sim.road_edge(S,rear,d2) and Sim.road_edge(S,front,d1)
    return road_marks[(interior and "oneway_paint_" or "oneway_")..m.dir.."_g"..m.slope]
  end
  local coal_rail_stage={}
  for _,role in ipairs({"load","unload"}) do
    coal_rail_stage[role]={}
    for axis=0,1 do
      local asset="rail_coal_stage_"..role.."_"..axis
      coal_rail_stage[role][axis]={
        architecture(asset,asset,"rail_coal_stage_atlas"),
        architecture(asset.."_mirror",asset.."_mirror","rail_coal_stage_atlas"),
      }
    end
  end
  local stock_rail,rail_grade,rail_eased={},{},{}
  for bits=1,63 do
    stock_rail[bits]=architecture("stock_rail_"..bits,"rail_track_"..bits,"rail_atlas")
  end
  for _,part in ipairs({4,8,16,32}) do
    rail_eased[part]={}
    for mode=1,3 do
      local name="rail_eased_"..part.."_"..mode
      rail_eased[part][mode]=architecture(name,name,"rail_atlas")
    end
  end
  stock_rail.guideway={}
  for gauge,kind in pairs({[2]="mono",[3]="maglev"}) do
    local guideway={flat={},eased={},grade={},station={},depot={}}
    stock_rail.guideway[gauge]=guideway
    local function mesh(variant)
      local name="guideway_"..kind.."_"..variant
      return architecture(name,name,"guideway_"..kind.."_atlas")
    end
    for bits=1,63 do guideway.flat[bits]=mesh("flat_"..bits) end
    for grade=1,4 do guideway.grade[grade]=mesh("grade_"..grade) end
    local function facility(variant)
      local name="guideway_"..kind.."_"..variant
      return architecture(name,name,"guideway_"..kind.."_facility_atlas")
    end
    for axis=0,1 do guideway.station[axis]=facility("platform_"..axis) end
    for dir=0,3 do guideway.depot[dir]=facility("depot_"..dir) end
    for _,bits in ipairs({4,8,16,32}) do
      guideway.eased[bits]={}
      for mode=1,3 do guideway.eased[bits][mode]=mesh("eased_"..bits.."_"..mode) end
    end
  end
  function stock_rail.visual(id,bits,gauge)
    local art=stock_rail.guideway[gauge]
    local eased=art and art.eased[bits] or not art and rail_eased[bits]
    return eased and eased[diagonal.mode(S,id)] or (art and art.flat[bits] or stock_rail[bits])
  end
  for grade=1,4 do rail_grade[grade]=architecture("stock_rail_grade_"..grade,"rail_grade_"..grade,"rail_atlas") end
  function stock_rail.grade_art(grade,gauge)
    local art=stock_rail.guideway[gauge]
    return art and art.grade[grade] or rail_grade[grade]
  end
  local rail_platform,rail_depot={},{}
  for axis=0,1 do
    local a="rail_platform_"..(2^axis)
    rail_platform[axis]=architecture("stock_"..a,a,"rail_architecture_atlas")
  end
  for dir=0,3 do
    local a="rail_depot_"..dir
    rail_depot[dir]=architecture("stock_"..a,a,"rail_architecture_atlas")
  end
  local coal_buildings={}
  if api.stock_coal_scenery then
    local assets={
      coal_mine_0={{0,0},{1,0},{1,1},{1,2},{2,0},{2,2}},
      power_station={{0,0},{1,0},{2,0},{3,0},{0,1},{1,1},{2,1},{3,1}},
    }
    for kind,positions in pairs(assets) do
      for _,pos in ipairs(positions) do
        local key=("%s_%d_%d"):format(kind,pos[1],pos[2])
        local asset=key=="coal_mine_0_1_1" and key.."_nosheaves" or key
        coal_buildings[key]=architecture(key,asset,kind=="coal_mine_0" and "coal_mine_atlas" or "power_station_atlas")
      end
    end
  end
  local timber_buildings,timber_harvested={}
  if api.stock_timber_scenery then
    for _,kind in ipairs({"forest","sawmill"}) do
      for layout=0,kind=="forest" and 1 or 0 do
        for _,cell in ipairs(api.timber_rules.layout[kind][layout]) do
          local mesh=("%s_%d_%d_%d"):format(kind,layout,cell[1],cell[2])
          timber_buildings[mesh]=architecture(mesh,mesh,kind.."_atlas")
        end
      end
    end
    timber_harvested=architecture("forest_harvested","forest_harvested","forest_atlas")
  end
  local farm_buildings,farm_fields={},{}
  if api.farm_world then
    local assets=api.farm_visual_assets
    for style,parts in pairs(assets.footprints) do
      for _,cell in ipairs(parts) do
        local mesh=("%s_%d_%d"):format(style,cell[1],cell[2])
        farm_buildings[mesh]=architecture(mesh,mesh,style.."_atlas")
      end
    end
    for _,slope in ipairs(assets.slopes) do
      farm_fields[slope]={}
      for v=0,8 do
        local key=("farm_ground_%d_%d"):format(slope,v)
        farm_fields[slope][v]=architecture(key,"farm_land_"..slope,"farm_field_"..v)
      end
    end
  end
  local oil_buildings={}
  if api.heavy_world then
    for style,parts in pairs(api.heavy_world.visual_sources()) do
      for _,part in ipairs(parts) do
        local mesh=("%s_%d_%d"):format(style,part[1],part[2])
        oil_buildings[mesh]=architecture(mesh,mesh,style.."_atlas")
      end
    end
  end
  if api.capabilities and api.capabilities.temperate_bank then
    for dx=0,1 do
      local name="industry_temperate_bank_"..dx.."_0"
      oil_buildings[name]=architecture(name,name,"industry_temperate_bank_atlas")
    end
  end
  if api.oil_world then
    for style,parts in pairs(api.oil_world.visual_sources()) do
      for _,cell in ipairs(parts) do
        local mesh=("%s_%d_%d"):format(style,cell[1],cell[2])
        oil_buildings[mesh]=architecture(mesh,mesh,style.."_atlas")
      end
    end
  end
  local airfield_nodes={}
  if api.airport_tools then
    local function airport_media(kind,asset,w,h)
      local nodes={}
      airfield_nodes[kind]=nodes
      for z=0,h-1 do
        nodes[z]={}
        for x=0,w-1 do
          local cell=("%s_%d_%d"):format(asset,x,z)
          nodes[z][x]=architecture(cell,cell,asset.."_atlas")
        end
      end
    end
    airport_media("country","small_airport",4,3)
    if api.capabilities and api.capabilities.city_airport then airport_media("city","city_airport",6,6) end
  end
  local ship_docks,ship_piers,ship_depots={},{},{}
  local aqueduct_head,aqueduct_span,aqueduct_pier_head,aqueduct_pier={},{},{},{}
  local ship_locks={lower={},middle={},upper={}}
  if api.ship_tools then
    for part,dirs in pairs(ship_locks) do
      for d=0,3 do
        local asset="ship_lock_"..part.."_"..d
        dirs[d]=architecture(asset,asset,"ship_lock_atlas")
      end
    end
    for d=0,3 do
      local head="aqueduct_head_"..d
      aqueduct_head[d]=architecture(head,head,"aqueduct")
    end
    for axis=0,1 do
      local span,cap,pier="aqueduct_span_"..axis,"aqueduct_pier_head_"..axis,"aqueduct_pier_"..axis
      aqueduct_span[axis]=architecture(span,span,"aqueduct")
      aqueduct_pier_head[axis]=architecture(cap,cap,"aqueduct")
      aqueduct_pier[axis]=architecture(pier,pier,"aqueduct")
    end
    for d=0,3 do
      local ramp,pier="ship_dock_ramp_"..d,"ship_dock_pier_"..d
      ship_docks[d]=architecture(ramp,ramp,"ship_facilities_atlas")
      ship_piers[d]=architecture(pier,pier,"ship_facilities_atlas")
    end
    for axis=0,1 do
      ship_depots[axis]={}
      for part=1,2 do
        local asset="ship_depot_"..axis.."_"..(part-1)
        ship_depots[axis][part]=architecture(asset,asset,"ship_facilities_atlas")
      end
    end
  end
  local tramway,tram_stops,tram_depots={},{},{}
  if api.tram_tools then
    tramway.grade,tramway.signed={},{}
    for _,slope in ipairs{3,6,9,12} do
      local asset="tramway_grade_"..slope
      tramway.grade[slope]=architecture(asset,asset,"tram_palette")
      tramway.signed[slope]=architecture(asset.."_signed",asset.."_signed","tram_palette")
    end
    local tram_crossing={}
    for axis=0,1 do
      local asset="tramway_crossing_"..axis
      tram_crossing[axis]=architecture(asset,asset,"tram_palette")
    end
    function R.tram_span_node(class,axis,head,height,x,y,z)
      if x%2~=0 or z%2~=0 then return end
      if class=="bridge" and y==height+1 then
        if head and not head.flat_ramp then return tramway.grade[head.road_slope] end
        return tramway[axis==0 and 10 or 5]
      end
      -- The portal sculpture is at base+1. Reuse the one-voxel
      -- translated, flat track/contact wire overlay at base+2.
      if class=="tunnel" and y==height+2 then
        return tram_crossing[axis]
      end
    end
    function R.tram_crossing_node(c,x,y,z)
      if c.tramtype==1 and y==c.top+2 and x%2==0 and z%2==0 then
        return tram_crossing[c.road_axis]
      end
    end
    for mask=1,15 do
      local asset="tramway_"..mask
      tramway[mask]=architecture(asset,asset,"tram_palette")
    end
    for axis=0,1 do
      local asset="tram_stop_"..axis
      tram_stops[axis]=architecture(asset,asset,"tram_facilities_atlas")
    end
    for dir=0,3 do
      local asset="tram_depot_"..dir
      tram_depots[dir]=architecture(asset,asset,"tram_facilities_atlas")
    end
    core.register_entity("luanttd_core:tram_preview_vehicle",{
      initial_properties={physical=false,pointable=false,collide_with_objects=false,static_save=false,
        visual="mesh",mesh="bl_streetcar.obj",textures={"bl_tram_palette.png"},
        shaded=true,backface_culling=true,visual_size={x=.4,y=.4,z=.4}},
    })
  end
  local bridge_styles=dofile(modpath.."/bridge_style_assets.lua")
  local bridges={}
  do
    local clear_span=dofile(modpath.."/bridge_clearance_render.lua")
    local rules=dofile(modpath.."/openttd/road_bridge.lua")(api.slope)
    local piece=dofile(modpath.."/bridge_piece_art.lua")(architecture,rules,Sim.xy)
    for style,prefix in pairs(bridge_styles.road) do
      local manifest=bridge_styles.pieces[style]
      local geometry=bridge_styles.mesh_stem("road",style)
      local parts={head_flat={},head_ramp={}}
      if not manifest then parts.span={};parts.pier={} end
      for part,list in pairs(parts) do
        local limit=(part=="span" or part=="pier") and 1 or 3
        for d=0,limit do
          local asset=prefix.."_"..part.."_"..d
          list[d]=architecture("stock_"..asset,geometry.."_"..part.."_"..d,prefix)
        end
      end
      if manifest then parts.piece=piece.mount(prefix,manifest,geometry) end
      parts.clear_span=clear_span(architecture,prefix,manifest~=nil)
      bridges[style]=parts
    end
  end
  local rail_spans=api.rail_spans and dofile(modpath.."/rail_span_render.lua")(
    api.rail_spans,visual.state,architecture,terrain_view,api.rail_bridge_wire_art,Sim.xy)
  local tunnel_portal={}
  for d=0,3 do
    local asset="road_tunnel_portal_"..d
    tunnel_portal[d]=architecture("stock_"..asset,asset,"road_tunnel_portal")
  end
  local freight_straight,freight_bay={},{}
  if api.freight_tools or api.stock_coal_scenery or api.stock_timber_scenery then
    for dir=0,1 do
      local id="road_freight_stop_straight_"..dir
      freight_straight[dir]=architecture(id,id,"road_freight_stop")
    end
    for dir=0,3 do
      local id="road_freight_stop_bay_"..dir
      freight_bay[dir]=architecture(id,id,"road_freight_stop")
    end
  end
  local mail_stop_straight,mail_stop_bay={},{}
  if S.road_mail then
    for n=0,1 do local asset="road_post_stop_straight_"..n
      mail_stop_straight[n]=architecture("stock_"..asset,asset,"road_post_stop")
    end
    for n=0,3 do local asset="road_post_stop_bay_"..n
      mail_stop_bay[n]=architecture("stock_"..asset,asset,"road_post_stop")
    end
  end
  local road_bay_pairs,bay_dir={}, {[8]=0,[4]=1,[2]=2,[1]=3}
  for d=0,3 do
    local asset="road_bus_bay_pair_"..d
    road_bay_pairs[d]=architecture(asset,asset,"road_bus_bay_pair")
  end
  local road_waypoint_mark={}
  for axis=0,1 do road_waypoint_mark[axis]=architecture("road_waypoint_"..axis,"road_waypoint_"..axis,"road_waypoint_atlas") end
  local shelter=architecture("stop_shelter","bus_shelter")
  local shelter_quarter=architecture("stop_shelter_quarter","bus_shelter_quarter")
  local shelter_corner=architecture("stop_shelter_corner","bus_shelter_corner")
  local depot={}
  for i=0,3 do depot[i+1]=architecture("depot_"..i,"road_depot_"..i) end
  local ground_mesh={}
  local pedestrian=dofile(modpath.."/pedestrian.lua")
  local slope_colliders={}
  local function slope_collision(mask)
    if not slope_colliders[mask] then
      slope_colliders[mask]=pedestrian.slope_box(api.slope.surface,mask)
    end
    return slope_colliders[mask]
  end
  local road_feet=terrain and dofile(modpath.."/bridge_pier_render.lua")(architecture,terrain_view,bridge_styles.static("road"))
  -- The slope owns the exposed surface, including any flat lower
  -- triangle of a single-corner ramp. A full cube beneath it would
  -- draw a second top at exactly the same depth.
  local slope_fill=terrain and reg("slope_fill_open",{png("grass_side")},{
    drawtype="mesh",mesh="bl_slope_fill_open.obj",paramtype="light",
    sunlight_propagates=true,pointable=false})
  if terrain then
    for mask=1,30 do
      if mask<15 or mask==23 or mask==27 or mask==29 or mask==30 then
        ground_mesh[mask]={}
        for variant=0,3 do
          ground_mesh[mask][variant]=reg("slope_"..mask.."_"..variant,{png("grass"..variant)},
            {drawtype="mesh",mesh="bl_land_"..mask..".obj",paramtype="light",
             sunlight_propagates=true,collision_box=slope_collision(mask),pointable=false})
        end
      end
    end
  end
  local road_slope_mesh,road_foundation_mesh={},{}
  local retaining=reg("road_retaining",{png("grass0"),png("hill0"),png("road_surface_retaining")})
  if terrain then
    for shape,mask in pairs({[3]=10,[6]=5,[9]=5,[12]=10}) do
      road_slope_mesh[shape]=reg("road_grade_"..shape,{png("road_surface_"..mask)},
        {drawtype="mesh",mesh="bl_land_"..shape..".obj",paramtype="light",
         sunlight_propagates=true,collision_box=slope_collision(shape),pointable=false})
      road_foundation_mesh[shape]=reg("road_grade_"..shape.."_foundation",
        {png("road_grade_foundation_"..mask)},
        {drawtype="mesh",mesh="bl_road_grade_foundation_"..shape..".obj",paramtype="light",
         sunlight_propagates=true,collision_box=slope_collision(shape),pointable=false})
    end
  end
  local function shelter_layout(id)
    local mask=R.mask(id,"road")
    local ns=mask%2+math.floor(mask/4)%2
    local ew=math.floor(mask/2)%2+math.floor(mask/8)%2
    if ns>0 and ew>0 then return "corner" end
    if ns>0 then return "quarter" end
    return "straight"
  end
  local rebuild_art={}
  for axis=0,1 do
    local asset="road_reconstruction_"..axis
    rebuild_art[axis]=architecture(asset,asset,"road_reconstruction_atlas")
  end
  local function road_surface(id)
    local t=S.tiles[id]
    local name=t and t.build
    if S.corner_grid and (name=="road" or name=="road_station" or name=="road_depot" or name=="stock_road_bridge" or name=="stock_road_tunnel") and Sim.road_surface then
      return Sim.road_surface(S,id)
    end
  end
  function R.road_reconstruction_node(t,id,x,y,z)
    if not t.roadworks or x%2~=0 or z%2~=0 then return end
    local slope,base=road_surface(id)
    if slope==nil and t.tram and R.tram_surface then
      local surface=R.tram_surface(id)
      if surface then slope,base=surface.grade,surface.base end
    end
    if slope==0 and y==base+2 then
      local bits=Sim.road_bits(S,id)
      if bits==0 and t.tram then bits=t.tram.tram_bits end
      return rebuild_art[bits==5 and 1 or 0]
    end
  end
  if api.tram_tools and terrain then
    local sampler=dofile(modpath.."/openttd/tram_grade_surface.lua")(
      dofile(modpath.."/openttd/road_slope.lua"),api.slope)
    function R.tram_surface(id)
      local t=S.tiles[id]
      if not t or not t.tram then return end
      local shape,base=terrain.tile(id)
      return sampler.for_tile(shape,base,t.tram,Sim.road_bits(S,id))
    end
  end
  function R.platform(st)
    local at=st and (st.bus_tile or (st.stop_type~="truck" and st.tile))
    local t=at and S.tiles[at]
    if not t or t.station~=st.id or Sim.road_stop_tile_kind(st,at,t)~="bus" or t.build~="road_station" then return end
    local tx,tz=Sim.xy(at)
    local x,z=tx*2+.5,tz*2+.5
    local _,base=road_surface(at)
    local y=(base or t.h)+.56
    if t.road_stop_pair then
      local d=bay_dir[Sim.road_bits(S,at)]
      if not d then return end
      local function rotate(a,b)
        for _=1,d do a,b=b,-a end
        return a,b
      end
      local dx,dz=rotate(-.035,.748)
      local ax,az=rotate(1,0)
      local bx,bz=rotate(0,1)
      return {x=x+dx,y=y-.005,z=z+dz,side={x=bx,z=bz},along={x=ax,z=az},
        width=.143,length=1.24,slot_ok=function(f) return math.abs(f-.099)>.081 end}
    end
    local layout=shelter_layout(at)
    -- Use the exposed curbside strip, not under the opaque roof. The
    -- strip stays inside the platform and outside either asphalt lane.
    if layout=="quarter" then
      return {x=x-.61+.185,y=y,z=z,side={x=1,z=0},along={x=0,z=1},width=.22,length=1.70}
    end
    if layout=="corner" then x=x+.65 end
    return {x=x,y=y,z=z+.61-.185,side={x=0,z=-1},along={x=1,z=0},width=.22,length=layout=="corner" and .646 or 1.70}
  end
  function R.host_state() return S end
  function R.host_terrain_top(id)
    if terrain then local _,_,level=terrain.tile(id);return level end
  end
  function R.host_tile(id)
    return id and S.tiles[id]
  end
  function R.host_record(registry,id)
    local i=S[registry]
    return i and id and i[id]
  end
  function R.host_deck(id)
    local level
    local function check(index,registry)
      local deck=R.host_record(registry,R.host_record(index,id))
      if deck and deck.deck then level=math.max(level or 0,deck.deck) end
    end
    check("bridge_above","stock_road_bridges")
    check("rail_bridge_above","stock_rail_spans")
    check("aqueduct_above","stock_aqueducts")
    return level
  end
  function R.host_signal(id)
    local d=S.stock_rail_dispatch
    return id and d and d.signals and d.signals.records[id]
  end
  function R.pick_terrain(pos,ray,limit)
    if terrain then return terrain.pick(pos,ray,R.uses_slope,limit,R.surface) end
  end
  function R.uses_slope(id)
    if not terrain then return false end
    local t=S.tiles[id]
    return t and not t.stock_void and (t.coastal_water or t.water_class=="river" or
      (not t.site and not t.house and not t.build and t.terrain~="water") or road_surface(id)~=nil or
      t.rail_depot_dir~=nil or t.tram~=nil)
  end
  function R.surface(id,x,z)
    local t=S.tiles[id]
    if t and t.rail_depot_dir~=nil and api.trackworks then
      local shape,base=terrain.tile(id)
      local _,level=api.trackworks.depot_surface(shape,base)
      if level then return level+.5 end
    end
    local slope,base=road_surface(id)
    if slope==nil and R.tram_surface then
      local track=R.tram_surface(id)
      if track then slope,base=track.grade,track.base end
    end
    if slope then
      local u,v=Sim.xy(id)
      return base+.5+api.slope.surface((x-2*u+.5)/2,(z-2*v+.5)/2,slope)
    end
    return terrain.sample(id,x,z)
  end
  local function depot_door(t,id)
    if t.depot_dir then return t.depot_dir end
    for d=1,4 do
      local j=Sim.adjacent(id,d)
      if j and S.tiles[j] and S.tiles[j].build~="road_depot" and Sim.mode_on(S,j,"road",t.owner) then return d end
    end
    return 1
  end
  local scenery,house,forest={},{},{}
  for _,k in ipairs({"town","mine","farm","mill","factory"}) do
    scenery[k]=architecture("scenery_"..k,"scenery_"..k,"scenery_palette")
  end
  local parcels={}
  for _,kind in ipairs({"market","shop","green"}) do
    parcels[kind]=architecture("town_"..kind,"town_"..kind,"scenery_palette",kind=="shop",
      kind=="shop" and {-.17,-.5,-.20,1.18,.65,1.10} or nil)
  end
  for v=0,3 do
    house[v]=architecture("scenery_house_"..v,"scenery_house_"..v,"scenery_palette",true,
      {-.15,-.5,.12,1.17,.48,1.22})
    forest[v]=architecture("scenery_tree_"..v,"scenery_tree_"..v,"scenery_palette")
  end
  local stock_house,stock_build={},{}
  local stock_styles=dofile(modpath.."/stock_town_art.lua")
  for id,style in pairs(stock_styles) do
    if type(style)=="table" and style.asset then
      local name=("town_stock_%02x"):format(id)
      if style.width then
        local parts={}
        stock_house[id]=parts
        local size=style.width..style.depth
        stock_build[size]=stock_build[size] or {}
        for x=0,style.width-1 do
          for z=0,style.depth-1 do
            local part=2*x+z
            local asset=name.."_"..part
            parts[part]=architecture(asset,asset,"scenery_palette",false,style.solid)
            for progress=0,2 do
              local stages=stock_build[size]
              stages[progress]=stages[progress] or {}
              if not stages[progress][part] then
                local stage="town_stock_stage_"..size.."_"..progress.."_"..part
                stages[progress][part]=architecture(stage,stage,"scenery_palette")
              end
            end
          end
        end
      elseif style.looks then
        local variants={}
        stock_house[id]=variants
        for _,look in ipairs(style.looks) do
          if not variants[look] then
            local asset=stock_styles.asset_name(id,look)
            variants[look]=architecture(asset,asset,"scenery_palette",true,style.solid)
          end
        end
      else
        stock_house[id]=architecture(name,name,"scenery_palette",true,style.solid)
      end
    end
  end
  local stock_scenery={forest={},quarters={[0]=0,2,3,1}}
  if api.ship_tools then stock_scenery.buoy=architecture("ship_buoy","ship_buoy","ship_buoy_palette") end
  stock_scenery.waypoint={}
  for axis=0,1 do
    local name="rail_waypoint_"..axis
    stock_scenery.waypoint[axis]=architecture(name,name,"rail_waypoint_palette")
  end
  if api.electric_art then
    stock_scenery.catenary={}
    for _,mask in ipairs({1,2,4,8,16,32}) do
      local family={}
      for pole=0,1 do
        local name=("rail_catenary_%d_%d"):format(mask,pole)
        family[pole]=architecture(name,name,"rail_catenary_atlas")
      end
      stock_scenery.catenary[mask]=family
    end
  end
  if S.stock_generated_profile and S.stock_generated_profile.forest then
    for v=0,3 do
      stock_scenery.forest[v]={}
      for elevation=0,4 do
        local name=("stock_forest_%d_%d"):format(v,elevation)
        stock_scenery.forest[v][elevation]=architecture(name,name,"scenery_palette")
      end
    end
  end
  if S.stock_generated_profile and S.stock_generated_profile.object_rng then
    stock_scenery.lighthouse=architecture("stock_lighthouse","stock_lighthouse","stock_landmarks_atlas")
    stock_scenery.transmitter=architecture("stock_transmitter","stock_transmitter","stock_landmarks_atlas")
  end
  local lighthouse_beams=stock_scenery.lighthouse and dofile(modpath.."/lighthouse_beam_view.lua")(core,Sim)
  function R.step_lighthouse_beams(dt,viewers)
    if not lighthouse_beams then return end
    if not viewers then
      viewers={}
      for _,player in ipairs(core.get_connected_players()) do
        local at=player:get_pos()
        if at then viewers[#viewers+1]=at end
      end
    end
    lighthouse_beams.step(dt,S,viewers)
  end
  local river_view,river_revision,river_topology,river_directions
  if S.stock_generated_profile and S.stock_generated_profile.river_stats then
    river_view=dofile(modpath.."/river_presentation.lua")(Sim)
    stock_scenery.river={}
    local function register_surface(mask)
      local prefix="stock_river_"..(mask==0 and "flat" or mask)
      local mesh=mask~=0 and "bl_land_"..mask..".obj" or nil
      local family={}
      -- Native +Y world-aligned texture V advances toward +Z.
      local files={south="bl_water_river_anim.png",north="bl_water_river_north_anim.png",
        east="bl_water_river_east_anim.png",west="bl_water_river_west_anim.png"}
      for _,dir in ipairs({"north","south","east","west"}) do
        local top=water_tile(files[dir],2.4,not mesh and 2 or nil)
        family[dir]=reg(prefix..(dir=="north" and "" or "_"..dir),
          mesh and {top} or {top,water_side,water_side},water_definition(mesh))
      end
      stock_scenery.river[mask]=family
    end
    register_surface(0)
    for mask in pairs(ground_mesh) do register_surface(mask) end
  end
  local function update_river_directions(changed)
    if not river_view or projected then return end
    local revision=S.corner_grid.revision
    if river_directions and river_revision==revision and river_topology==S.topology then return end
    local old=river_directions
    river_revision,river_topology=revision,S.topology
    river_directions=river_view.routes(S)
    if old and changed then
      for id,dir in pairs(old) do if river_directions[id]~=dir then changed[id]=true end end
      for id,dir in pairs(river_directions) do if old[id]~=dir then changed[id]=true end end
    end
  end
  local function river_direction(id)
    if projected then return S.river_directions[id] or "north" end
    update_river_directions()
    return river_directions[id] or "north"
  end
  local house_build,stock_sites={},{}
  local stock_construction=dofile(modpath.."/stock_town_construction_art.lua")(
    dofile(modpath.."/openttd/stock_town_draw_rows.lua"),stock_styles)
  if api.town_growth then
    for stage=0,2 do
      local name="house_build_stage_"..stage
      house_build[stage]=architecture(name,name,"house_build_atlas",true)
    end
    for name,appearance in pairs(stock_construction.files()) do
      local shape=appearance.shell and stock_styles[appearance.id].solid or nil
      stock_sites[name]=architecture(name,name,"scenery_palette",true,shape)
    end
  end
  local basement=reg("bedrock",{rock_side})
  core.register_alias("mapgen_stone",basement)
  core.register_alias("mapgen_water_source",gnames.water[0])
  core.register_alias("mapgen_river_water_source",gnames.water[0])
  local frontage=dofile(modpath.."/house_frontage.lua")
  local fountains=dofile(modpath.."/town_fountain_view.lua")(core,Sim,frontage)
  local smoke=S.stock_generated_profile and dofile(modpath.."/industry_smoke_view.lua")(core,Sim,terrain)
  function R.step_ambient_particles(dt,viewers)
    if not viewers then
      viewers={}
      for _,player in ipairs(core.get_connected_players()) do
        local pos=player:get_pos()
        if pos then pos.name=player:get_player_name();viewers[#viewers+1]=pos end
      end
    end
    fountains.step(dt,S,viewers)
    if smoke then smoke.step(dt,S,viewers) end
  end
  function R.leave_ambient_particles(name)
    fountains.leave(name)
    if smoke then smoke.leave(name) end
  end
  local function solid(t,id,x,z)
    if t.site or t.house then
      local record=t.source_house
      -- Multipart buildings are split at real tile boundaries for
      -- independently loaded worker sectors; their stock footprint is fixed.
      local style=record and record.asset_root and stock_styles[record.asset_root]
      if style then
        if x%2==0 and z%2==0 then
          local part=record.asset_part
          local node=record.completed and stock_house[record.asset_root][part]
            or stock_build[style.width..style.depth][record.stage][part]
          return node,t.h+1,0
        end
        return gnames[t.terrain][t.variant],t.h
      end
      local stage,old_orientation
      local building=record and stock_house[record.id]
      if record then
        local tx,tz=Sim.xy(id)
        if type(building)=="table" then building=building[stock_styles.look(record.id,tx,tz)] end
        if api.town_growth and record.town_growth and not record.completed then
          local key=stock_construction.selection(record.id,tx,tz,record.stage)
          if key and key~="complete" then
            stage=assert(stock_sites[key],key)
          elseif not key then
            stage=house_build[record.stage]
            old_orientation=stage
          end
        end
      end
      local parcel=record and record.render_parcel or t.parcel
      local dx,dz,facedir=frontage.placement(Sim,S,id,t,old_orientation,parcel)
      if x%2==dx and z%2==dz then
        local variant=record and record.render_variant or t.variant
        return stage or building or
          (t.site and scenery[S.sites[t.site].kind] or parcels[parcel] or house[variant]),t.h+1,facedir
      end
      return gnames[t.terrain][t.variant],t.h
    end
    if t.build then
      if props[t.build] then return props[t.build],1 end
      local mode=Sim.tools[t.build] and Sim.tools[t.build].mode or t.rail_span_id and "rail"
      if mode=="road" or mode=="rail" then
        local suffix=t.build:find("_bridge") and "bridge" or t.build:find("_tunnel") and "tunnel" or "plain"
        return infrastructure[mode.."_"..R.mask(id,mode).."_"..suffix][x%2+2*(1-z%2)],t.h
      end
    end
    local planted=t.wood==true and ((x%2+2*(z%2))==t.variant or (id%7==0 and x%2==z%2))
    return planted and forest[t.variant] or gnames[t.terrain][t.variant],planted and t.h+1 or t.h
  end
  local function content(name)
    if ids[name]==nil then ids[name]=core.get_content_id(name) end
    return ids[name]
  end
  local top_bound=4
  if S.corner_grid then
    for _,level in ipairs(S.corner_grid.levels) do top_bound=math.max(top_bound,level+3) end
  end
  for _,span in pairs(S.stock_road_bridges or {}) do top_bound=math.max(top_bound,span.deck+3) end
  if rail_spans then top_bound=math.max(top_bound,rail_spans.extent()+3) end
  function R.raise_bound(height) top_bound=math.max(top_bound,height+3) end
  function R.max_target_level() return top_bound end
  local generated_ground={}
  if api.generated_world then
    for class,name in ipairs({"clear_rough","clear_rocks"}) do
      local texture=png(name)
      local family={flat=reg("stock_clear_ground_"..class,{texture,png("grass2"),rock_side})}
      for mask in pairs(ground_mesh) do
        family[mask]=reg("stock_clear_ground_"..class.."_slope_"..mask,{texture},
          {drawtype="mesh",mesh="bl_land_"..mask..".obj",
            paramtype="light",sunlight_propagates=true,collision_box=slope_collision(mask),pointable=false})
      end
      generated_ground[class]=family
    end
  end
  local shore={}
  local show_shore=S.stock_coastal_flood
  if terrain and not show_shore then
    for _,tile in ipairs(S.tiles) do if tile.coastal_water then show_shore=true;break end end
  end
  if terrain and show_shore then
    for _,mask in ipairs{1,2,3,4,6,7,8,9,11,12,13,14,23,27,29,30} do
      local asset="coastal_bank_"..mask
      shore[mask]={}
      for variant=0,3 do
        shore[mask][variant]=architecture("stock_shore_"..mask.."_"..variant,asset,"original_coast_"..variant)
      end
    end
  end
  local function source_road_node(t,id,x,y,z,grade,base,foundation)
    if grade==0 then
      if y==base then
        local mask=R.mask(id,"road")
        local quarter=x%2+2*(1-z%2)
        if t.road_town then
          return (foundation~="none" and town_foundation_flat or town_streets)[mask][quarter]
        end
        if foundation~="none" then return road_foundation_flat[mask][quarter] end
        return infrastructure["road_"..mask.."_plain"][quarter]
      end
      if y<base then return foundation~="none" and retaining or gnames.grass[t.variant] end
      return "air"
    elseif road_slope_mesh[grade] then
      if y<=base then return foundation~="none" and retaining or gnames.grass[t.variant] end
      if y==base+1 and x%2==0 and z%2==0 then
        return (foundation~="none" and road_foundation_mesh or road_slope_mesh)[grade]
      end
      return "air"
    end
  end
  if api.tram_tools and terrain then
    function R.tram_node(t,id,x,y,z,grade)
      local p=t.tram
      local track=R.tram_surface and R.tram_surface(id)
      local _,ground=terrain.tile(id)
      local level=track and track.base or ground
      local slope=track and track.grade or 0
      if x%2==0 and z%2==0 then
        if slope~=0 then
          local marks=api.oneway and (t.road_disallowed or t.disallowed or 0)~=0
          if marks and y==level+3 then return tramway.signed[slope] end
          if not marks and y==level+2 then return tramway.grade[slope] end
        end
        if slope==0 and y==level+1 then
          if p.kind=="depot" then return tram_depots[p.dir] end
          if p.kind=="drive_stop" then return tram_stops[p.dir] end
          return tramway[p.tram_bits]
        end
      end
      if not grade then
        if slope~=0 then return source_road_node(t,id,x,y,z,slope,level,track.foundation) end
        if y<level then return track and track.foundation~="none" and retaining or gnames.grass[t.variant] end
        if y==level then
          local a=x%2+2*(1-z%2)
          if track and track.foundation~="none" then return road_foundation_flat[p.tram_bits][a] end
          return infrastructure["road_"..p.tram_bits.."_plain"][a]
        end
        return "air"
      end
    end
  end
  local function coastal_node(t,id,x,y,z)
    if t.stock_void then return y==0 and ocean(x,z) or "air" end
    if t.ship and t.ship.water_ground and t.ship.water_class=="sea" then return ocean(x,z) end
    if t.coastal_water and terrain and next(shore) then
      local mask,base=terrain.tile(id)
      if y==base then return ocean(x,z) end
      if y<base then return gnames.grass[t.variant] end
      if mask~=0 and y==base+1 and x%2==0 and z%2==0 then return assert(shore[mask][t.variant]) end
      return "air"
    end
    if t.terrain=="water" and not t.coastal_water and not t.build and not t.ship and
        (not t.water_class or t.water_class=="sea") then return ocean(x,z) end
  end
  local function tile_node_base(id,x,y,z)
    local t=S.tiles[id]
    if y<-1 or y>top_bound then return "air" end
    if t.stock_void then
      -- Close the visual seam between the passive horizon and in-map sea.
      -- The record is still void: topology, targeting and build rules must
      -- not treat this decorative water node as a navigable tile.
      return coastal_node(t,id,x,y,z)
    end
    if y==-1 then return basement end
    if t.stock_landmark then
      if y<=t.h then return gnames[t.terrain][t.variant] end
      if y==t.h+1 and x%2==0 and z%2==0 then return assert(stock_scenery[t.stock_landmark.kind]) end
      return "air"
    end
    if rail_spans then
      local span_node=rail_spans.node(id,x,y,z,gnames.grass[t.variant],retaining)
      if span_node then return span_node end
    end
    if api.crossings and t.level_crossing then
      local c=t.level_crossing
      local tram=R.tram_crossing_node and R.tram_crossing_node(c,x,y,z)
      if tram then return tram end
      if y<=c.top then return c.foundation~="none" and retaining or gnames[t.terrain][t.variant] end
      if y==c.top+1 and x%2==0 and z%2==0 then
        local gate=(c.barred or c.phase=="unobserved" or c.phase=="mixed_occupancy") and "closed" or "open"
        return crossing_mesh[c.rail_axis][gate]
      end
      return "air"
    end
    if t.roadworks then
      local works=R.road_reconstruction_node(t,id,x,y,z)
      if works then return works end
    end
    if api.oneway and (t.road_disallowed or t.disallowed) and x%2==0 and z%2==0 then
      local mark=one_way_node(id,y)
      if mark then return mark end
    end
    local n,top,facedir=solid(t,id,x,z)
    local bridge_id=t.road_bridge_id or (S.bridge_above and S.bridge_above[id])
    local span=bridge_id and S.stock_road_bridges[bridge_id]
    if span then
      local wood_bridge=bridges[span.bridge_type or 0]
      local head=span.start==id and span.head or span["end"]==id and span.tail
      local native_anchor=x%2==0 and z%2==0
      if span.tramtype==1 and R.tram_span_node then
        local overhead=R.tram_span_node("bridge",span.axis,head,span.deck,x,y,z)
        if overhead then return overhead end
      end
      local clear=not head and wood_bridge.clear_span.under(t)
      if y==span.deck and native_anchor then
        if head then return wood_bridge[head.flat_ramp and "head_flat" or "head_ramp"][head.inside_direction] end
        if wood_bridge.piece then
          local deck,under=wood_bridge.piece.models(span,id)
          return clear and under or deck
        end
        return (clear and wood_bridge.clear_span or wood_bridge.span)[span.axis]
      end
      if not head and not clear and native_anchor and y<span.deck then
        local _,_,land_top=terrain.tile(id)
        if y>land_top then
          local pier
          if wood_bridge.piece then local _,_,node=wood_bridge.piece.models(span,id);pier=node
          else pier=wood_bridge.pier[span.axis] end
          if pier then return pier end
        end
      end
      if head then
        if y<=head.base then
          return head.foundation~="none" and retaining or gnames.grass[t.variant]
        end
        return "air"
      end
    end
    if t.road_tunnel_id then
      local tunnel=S.stock_road_tunnels[t.road_tunnel_id]
      local head=tunnel.start==id and tunnel.head or tunnel.tail
      if tunnel.tramtype==1 and R.tram_span_node then
        local overhead=R.tram_span_node("tunnel",head.inside_direction%2,head,tunnel.base,x,y,z)
        if overhead then return overhead end
      end
      if y<=tunnel.base then return gnames.grass[t.variant] end
      if y==tunnel.base+1 and x%2==0 and z%2==0 then return tunnel_portal[head.inside_direction] end
      return "air"
    end
    if t.stock_industry and (api.stock_coal_scenery or api.stock_timber_scenery or api.farm_world or api.oil_world or api.heavy_world) then
      local b=t.stock_industry
      local _,level=terrain.tile(id)
      local registry=b.chain=="farm" and S.stock_farm_industries or
        b.chain=="timber" and S.stock_timber_industries or
        b.chain=="oil" and S.stock_oil_industries or b.chain=="heavy" and S.stock_heavy_industries or
        b.chain=="bank" and S.stock_bank_industries or S.stock_coal_industries
      local industry=registry and registry[b.id]
      if industry and not industry.removed and y==level+1 and x%2==0 and z%2==0 then
        local name=("%s_%d_%d"):format(b.style,b.x,b.z)
        if b.chain=="farm" then return assert(farm_buildings[name]) end
        if b.chain=="oil" then return assert(oil_buildings[name]) end
        if b.chain=="heavy" or b.chain=="bank" then return oil_buildings[name] or "air" end
        if b.chain=="timber" then
          if b.kind=="forest" then
            for _,cell in ipairs(industry.tiles) do
              if cell.x==industry.x+b.x and cell.z==industry.z+b.z and cell.gfx==17 then return timber_harvested end
            end
          end
          return timber_buildings[name] or "air"
        end
        return coal_buildings[name] or "air"
      end
      if b.chain=="oil" and b.kind=="rig" then
        if y~=level then return "air" end
        local class=t.water_class or "sea"
        if class=="sea" then return coastal_node(t,id,x,y,z) or gnames.water[t.variant or 3] end
        if class=="river" and stock_scenery.river then return stock_scenery.river[0][river_direction(id)] end
        return gnames.water[t.variant or 3]
      end
      return y<=level and gnames.grass[t.variant] or "air"
    end
    if api.farm_world then
      local field=api.farm_world.field(S,id)
      if field then
        if field.slope~=0 and y==field.base then return slope_fill end
        if y<=field.base then return gnames.grass[t.variant] end
        if y==field.base+1 and x%2==0 and z%2==0 then return farm_fields[field.slope][field.variant] end
        return "air"
      end
    end
    if api.airport_tools and t.airfield then
      local field=t.airfield
      local _,level=terrain.tile(id)
      local nodes=airfield_nodes[field.layout or "country"]
      local row=nodes and nodes[field.z]
      if row and y==level+1 and x%2==0 and z%2==0 then return row[field.x] or "air" end
      return y<=level and gnames.grass[t.variant] or "air"
    end
    if api.ship_tools and S.aqueduct_above and S.aqueduct_above[id] then
      local span=S.stock_aqueducts[S.aqueduct_above[id]]
      if x%2==0 and z%2==0 then
        if y==span.deck then return aqueduct_span[span.axis] end
        if y<span.deck and not (t.build or t.ship or t.tram or t.wood or t.house or t.site or t.terrain=="water") then
          local _,_,top=terrain.tile(id)
          if y>top then return y==span.deck-1 and aqueduct_pier_head[span.axis] or aqueduct_pier[span.axis] end
        end
      end
    end
    if api.ship_tools and t.ship then
      local sp=t.ship
      local _,level=terrain.tile(id)
      if sp.kind=="buoy" then
        if y==level+1 and x%2==0 and z%2==0 then return stock_scenery.buoy end
        if y==level then
          if sp.water_class=="river" and stock_scenery.river then
            return stock_scenery.river[0][river_direction(id)]
          end
          return coastal_node(t,id,x,y,z) or gnames.water[t.variant or 3]
        end
        return y<level and gnames.grass[t.variant] or "air"
      end
      if y==level+1 and x%2==0 and z%2==0 then
        if sp.kind=="lock" then return ship_locks[sp.part][sp.dir] end
        if sp.kind=="aqueduct" then return aqueduct_head[sp.dir] end
        if sp.kind=="ship_depot" then return ship_depots[sp.axis][sp.part] end
        if sp.kind=="dock" then return sp.water_part and ship_piers[sp.dir] or ship_docks[sp.dir] end
      end
      if y>level or sp.kind=="lock" and y==level then return "air" end
      if y==level then
        local surface=coastal_node(t,id,x,y,z)
        if surface then return surface end
      end
      return (sp.kind=="ship_depot" or sp.water_part) and gnames.water[t.variant] or gnames.grass[t.variant]
    end
    local trees=type(t.wood)=="table" and not t.build and not t.house and not t.site
      and not t.ship and not t.tram and not t.airfield and t.wood
    if trees and terrain and stock_scenery.forest[0] then
      local mask,base=terrain.tile(id)
      if y==base+2 then
        local q=x%2+2*(z%2)
        local stem=stock_scenery.quarters[(q-t.variant)%4]
        if stem<trees.count then
          local u,v=(x%2+.5)/2,(z%2+.5)/2
          local lift=math.floor(api.slope.surface(u,v,mask)*2+.00001)
          return stock_scenery.forest[trees.type%4][math.max(0,math.min(4,lift))]
        end
      end
    end
    if t.coastal_water then
      local node=coastal_node(t,id,x,y,z)
      if node then return node end
    end
    if api.ship_tools and t.stock_canal then
      local _,level=terrain.tile(id)
      if y==level then return gnames.water[3] end
      if y<level then return gnames.grass[t.variant] end
      return "air"
    end
    if t.water_class=="river" and stock_scenery.river then
      local mask,base=terrain.tile(id)
      if mask==0 and y==base then return stock_scenery.river[0][river_direction(id)] end
      if mask~=0 and y==base then return slope_fill end
      if y<=base then return gnames.grass[t.variant] end
      if mask~=0 and y==base+1 and x%2==0 and z%2==0 then return assert(stock_scenery.river[mask])[river_direction(id)] end
      return "air"
    end
    if t.rail_tracks then
      local shape,base=0,t.h
      if terrain then shape,base=terrain.tile(id) end
      local grade,level,foundation,profile
      if t.rail_depot_dir~=nil then grade,level,foundation=api.trackworks.depot_surface(shape,base)
      else grade,level,foundation,profile=api.trackworks.surface(shape,base,t.rail_tracks) end
      if grade then
        if t.rail_waypoint_id and grade==0 and y==level+1 and x%2==1 and z%2==1 then
          return stock_scenery.waypoint[t.rail_tracks==1 and 0 or 1]
        end
        if grade==0 and y==level+2 and x%2==0 and z%2==0 and t.rail_type==1
            and not t.rail_depot_dir and stock_scenery.catenary then
          local art=api.electric_art.overlay(t.rail_tracks,0,t.rail_station_id and "platform" or "plain",x/2,z/2)
          if art then
            local d=S.stock_rail_dispatch
            local signal=d and d.signals and d.signals.records[id]
            return stock_scenery.catenary[t.rail_tracks][art.pole and not signal and 1 or 0]
          end
        end
        if y<=level then return foundation~="none" and retaining or gnames[t.terrain][t.variant] end
        if x%2==0 and z%2==0 then
          if grade==0 and y==level+1 then
            if t.rail_station_id then
              local st=S.stock_rail_stations and S.stock_rail_stations[t.rail_station_id]
              local art=st and st.coal_role and coal_rail_stage[st.coal_role]
              if art and (st.coal_stage_tile or st.tiles[#st.tiles])==id then
                return art[t.rail_station_axis][st.coal_stage_mirror~=false and 2 or 1]
              end
              local guideway=stock_rail.guideway[t.rail_type]
              return guideway and guideway.station[t.rail_station_axis] or rail_platform[t.rail_station_axis]
            end
            if t.rail_depot_dir then
              local guideway=stock_rail.guideway[t.rail_type]
              return guideway and guideway.depot[t.rail_depot_dir] or rail_depot[t.rail_depot_dir]
            end
            return stock_rail.visual(id,t.rail_tracks,t.rail_type)
          end
          if grade>0 then
            if y==level+1 then return ground_mesh[profile][t.variant] end
            if y==level+2 then return stock_rail.grade_art(grade,t.rail_type) end
          end
        end
        return "air"
      end
    end
    local grade,base,foundation=road_surface(id)
    if t.tram and R.tram_node then
      local asset=R.tram_node(t,id,x,y,z,grade)
      if asset then return asset end
    end
    if y==(base or 0)+1 and x%2==0 and z%2==0 then
      if t.road_waypoint_id then
        return road_waypoint_mark[t.road_bits==10 and 0 or 1]
      elseif t.build=="road_station" then
        local st=S.stations[t.station]
        if t.road_stop_pair then return assert(road_bay_pairs[bay_dir[Sim.road_bits(S,id)]]) end
        local role=Sim.road_stop_tile_kind(st,id,t)
        if role=="truck" and (st.coal_art or st.freight_art) and freight_straight[0] then
          local bits=Sim.road_bits(S,id)
          local bay=({[8]=0,[4]=1,[2]=2,[1]=3})[bits]
          return (bits==5 and freight_straight[1]) or (bits==10 and freight_straight[0])
            or (bay and freight_bay[bay]) or freight_straight[0]
        end
        if S.road_mail and role=="truck" then
          local bits=Sim.road_bits(S,id)
          local bay=({[8]=0,[4]=1,[2]=2,[1]=3})[bits]
          return (bits==5 and mail_stop_straight[1]) or (bits==10 and mail_stop_straight[0])
            or (bay and mail_stop_bay[bay]) or mail_stop_straight[0]
        end
        local layout=shelter_layout(id)
        return layout=="corner" and shelter_corner or layout=="quarter" and shelter_quarter or shelter
      elseif t.build=="road_depot" then
        return depot[depot_door(t,id)]
      end
    end
    local surface_node=grade and source_road_node(t,id,x,y,z,grade,base,foundation)
    if surface_node then return surface_node end
    if R.uses_slope(id) then
      local mask,base=terrain.tile(id)
      local material=generated_ground[trees and trees.ground or not t.wood and t.stock_clear_ground]
      if material and y==base and mask==0 then return material.flat end
      if material and mask~=0 and y==base+1 and x%2==0 and z%2==0 then return material[mask] end
      if mask~=0 then
        if y==base then return slope_fill end
        if y<base then return gnames.grass[t.variant] end
        if y==base+1 and x%2==0 and z%2==0 then return ground_mesh[mask][t.variant] end
        return "air"
      end
      if t.wood~=true or base~=t.h then
        return y<=base and gnames.grass[t.variant] or "air"
      end
    end
    if t.signal and y==top+1 then return props[t.closed and "closed" or "signal"] end
    if y==top then return coastal_node(t,id,x,y,z) or n,facedir end
    if y<top then return gnames[t.terrain][t.variant] end
    return "air"
  end
  local tunnel_bore=terrain and Bore.mount(reg,bore_ground_defs)
  local function tile_node(id,x,y,z)
    local node,param2=tile_node_base(id,x,y,z)
    local cut=tunnel_bore and tunnel_bore(S,id,x,y,z,node)
    if cut then return cut,param2 end
    -- Only an unused cell in a middle tile can host the footings. Preserve
    -- the already-rendered slope/water/foundation in every occupied cell.
    if node=="air" and y>=0 and x%2==1 and z%2==1 then
      local key=S.bridge_above and S.bridge_above[id]
      local span=key and S.stock_road_bridges[key]
      if span and road_feet then
        local style=bridges[span.bridge_type or 0]
        if style.clear_span.under(S.tiles[id]) then return node,param2 end
        local piece
        if style.piece then local _,_,_,feet=style.piece.models(span,id);piece=feet end
        return road_feet(id,x,y,z,span,span.bridge_type or 0,S.tiles[id].terrain=="water",piece) or node
      end
      if rail_spans then return rail_spans.foot(id,x,y,z) or node end
    end
    return node,param2
  end
  local backdrop=api.road_first and 136 or 0
  local function within_world(minp,maxp)
    return not (maxp.y < -1 or minp.y > top_bound or maxp.x < 2-backdrop
      or minp.x > Sim.W*2+1+backdrop or maxp.z < 2-backdrop or minp.z > Sim.H*2+1+backdrop)
  end
  local function paint_region(vm,lo,hi,minp,maxp,mapgen)
    local xmax,zmax=Sim.W*2+1,Sim.H*2+1
    local area=VoxelArea:new({MinEdge=lo,MaxEdge=hi})
    local d=vm:get_data()
    local param2=vm:get_param2_data()
    local low,high=math.max(minp.y,-1),math.min(maxp.y,top_bound)
    local tops,air=S.paint_tops,content("air")
    local changed,changed_param2=false,false
    local function put(i,node,facedir)
      if d[i]~=node then d[i]=node;changed=true end
      if param2[i]~=facedir then param2[i]=facedir;changed_param2=true end
    end
    for z=math.max(minp.z,2-backdrop),math.min(maxp.z,zmax+backdrop) do
      for x=math.max(minp.x,2-backdrop),math.min(maxp.x,xmax+backdrop) do
        if x>=2 and x<=xmax and z>=2 and z<=zmax then
          local id=Sim.id(math.floor(x/2),math.floor(z/2))
          if S.tiles[id] then
            local roof=tops and math.min(high,tops[id] or high) or high
            local index=area:index(x,low,z)
            local stride=area.ystride
            for y=low,roof do
              local node,facedir=tile_node(id,x,y,z)
              put(index,content(node),facedir or 0)
              index=index+stride
            end
            -- Still erase obsolete upper nodes when terrain or an
            -- elevated bridge is lowered. Only skip the scene lookup.
            for _=math.max(low,roof+1),high do
              put(index,air,0)
              index=index+stride
            end
          end
        elseif minp.y<=0 and maxp.y>=0 then
          -- The water backdrop is only scenery: no tile, no route, no target.
          local i=area:index(x,0,z)
          local sea=content(ocean(x,z))
          if d[i]~=sea then put(i,sea,0) end
        end
      end
    end
    if changed then vm:set_data(d) end
    if changed_param2 then vm:set_param2_data(param2) end
    if mapgen then vm:calc_lighting() end
    if mapgen or changed or changed_param2 then vm:write_to_map() end
  end
  core.register_on_generated(function(minp,maxp)
    if not within_world(minp,maxp) then return end
    local vm,lo,hi=core.get_mapgen_object("voxelmanip")
    paint_region(vm,lo,hi,minp,maxp,true)
  end)
  -- A local world was already open while its creation formspec was shown.
  -- Those singlenode chunks can be marked generated but contain only air,
  -- so their on_generated hooks will not run on the next startup.
  -- Explicitly paint authoritative campaign terrain into the existing
  -- chunks as well as the newly emerged ones, before enabling the camera.
  local function place_region(low,high,done,notify)
    local failed,total,reported=false,nil,-1
    local function update(f,stage)
      if notify then notify(f,stage) end
    end
    core.emerge_area(low,high,function(_,action,remaining)
      if action==core.EMERGE_CANCELLED or action==core.EMERGE_ERRORED then failed=true end
      total=total or remaining+1
      local percent=math.floor(35*(total-remaining)/total)
      if percent>reported then
        reported=percent
        core.after(0,update,percent/100,"Loading the starting area")
      end
      if remaining~=0 then return end
      if failed then core.after(0,done,false,"Luanti could not emerge part of the starting area.");return end
      local x,z=low.x,low.z
      local batches=math.ceil((high.x-low.x+1)/64)*math.ceil((high.z-low.z+1)/64)
      local done_batches=0
      local function batch()
        local a={x=x,y=low.y,z=z}
        local b={x=math.min(x+63,high.x),y=high.y,z=math.min(z+63,high.z)}
        local ok,why=pcall(function()
          local vm=core.get_voxel_manip(a,b)
          local lo,hi=vm:get_emerged_area()
          paint_region(vm,lo,hi,a,b,false)
        end)
        if not ok then done(false,why);return end
        done_batches=done_batches+1
        update(.35+.65*done_batches/batches,"Placing terrain and buildings")
        x=x+64
        if x>high.x then x=low.x;z=z+64 end
        if z>high.z then done(true) else core.after(0,batch) end
      end
      core.after(0,batch)
    end)
  end
  -- Draw exactly the same stock nodes from a sparse worker projection.
  -- Loading order stays asynchronous; unhydrated cells are never painted.
  function R.use_worker_projection(projection)
    assert(api.terrain,"worker projection requires canonical slopes")
    visual.accept(projection)
    S=visual.state
    projected=true
    terrain=dofile(modpath.."/terrain_view.lua")(Sim,dofile(modpath.."/openttd/terrain.lua"),nil,projection)
    if api.farm_view then api.farm_view.use_worker_projection(S) end
    for _,receipt in ipairs(projection.windows()) do
      local w=receipt.value
      for _,t in ipairs(w.tiles) do R.raise_bound(t.top) end
      for _,name in ipairs({"stock_road_bridges","stock_rail_spans","stock_aqueducts"}) do
        for _,span in pairs(w.registries and w.registries[name] or {}) do
          if span.deck then R.raise_bound(span.deck) end
        end
      end
    end
  end
  function R.place_projected(x,z,w,h,done)
    assert(projected and w>=1 and w<=32 and h>=1 and h<=32)
    return place_region({x=2*x,y=-1,z=2*z},
      {x=2*(x+w-1)+1,y=top_bound,z=2*(z+h-1)+1},done)
  end
  function R.place_world(done,notify)
    local low={x=2-backdrop,y=-1,z=2-backdrop}
    local high={x=Sim.W*2+1+backdrop,y=top_bound,z=Sim.H*2+1+backdrop}
    if not api.generated_world or Sim.W*Sim.H<=128*128 then
      return place_region(low,high,done,notify)
    end
    -- Repair old empty singlenode blocks around the world-setup camera.
    -- Full campaign startup is independent of map area in native nodes;
    -- the normal on_generated hook paints unexplored sectors on demand.
    local distance=tonumber(core.settings:get("max_block_generate_distance")) or 8
    local radius=16*(math.max(1,math.floor(distance))+5)
    local a={x=math.max(low.x,-radius),y=low.y,z=math.max(low.z,-radius)}
    local b={x=math.min(high.x,radius),y=high.y,z=math.min(high.z,radius)}
    local function fraction(from,to)
      return notify and function(f,stage) notify(from+(to-from)*f,stage) end
    end
    place_region(a,b,function(ok,why)
      if not ok then done(false,why);return end
      local site=S.sites[1]
      if not site then done(true);return end
      local x,z=Sim.xy(site.tile)
      local u,v=2*x,2*z
      local size=48
      local c={x=math.max(low.x,u-size),y=low.y,z=math.max(low.z,v-size)}
      local d={x=math.min(high.x,u+size),y=high.y,z=math.min(high.z,v+size)}
      if c.x>=a.x and c.z>=a.z and d.x<=b.x and d.z<=b.z then done(true)
      else place_region(c,d,done,fraction(.8,1)) end
    end,fraction(0,.8))
  end
  local function update_tile(id)
    if not S.tiles[id] then return end
    local x,z=Sim.xy(id)
    for dz=0,1 do for dx=0,1 do for y=-1,top_bound do
      local p={x=x*2+dx,y=y,z=z*2+dz}
      local old=core.get_node_or_nil(p)
      if old and old.name~="ignore" then
        local node,facedir=tile_node(id,p.x,y,p.z)
        local param2=facedir or 0
        if old.name~=node or old.param2~=param2 then
          core.swap_node(p,{name=node,param2=param2})
        end
      end
    end end end
  end
  core.register_lbm({
    label="Refresh survey from dispatcher state",name="luanttd_core:refresh_survey",
    nodenames={basement},run_at_every_load=true,
    action=function(p)
      if p.y~=-1 or p.x%2~=0 or p.z%2~=0 then return end
      local id=Sim.id(p.x/2,p.z/2)
      if id then update_tile(id) end
    end,
  })
  -- Upgrade the derived sea appearance in previously painted mapblocks.
  -- The authoritative campaign records and all canal/river nodes stay put.
  core.register_lbm({
    label="Refresh the sea surface",name="luanttd_core:refresh_ocean_top",
    nodenames={gnames.water[0],gnames.water[1],gnames.water[2],gnames.water[3]},
    action=function(p)
      if p.y~=0 then return end
      local id=Sim.id(math.floor(p.x/2),math.floor(p.z/2))
      local node=id and S.tiles[id] and tile_node(id,p.x,p.y,p.z)
      if not id and p.x>=2-backdrop and p.x<=Sim.W*2+1+backdrop and
          p.z>=2-backdrop and p.z<=Sim.H*2+1+backdrop then node=ocean(p.x,p.z) end
      if node and node==ocean(p.x,p.z) then core.swap_node(p,{name=node}) end
    end,
  })
  local pending={}
  local function queue_near(id)
    if not api.interest then update_tile(id);return end
    local x,z=Sim.xy(id)
    local pos={x=x*2+.5,z=z*2+.5}
    if api.interest.near(pos,false,128) then update_tile(id);return end
    local k=api.interest.sector(pos.x,pos.z)
    local bucket=pending[k] or {};pending[k]=bucket
    bucket[id]=true
  end
  local interest_frame=0
  function R.refresh_interest()
    if not api.interest then return end
    interest_frame=interest_frame+1
    if interest_frame%4~=0 then return end
    local quota=64
    for key in pairs(api.interest.sectors(128)) do
      local bucket=pending[key]
      if bucket then
        for id in pairs(bucket) do
          update_tile(id);bucket[id]=nil
          quota=quota-1
          if quota==0 then return end
        end
        pending[key]=nil
      end
    end
  end
  local observed_gates={}
  function R.crossing_gates()
    for id in pairs(S.level_crossing_tiles or {}) do
      local t=S.tiles[id].level_crossing
      if t then
        local value=t.barred or t.phase=="unobserved" or t.phase=="mixed_occupancy"
        if observed_gates[id]~=value then
          observed_gates[id]=value
          queue_near(id)
        end
      end
    end
  end
  local function update_set(changed,paint)
    local set={}
    update_river_directions(set)
    for _,id in ipairs(changed or {}) do
      set[id]=true
      for d=1,4 do local j=Sim.adjacent(id,d);if j then set[j]=true end end
    end
    for id in pairs(set) do paint(id) end
  end
  function R.update(changed) update_set(changed,update_tile) end
  function R.update_near(changed) update_set(changed,queue_near) end
  local models={bus="town_flyer",leopard_bus="leopard_bus",mail_van="mail_van",coal_tipper="coal_tipper",truck="truck",coach="coach",
    wood_truck="witcombe_wood_truck",goods_truck="balogh_goods_truck",craighead_goods_truck="craighead_goods_truck",
    steam="steam",diesel="diesel",electric="electric",ferry="ferry",freighter="freighter",prop="prop",jet="jet"}
  local paint={wood_truck="bl_witcombe_wood_truck_atlas.png",goods_truck="bl_balogh_goods_truck_atlas.png",
    craighead_goods_truck="bl_craighead_goods_truck_atlas.png",
    coal_tipper="bl_coal_tipper_palette.png",leopard_bus="bl_road_fleet_palette.png",mail_van="bl_road_fleet_palette.png",
    foster_bus="bl_foster_bus_atlas.png"}
  if Sim.foster_art_ready(S) then models.foster_bus="foster_bus" end
  local road_art=dofile(modpath.."/road_stock_media.lua")
  local road_cap=api.capabilities and api.capabilities.road
  for id in pairs(road_cap and road_cap.extra or {}) do
    local model=road_art.models[id]
    models[id],paint[id]=model,"bl_"..model.."_atlas.png"
  end
  if api.farm_world then
    models.grain_truck,models.livestock_van="hereford_grain_truck","talbott_livestock_van"
    paint.grain_truck,paint.livestock_van="bl_hereford_grain_truck_atlas.png","bl_talbott_livestock_van_atlas.png"
  end
  if api.oil_world then
    models.oil_tanker="witcombe_oil_tanker"
    paint.oil_tanker="bl_witcombe_oil_tanker_atlas.png"
  end
  for id,mesh in pairs(models) do
    core.register_entity("luanttd_core:vehicle_"..id,{
      initial_properties={physical=false,pointable=false,collide_with_objects=false,
        static_save=false,visual="mesh",mesh="bl_"..mesh..".obj",textures={paint[id] or "bl_vehicle_palette.png"},
        shaded=true,backface_culling=true,visual_size=road_lanes.visual_size(id)},
    })
  end
  local floaters={}
  function R.leave(n)
    floaters[n]=nil
    if api.crowd then api.crowd.leave(n) end
  end
  local function cue(name,n,id)
    local p=core.get_player_by_name(n)
    if not p then return end
    local q=p:get_pos()
    local x,z=Sim.xy(id);x,z=x*2+.5,z*2+.5
    if (q.x-x)^2+(q.z-z)^2>32^2 or q.y>34 then return end
    core.sound_play(name,{to_player=n,gain=.38},true)
  end
  function R.float(n,id,value,color)
    local p=core.get_player_by_name(n)
    if not p then return end
    local x,z=Sim.xy(id)
    local t=S.tiles[id]
    local high=color==0xa6ee89 or color==0x9bdce8
    local q={x=x*2+.5,y=t.h+(high and 3.20 or 2.2),z=z*2+.5}
    local list=floaters[n] or {}
    if #list>=7 then p:hud_remove(table.remove(list,1).hud) end
    list[#list+1]={pos=q,life=0,hud=p:hud_add({type="waypoint",name=value,text="",precision=0,world_pos=q,number=color,z_index=90})}
    floaters[n]=list
  end
  function R.preview(n,route,valid)
    local tex=valid and "bl_preview_ok.png" or "bl_preview_no.png"
    for _,id in ipairs(route) do
      local x,z=Sim.xy(id)
      local t=S.tiles[id];local y=t.h+.57
      if t.site or t.house or t.build=="road_depot" then y=y+1 end
      for j=-1,1,2 do
        local px,pz=x*2+.5+j*.74,z*2+.5+j*.74
        local py=terrain and R.uses_slope(id) and R.surface(id,px,pz)+.07 or y
        core.add_particle({pos={x=px,y=py,z=pz},
          expirationtime=.16,size=1.22,glow=10,texture=tex,playername=n})
      end
    end
  end
  local projected_actors=dofile(modpath.."/campaign_projected_actors.lua")(core,api,road_motion,models,
    dofile(modpath.."/airport_manifest.lua")(core,modpath))
  local exhaust_view=dofile(modpath.."/rail_exhaust_view.lua")(core,
    dofile(modpath.."/rail_exhaust_model.lua"),vector and vector.rotate)
  local worker_observation
  local actor_buffer=dofile(modpath.."/campaign_actor_buffer.lua")()
  function R.waiting_at(mode,id)
    if worker_observation then return worker_observation.waiting(mode,id) end
  end
  function R.sample_worker_actors(projection)
    actor_buffer.observe(projection.actors(),projection.actor_clock())
  end
  function R.step_worker_actors(dt)
    if worker_observation then
      local actors=actor_buffer.sample(core.get_us_time())
      projected_actors.render(actors,dt,worker_observation.signals and worker_observation.signals())
      exhaust_view.render(actors,dt)
    end
  end
  function R.draw_worker_actors(projection)
    worker_observation=projection
    if api.vehicle_ui then api.vehicle_ui.use_worker_projection(projection) end
    R.sample_worker_actors(projection)
    if api.crowd and projection.take_boardings then
      api.crowd.use_worker_projection(projection,visual.state,terrain)
    end
  end
  local refs,last,poses={},{},{}
  function R.remove_vehicle_views()
    for id,ref in pairs(refs) do
      if ref:get_pos() then ref:remove() end
      refs[id]=nil;last[id]=nil
    end
  end
  local function lerp(a,b,t) return a+(b-a)*t end
  local function tile_pose(id,mode,air)
    local x,z=Sim.xy(id)
    local tile=S.tiles[id]
    local h=tile.h+.52
    if mode=="road" and road_surface(id) then h=R.surface(id,x*2+.5,z*2+.5)+.02 end
    if tile.station and tile.build~="road_station" then h=1.42 end
    if air then h=h+6.0 end
    return x*2+.5,h,z*2+.5
  end
  local function road_ground(id,x,z)
    if road_surface(id) then return R.surface(id,x,z)+.02 end
    return S.tiles[id].h+.52
  end
  local function source_pose(frames,length,at)
    return source_pose_model.sample(S,frames,length,at,road_ground)
  end
  local function position(v,t)
    local projected,pos,yaw,pitch=source_pose_model.timeline(S,v,t,road_ground)
    if projected then return pos,yaw,pitch end
    if v.route and Sim.road_hidden_depot(v) then return end
    if Sim.road_motion_frame and v.road_speed_state and v.road_speed_state.lane_pose then
      -- The saved authoritative shifted frame is available one day before
      -- the next interpolation timeline. Restoring must not jump lanes.
      local sample=Sim.road_motion_frame(S,v)
      if sample then return source_pose({sample},1,1) end
    end
    local prev=poses[v.id]
    if not v.route then
      if v.depot and S.road_stock_clock then return end
      if v.road_stop_pose then
        if prev and prev.frames then
          return source_pose(prev.frames,#prev.route,lerp(prev.progress,#prev.route,t))
        end
        return source_pose({v.road_stop_pose},1,1)
      end
      local id=Sim.position(S,v)
      if not id then return end
      local mode=Sim.vehicles[v.engine].mode
      local x,y,z=tile_pose(id,mode,false)
      local yaw=last[v.id] and last[v.id].target_yaw
      if mode=="road" and S.corner_grid then
        if not yaw then
          for d,dir in ipairs(Sim.dir) do
            if Sim.road_edge(S,id,d) then yaw=math.atan2(dir[1],dir[2]);break end
          end
        end
        if not v.depot and yaw then x,z=road_lanes.position(x,z,math.sin(yaw),math.cos(yaw)) end
      end
      return {x=x,y=y,z=z},yaw or 0
    end
    local route=v.route
    local current=math.min(#route,v.progress)
    local at=lerp(prev and prev.route==route and prev.progress or math.max(1,current-.5),current,t)
    if v.road_motion_frames then return source_pose(v.road_motion_frames,#route,at) end
    local idx=math.max(1,math.min(#route-1,math.floor(at)))
    local mode=Sim.vehicles[v.engine].mode
    local a,b=route[idx],route[math.min(idx+1,#route)]
    local fraction=at-idx
    if mode=="air" then a,b=route[1],route[#route];fraction=(at-1)/math.max(1,#route-1) end
    local x,y,z=tile_pose(a,mode,mode=="air")
    local u,w,q=tile_pose(b,mode,mode=="air")
    local yaw= (q==z and u==x) and 0 or math.atan2(u-x,q-z)
    local px,pz=lerp(x,u,fraction),lerp(z,q,fraction)
    local height,pitch=lerp(y,w,fraction),0
    if mode=="road" and S.corner_grid then
      local function permits_corner(id)
        local tile=S.tiles[id]
        local grade=road_surface(id)
        return tile.build=="road" and grade==0
      end
      local rx,rz,tx,tz,turn_tile=road_motion.corner(route,at,Sim.xy,permits_corner)
      if rx then
        rx,rz=road_lanes.position(rx,rz,tx,tz,road_lanes.outside_phase(route,at,Sim.xy))
        return {x=rx,y=R.surface(turn_tile,rx,rz)+.02,z=rz},math.atan2(tx,tz),0
      end
      local from_depot=S.tiles[a].build=="road_depot"
      local to_depot=S.tiles[b].build=="road_depot"
      local function lane(f)
        local blend=road_lanes.depot_blend(f,from_depot,to_depot)
        return road_lanes.position(lerp(x,u,f),lerp(z,q,f),u-x,q-z,nil,blend)
      end
      px,pz=lane(fraction)
      local function road_height(f)
        local id=f<.5 and a or b
        local gx,gz=lane(f)
        if road_surface(id) then return R.surface(id,gx,gz)+.02 end
        return S.tiles[id].h+.52
      end
      local back,forward=math.max(0,fraction-.12),math.min(1,fraction+.12)
      height=road_height(fraction)
      if forward>back then
        -- Object rotation stores elevation with the opposite sign to the
        -- world-space forward tangent. Verify with the physical mesh on a ramp.
        pitch=-math.atan((road_height(forward)-road_height(back))/(2*(forward-back)))
      end
    end
    return {x=px,y=height,z=pz},yaw,pitch
  end
  function R.pick(p)
    local pos=p:get_pos()
    pos.y=pos.y+(p:get_properties().eye_height or 1.625)
    local ray=p:get_look_dir()
    local best,tbest
    for id,ref in pairs(refs) do
      local q=ref:get_pos()
      if q and S.fleet[id] then
        local road=Sim.vehicles[S.fleet[id].engine].mode=="road"
        local x,y,z=q.x-pos.x,q.y+(road and .13 or .35)-pos.y,q.z-pos.z
        local t=x*ray.x+y*ray.y+z*ray.z
        if t>0 and t<75 and (not tbest or t<tbest) and x*x+y*y+z*z-t*t<(road and .37 or .65)^2 then best,tbest=id,t end
      end
    end
    return best
  end
  local fare_seen,arrival_seen,board_seen={},{},{}
  function R.prime_service_activity()
    for id,v in pairs(S.fleet) do
      fare_seen[id]=v.last_fare
      arrival_seen[id]=v.last_arrival
      board_seen[id]=v.last_board
    end
  end
  R.prime_service_activity()
  function R.capture()
    poses={}
    for id,v in pairs(S.fleet) do
      if v.route then poses[id]={route=v.route,progress=v.progress,frames=v.road_motion_frames} end
    end
  end
  local acc=0
  function R.frame(dt,fraction)
    acc=acc+dt
    if acc<.075 then return end
    local elapsed=acc
    acc=0
    local players=core.get_connected_players()
    local function fare_effect(owner,cargo,fare)
      R.float(owner,fare.tile,"+$"..fare.amount.."  /  "..fare.units.." "..(cargo=="coal" and "t coal" or Sim.cargo[cargo].name:lower()),0xa6ee89)
      if S.road_economy and fare.amount>0 then cue("bayline_fare",owner,fare.tile) end
    end
    local function arrival_effect(owner,cargo,event)
      if not event.first then return end
      local label=cargo=="coal" and "Coal tipper arrived" or cargo=="mail" and "Post van arrived" or "First bus arrived"
      R.float(owner,event.tile,label,0x9bdce8)
      cue("bayline_first_arrival",owner,event.tile)
    end
    local function board_effect(owner,cargo,event)
      if event.units<=0 then return end
      R.float(owner,event.tile,event.units..(cargo=="coal" and " t coal loaded" or cargo=="mail" and " mail bags loaded" or " boarded"),0x9bdce8)
      local t=S.tiles[event.tile]
      local station=t and S.stations[t.station]
      if station and api.crowd and cargo=="passenger" then api.crowd.board(station,event.units) end
    end
    -- One rendered day can contain several real boarding slices and even
    -- multiple stops. Drain all pulses in sequence, then mark the saved
    -- historical snapshots seen so the legacy fallback won't repeat them.
    if Sim.rail_coal_loading_events then
      for _,effect in ipairs(Sim.rail_coal_loading_events(S)) do
        if effect.kind=="fare" and effect.amount>0 and effect.units>0 then
          R.float(effect.owner,effect.tile,"+$"..effect.amount.."  /  "..effect.units.." t rail coal",0xa6ee89)
          cue("bayline_fare",effect.owner,effect.tile)
        elseif effect.kind=="board" and effect.units>0 then
          R.float(effect.owner,effect.tile,effect.units.." t loaded by rail",0x9bdce8)
        end
      end
    end
    if Sim.rail_loading_events then
      for _,effect in ipairs(Sim.rail_loading_events(S)) do
        if effect.kind=="fare" and effect.amount>0 and effect.units>0 then
          R.float(effect.owner,effect.tile,"+$"..effect.amount.."  /  "..effect.units.." rail passengers",0xa6ee89)
          cue("bayline_fare",effect.owner,effect.tile)
        elseif effect.kind=="board" and effect.units>0 then
          R.float(effect.owner,effect.tile,effect.units.." boarded the train",0x9bdce8)
          if api.crowd then api.crowd.board_terminal("rail",effect.station_local,effect.units) end
        end
      end
    end
    if Sim.ferry_loading_events then
      for _,effect in ipairs(Sim.ferry_loading_events(S)) do
        if effect.kind=="fare" and effect.amount>0 and effect.units>0 then
          R.float(effect.owner,effect.tile,"+$"..effect.amount.."  /  "..effect.units.." ferry passengers",0xa6ee89)
          cue("bayline_fare",effect.owner,effect.tile)
        elseif effect.kind=="board" and effect.units>0 then
          R.float(effect.owner,effect.tile,effect.units.." boarded the ferry",0x9bdce8)
          if api.crowd then api.crowd.board_terminal("ship",effect.station_local,effect.units) end
        end
      end
    end
    if Sim.air_loading_events then
      for _,effect in ipairs(Sim.air_loading_events(S)) do
        if effect.kind=="fare" and effect.amount>0 and effect.units>0 then
          R.float(effect.owner,effect.tile,"+$"..effect.amount.."  /  "..effect.units.." air passengers",0xa6ee89)
          cue("bayline_fare",effect.owner,effect.tile)
        elseif effect.kind=="board" and effect.units>0 then
          R.float(effect.owner,effect.tile,effect.units.." boarded the trimotor",0x9bdce8)
          if api.crowd then api.crowd.board_terminal("air",effect.station_local,effect.units) end
        end
      end
    end
    if Sim.road_loading_events then
      for _,effect in ipairs(Sim.road_loading_events(S)) do
        local v=S.fleet[effect.vehicle]
        if effect.kind=="fare" then
          fare_effect(effect.owner,effect.cargo,effect.data)
          fare_seen[effect.vehicle]=v and v.last_fare
        elseif effect.kind=="arrival" then
          arrival_effect(effect.owner,effect.cargo,effect.data)
          arrival_seen[effect.vehicle]=v and v.last_arrival
        elseif effect.kind=="board" then
          board_effect(effect.owner,effect.cargo,effect.data)
          board_seen[effect.vehicle]=v and v.last_board
        end
      end
    end
    road_fault_view.step(elapsed)
    for id,v in pairs(S.fleet) do
      local pos,yaw,pitch=position(v,fraction)
      local ref=refs[id]
      if api.vehicle_ui then api.vehicle_ui.track("road",id,pos) end
      if v.last_fare and fare_seen[id]~=v.last_fare then
        fare_seen[id]=v.last_fare
        fare_effect(v.owner,v.cargo,v.last_fare)
      end
      if S.road_economy and v.last_arrival and arrival_seen[id]~=v.last_arrival then
        arrival_seen[id]=v.last_arrival
        arrival_effect(v.owner,v.cargo,v.last_arrival)
      end
      if S.road_economy and v.last_board and board_seen[id]~=v.last_board then
        board_seen[id]=v.last_board
        board_effect(v.owner,v.cargo,v.last_board)
      end
      local nearby=api.interest and api.interest.near(pos,ref~=nil) or false
      if pos and not api.interest then
        for _,p in ipairs(players) do
          local a=p:get_pos()
          if (a.x-pos.x)^2+(a.y-pos.y)^2+(a.z-pos.z)^2<84^2 then nearby=true;break end
        end
      end
      if nearby and models[v.engine] then
        if not ref or not ref:get_pos() then
          ref=core.add_entity(pos,"luanttd_core:vehicle_"..v.engine);refs[id]=ref;last[id]=nil
        end
        if ref then
          if api.vehicle_ui then api.vehicle_ui.track("road",id,pos,ref) end
          local visible_load=road_art.payload(v.engine,models[v.engine],v.units)
          if visible_load and (not last[id] or visible_load~=last[id].visible_load) then
            ref:set_properties({mesh=visible_load})
          end
          ref:move_to(pos,true)
          local turn=yaw
          if Sim.vehicles[v.engine].mode=="road" then
            turn=road_motion.turn(last[id] and last[id].yaw,road_motion.nose_yaw(yaw),math.min(1.0,elapsed*7.2))
            ref:set_rotation({x=pitch or 0,y=turn,z=0})
          elseif pitch then ref:set_rotation({x=pitch,y=yaw,z=0})
          else ref:set_yaw(yaw) end
          last[id]={yaw=turn,target_yaw=yaw,visible_load=visible_load}
          if v.road_fault then road_fault_view.draw(id,v.road_fault,pos,turn,players,S.speed==0) end
        end
      elseif ref then ref:remove();refs[id]=nil end
    end
    if api.crowd then api.crowd.update(players,elapsed) end
    for n,list in pairs(floaters) do
      local p=core.get_player_by_name(n)
      if p then
        for i=#list,1,-1 do
          local f=list[i];f.life=f.life+.075
          if f.life>2.3 then p:hud_remove(f.hud);table.remove(list,i)
          else
            f.pos.y=f.pos.y+.046
            p:hud_change(f.hud,"world_pos",f.pos)
          end
        end
      end
    end
    for id,r in pairs(refs) do if not S.fleet[id] then
      r:remove();refs[id]=nil;last[id]=nil;road_fault_view.remove(id)
    end end
  end
  return R
end
