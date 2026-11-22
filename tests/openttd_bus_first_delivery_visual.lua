-- Native mesh presentation for the isolated resume proof only.
return function(trip,accepted,Slope,RoadSlope)
  local ns="triptest:"
  local C=accepted.board
  local initial=accepted.checkpoint()
  local bus=initial.vehicle
  local dest=bus.dest
  local label,model,ready,run,dt_bank=nil,nil,false,false,0
  local last_entity_pos
  core.set_mapgen_setting("mg_name","singlenode",true)
  core.set_mapgen_setting("mg_flags","light",true)
  local function mesh(name,file,texture)
    core.register_node(ns..name,{description=name,drawtype="mesh",mesh=file..".obj",tiles={texture..".png"},
      paramtype="light",sunlight_propagates=true,walkable=false,pointable=false})
  end
  core.register_node(ns.."soil",{description="Original LuanTTD grass",
    tiles={"bl_grass0.png","bl_grass0.png","bl_grass_side.png"},
    drawtype="nodebox",node_box={type="fixed",fixed={-.5,-.5,-.5,.5,.487,.5}}})
  for s=0,30 do
    if s<15 or s==23 or s==27 or s==29 or s==30 then
      mesh("land"..s,"bl_land_"..s,"bl_grass0")
    end
  end
  for bits=1,15 do for _,s in ipairs({0,3,6,9,12}) do
    mesh("road"..s.."_"..bits,"bl_land_"..s,"bl_road_surface_"..bits)
  end end
  for _,bits in ipairs({1,2,4,8}) do mesh("bay"..bits,"bl_land_0","stock_trip_bay_"..bits) end
  mesh("stop","bl_bus_shelter_corner","bl_road_architecture")
  core.register_entity(ns.."bus",{
    initial_properties={physical=false,static_save=false,pointable=false,visual="mesh",shaded=true,
      backface_culling=true,mesh="bl_town_flyer.obj",textures={"bl_vehicle_palette.png"},visual_size={x=.42,y=.42,z=.42}},
  })
  core.register_on_mods_loaded(function() core.set_timeofday(.5) end)
  local function draw(p)
    local s=trip.state()
    if not model then
      model=assert(core.add_entity(s.native,ns.."bus"))
      assert(model:get_properties().mesh=="bl_town_flyer.obj")
    end
    local at={x=s.native.x,y=s.native.y+.015,z=s.native.z}
    if not last_entity_pos or last_entity_pos.x~=at.x or last_entity_pos.z~=at.z then
      model:move_to(at,true)
      last_entity_pos=at
    end
    model:set_yaw(math.pi-(s.heading-3)*math.pi/4)
    p:hud_change(label,"text",("LuanTTD  |  STOCK BUS RESUME PROBE\nTick %d  •  %d onboard  •  %d delivered  •  £%d posted"):format(
      s.tick,s.units,s.delivered,s.payment))
    return s
  end
  local function orient(p,far)
    local x,z=2*dest.x+.5,2*dest.z+.5
    local y=bus.cursor.native.y
    local from=far and {x=x-5.3,y=y+2.1,z=z+4.2} or {x=x-2.9,y=y+1.35,z=z+3.9}
    local aim=far and {x=x-2.7,y=y+.25,z=z} or {x=x-.5,y=y+.3,z=z}
    p:set_pos(from)
    local dx,dy,dz=aim.x-from.x,aim.y-from.y-1.47,aim.z-from.z
    p:set_look_horizontal(math.atan2(-dx,dz))
    p:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
  end
  local tx1,tz1,tx2,tz2=bus.tile.x-6,dest.z-6,dest.x+7,dest.z+6
  local function build()
    local groups={}
    local function add(name,x,y,z)
      if not groups[name] then groups[name]={} end
      local g=groups[name]
      g[#g+1]={x=x,y=y,z=z}
    end
    for z=tz1,tz2 do for x=tx1,tx2 do
      local class,bits=C.tile(x,z)
      if class and class~=7 then
        local shape,base=Slope.classify(C.tile_corners(x,z))
        local top,name=base,"land"..shape
        if bits and bits>0 then
          local grade,raise=Slope.foundation(shape,RoadSlope.foundation(shape,bits))
          if grade==0 or grade==3 or grade==6 or grade==9 or grade==12 then
            top,name=base+raise,"road"..grade.."_"..bits
          end
        end
        for dz=0,1 do for dx=0,1 do
          add("soil",x*2+dx,top,z*2+dz)
          add("soil",x*2+dx,top-1,z*2+dz)
        end end
        if x==dest.x and z==dest.z then
          assert(shape==0 and (bits==1 or bits==2 or bits==4 or bits==8))
          name="bay"..bits
          -- Use the existing platform node with a spare anchor over this
          -- ground tile. Its authored base remains on the ground plane.
          add("stop",x*2,top+1,z*2-1)
        end
        add(name,x*2,top+1,z*2)
      end
    end end
    for name,pos in pairs(groups) do core.bulk_set_node(pos,{name=ns..name}) end
  end
  core.register_on_joinplayer(function(p)
    p:set_physics_override({gravity=0})
    p:override_day_night_ratio(.95)
    p:set_sky({type="plain",base_color="#b5d5e8",clouds=false})
    p:set_sun({visible=false,sunrise_visible=false})
    p:set_moon({visible=false})
    p:set_stars({visible=false})
    for _,f in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
      p:hud_set_flags({[f]=false})
    end
    label=p:hud_add({type="text",position={x=.029,y=.072},alignment={x=1,y=0},
      text="Preparing first loaded trip",number=0xfaf4dc,scale={x=100,y=70},size={x=1.1,y=1.1}})
    orient(p,true)
    local ply=p:get_player_name()
    core.emerge_area({x=tx1*2-7,y=-3,z=tz1*2-7},{x=tx2*2+7,y=14,z=tz2*2+7},function(_,_,count)
      if count==0 then
        build();ready=true
        local player=core.get_player_by_name(ply)
        if player then orient(player,true);draw(player) end
        core.log("action","LUANTTD STOCK TRIP VISUAL READY")
      end
    end)
  end)
  core.register_chatcommand("busprobe",{params="play | settle",description="Resume isolated first delivery",func=function(name,arg)
    local p=core.get_player_by_name(name)
    if not ready or not p then return false end
    if arg=="play" and trip.resume() then run="deliver";return true end
    if arg=="settle" and trip.state().delivery_tick and not trip.state().settlement_tick then
      run="settle";return true
    end
    return false,"No such action in the current fixture phase"
  end})
  core.register_globalstep(function(dt)
    if not run then return end
    local p=core.get_connected_players()[1]
    if not p then return end
    dt_bank=math.min(.12,dt_bank+dt)
    local s
    while dt_bank>=.027 do
      dt_bank=dt_bank-.027
      s=trip.step(1)
      if run=="deliver" and s.delivery_tick then
        run=false
        orient(p,false)
        core.log("action","LUANTTD STOCK TRIP VISUAL DELIVERED")
        break
      end
      if s.settlement_tick then
        run=false
        core.log("action","LUANTTD STOCK TRIP VISUAL SETTLED")
        break
      end
    end
    if s then draw(p) end
  end)
end
