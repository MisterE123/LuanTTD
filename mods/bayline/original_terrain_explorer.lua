-- Separate read-only Luanti game mode for the stock Original landscape.
-- The startup gate may be called before any campaign or normal node setup.
local E={setting="bayline_original_terrain_exploration",mask_file="original-mapgen.bin"}
local identity_key="original_terrain_exploration_identity"
local DIGEST="7ff877ad58ebcdc15cb49824c5c2bab434b2c19d7e48319b38ad94434003f432"
local CHUNK=8
local floor,min,max=math.floor,math.min,math.max
local clamp=function(v,lo,hi)return min(hi,max(lo,v)) end
local function logical(q) return floor((q+.5)/2) end

local sizes={[64]=true,[128]=true,[256]=true,[512]=true,[1024]=true,[2048]=true,[4096]=true}
function E.options(settings)
  local function read(setting,default)
    local raw=settings:get("bayline_original_terrain_"..setting)
    return raw==nil and default or tonumber(raw)
  end
  local w,h,seed=read("width",64),read("depth",64),read("seed",1751)
  assert(w and h and sizes[w] and sizes[h],"Original terrain axes must be powers of two from 64 to 4096.")
  assert(seed and seed>=0 and seed<2^32 and floor(seed)==seed,"Original terrain seed must be a uint32.")
  return {width=w,depth=h,seed=seed,terrain_type=3,quantity_sea_lakes=0,freeform_edges=true,masks_sha256=DIGEST}
end

function E.profiles(world)
  local stats=world.stats()
  local w,h=stats.width,stats.depth
  if w==64 and h==64 and stats.seed==1751 then
    return {
      coast={x=6,z=43,y=9,look_x=17,look_z=42,look_y=2},
      transect={x=13,z=33,y=20,look_x=40,look_z=33,look_y=10},
      summit={x=35,z=35,y=27,look_x=30,look_z=25,look_y=7},
    }
  end
  local mx,mz=w/2,h/2
  local stride_x,stride_z=max(2,floor(w/32)),max(2,floor(h/32))
  local function survey(x,z,tx,tz,lift)
    x,z=clamp(x,2,w-1),clamp(z,2,h-1)
    tx,tz=clamp(tx,2,w-1),clamp(tz,2,h-1)
    if x==tx and z==tz then tx=x<w-1 and x+1 or x-1 end
    return {x=x,z=z,y=world.tile(x,z).high+lift,
      look_x=tx,look_z=tz,look_y=world.tile(tx,tz).base+.6}
  end
  local summit,coast
  local function proximity(x,z) return math.abs(x-mx)+math.abs(z-mz) end
  local function try(x,z)
    local t=world.tile(x,z)
    local distance=proximity(x,z)
    if not summit or t.high>summit.high or (t.high==summit.high and distance<summit.dist) then
      summit={x=x,z=z,high=t.high,dist=distance}
    end
    -- A flat sea and adjacent real land are just as useful as an
    -- actual shore tile. Keep selection bounded independently of area.
    if t.ground~=0 and (not coast or distance<coast.dist) then
      for _,d in ipairs({{5,0},{0,5},{-5,0},{0,-5}}) do
        local u,v=x+d[1],z+d[2]
        if u>=2 and u<w and v>=2 and v<h and world.tile(u,v).ground==0 then
          coast={x=x,z=z,look_x=u,look_z=v,dist=distance}
          break
        end
      end
    end
  end
  for j=0,31 do for i=0,31 do
    try(clamp(2+i*stride_x,2,w-1),clamp(2+j*stride_z,2,h-1))
  end end
  local x,z=mx-3,mz+1
  local transectx=min(w-2,x+27)
  coast=coast or {x=mx,z=mz,look_x=mx+8,look_z=mz-5}
  return {
    coast=survey(coast.x,coast.z,coast.look_x,coast.look_z,8),
    transect=survey(x,z,transectx,z,16),
    summit=survey(summit.x-12,summit.z+16,summit.x+6,summit.z-8,18),
  }
end

local function install(core,world,Slope,Stream)
  local C=Stream.cover
  local bounds=world.stats()
  local WIDTH,DEPTH=bounds.width,bounds.depth
  local view=world.view({size=CHUNK,capacity=1})
  local stats={mapblocks=0,chunks=0,max_chunks_per_block=0}
  local masks={0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30}
  local coasts={[0]=true,true,true,true,true,false,true,true,true,true,false,true,true,true,true,
    [23]=true,[27]=true,[29]=true,[30]=true}
  local land,coast,soil={},{},{}
  core.set_mapgen_setting("mg_name","singlenode",true)
  core.set_mapgen_setting("chunksize","1",true)
  core.set_mapgen_setting("mg_flags","light",true)
  core.register_alias("mapgen_stone","air")
  core.register_alias("mapgen_water_source","air")
  core.register_alias("mapgen_river_water_source","air")
  local function node(name,values)
    local id="bayline:original_"..name
    for k,v in pairs({paramtype="light",sunlight_propagates=true,
        diggable=false,pointable=false,walkable=false,drop="",
        groups={not_in_creative_inventory=1}}) do values[k]=v end
    core.register_node(id,values)
    return id
  end
  for v=0,3 do
    local grass="bl_grass"..v..".png"
    local atlas="bl_original_coast_"..v..".png"
    soil[v]=node("earth_"..v,{description="Original survey terrain",
      drawtype="nodebox",node_box={type="fixed",fixed={-.5,-.5,-.5,.5,.485,.5}},
      tiles={grass,grass,"bl_grass_side.png"}})
    for _,s in ipairs(masks) do
      land[s],coast[s]=land[s] or {},coast[s] or {}
      land[s][v]=node("land_"..s.."_"..v,{description="Original terrain surface",
        drawtype="mesh",mesh="bl_land_"..s..".obj",tiles={grass}})
      if coasts[s] then
        coast[s][v]=node("coast_"..s.."_"..v,
          {description=s==0 and "Sea" or "Shore",
          drawtype="mesh",mesh="bl_original_coast_"..s..".obj",tiles={atlas}})
      end
    end
  end
  local ids={}
  local function cid(n)
    if not ids[n] then ids[n]=core.get_content_id(n) end
    return ids[n]
  end
  local function chunk_for(chunks,x,z)
    local a=floor((x-1)/CHUNK)
    local b=floor((z-1)/CHUNK)
    local key=b*(WIDTH/CHUNK)+a
    if not chunks[key] then
      local frame=assert(view.update(x,z,0,1))
      assert(frame.pending==0 and #frame.chunks==1 and frame.chunks[1].id==key,
        "Original terrain detached chunk mismatch")
      chunks[key]=frame.chunks[1]
      return key,true
    end
    return key,false
  end
  core.register_on_generated(function(minp,maxp)
    local x1,z1=max(1,floor(minp.x/2)),max(1,floor(minp.z/2))
    local x2,z2=min(WIDTH,floor(maxp.x/2)),min(DEPTH,floor(maxp.z/2))
    if x1>x2 or z1>z2 or maxp.y< -2 or minp.y>16 then return end
    local vm,lo,hi=core.get_mapgen_object("voxelmanip")
    local area=VoxelArea:new({MinEdge=lo,MaxEdge=hi})
    local data=vm:get_data()
    local chunks,count={},0
    for z=z1,z2 do for x=x1,x2 do
      local key,built=chunk_for(chunks,x,z)
      if built then count=count+1 end
      local p=assert(Stream.profile(chunks[key],x,z))
      if p.cover~=C.VOID then
        local v=(x*17+z*11+x*z*3)%4
        local nm
        if p.cover==C.COAST then nm=assert(coast[p.mask][v],"missing native shore profile")
        elseif p.cover==C.WATER_FLAT then nm=coast[0][v]
        else
          assert(p.cover==C.LAND_FLAT or p.cover==C.LAND_GRADED)
          nm=land[p.mask][v]
        end
        local fill=cid(soil[v])
        for nz=max(2*z,minp.z),min(2*z+1,maxp.z) do
          for nx=max(2*x,minp.x),min(2*x+1,maxp.x) do
            for y=max(-2,minp.y),min(p.base,maxp.y) do
              data[area:index(nx,y,nz)]=fill
            end
          end
        end
        local nx,ny,nz=2*x,p.base+1,2*z
        if nx>=minp.x and nx<=maxp.x and ny>=minp.y and ny<=maxp.y and nz>=minp.z and nz<=maxp.z then
          data[area:index(nx,ny,nz)]=cid(nm)
        end
      end
    end end
    assert(count<=4,"Original exploration requires one-mapblock map generation")
    stats.mapblocks=stats.mapblocks+1
    stats.chunks=stats.chunks+count
    stats.max_chunks_per_block=max(stats.max_chunks_per_block,count)
    vm:set_data(data)
    vm:calc_lighting()
    vm:write_to_map()
  end)

  local players={}
  local views=E.profiles(world)
  local function frame(p,profile)
    local a={x=profile.x*2+.5,y=profile.y,z=profile.z*2+.5}
    local dx,dz=2*(profile.look_x-profile.x),2*(profile.look_z-profile.z)
    local dy=profile.look_y-a.y-1.47
    p:set_pos(a)
    p:set_look_horizontal(math.atan2(-dx,dz))
    p:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
  end
  local function probe(pos)
    local x=clamp(logical(pos.x),2,WIDTH-1)
    local z=clamp(logical(pos.z),2,DEPTH-1)
    local record=world.tile(x,z)
    local u=clamp((pos.x-2*x+.5)/2,0,1)
    local v=clamp((pos.z-2*z+.5)/2,0,1)
    return x,z,record,.5+record.base+Slope.surface(u,v,record.mask)
  end
  local function material(t)
    if t.ground==1 then return "Sea"
    elseif t.ground==2 then return "Shore"
    else return t.mask==0 and "Grassland" or "Slope" end
  end
  local function clear_hud(p)
    p:hud_set_flags({hotbar=false,healthbar=false,crosshair=false,wielditem=false,
      breathbar=false,minimap=false,minimap_radar=false})
  end
  core.register_on_joinplayer(function(p)
    p:set_physics_override({gravity=0,speed=0,jump=0})
    p:override_day_night_ratio(.98)
    p:set_sky({type="regular",clouds=false,sky_color={day_sky="#a1cfe5",day_horizon="#c6dce5",
      indoors="#a1cfe5",fog_sun_tint="#dce8ea",fog_moon_tint="#c6dce5",fog_tint_type="custom"}})
    p:set_sun({visible=false,sunrise_visible=false})
    p:set_moon({visible=false})
    p:set_stars({visible=false})
    clear_hud(p)
    local hud=p:hud_add({type="text",position={x=.028,y=.06},alignment={x=1,y=0},
      text="LUANTTD  /  ORIGINAL TERRAIN",number=0xf7f3e2,style=1,size={x=1.10,y=1.10}})
    p:hud_add({type="text",position={x=.028,y=.94},alignment={x=1,y=0},
      text="WASD fly  •  Space rise  •  Shift sink  •  E boost  •  /terrain",number=0xf7f3e2})
    players[p:get_player_name()]={hud=hud}
    frame(p,views.coast)
  end)
  core.register_on_leaveplayer(function(p) players[p:get_player_name()]=nil end)
  core.register_on_mods_loaded(function() core.set_timeofday(.51) end)
  core.register_allow_player_inventory_action(function() return 0 end)
  -- Explorer has no normal game commands or writable inventory. Even a
  -- client able to issue raw placement interactions sees a protected map.
  core.is_protected=function() return true end

  core.register_globalstep(function(dt)
    for name,q in pairs(players) do
      local p=core.get_player_by_name(name)
      if p then
        local c=p:get_player_control()
        local pos=p:get_pos()
        local f=(c.up and 1 or 0)-(c.down and 1 or 0)
        local r=(c.right and 1 or 0)-(c.left and 1 or 0)
        local rise=(c.jump and 1 or 0)-(c.sneak and 1 or 0)
        local speed=(c.aux1 and 17 or 9)*min(dt,.12)
        if f~=0 or r~=0 or rise~=0 then
          local yaw=p:get_look_horizontal()
          local advance=math.sin(yaw)
          local across=math.cos(yaw)
          local scale=speed/math.sqrt(max(1,f*f+r*r))
          pos.x=clamp(pos.x+scale*(-f*advance+r*across),3.51,2*(WIDTH-1)+1.49)
          pos.z=clamp(pos.z+scale*( f*across+r*advance),3.51,2*(DEPTH-1)+1.49)
          pos.y=min(90,pos.y+rise*speed)
        end
        local x,z,t,ground=probe(pos)
        if f~=0 or r~=0 or rise~=0 or pos.y<ground+.65 then
          pos.y=max(pos.y,ground+.65)
          p:set_pos(pos)
        end
        local desc=("%s  |  tile %d, %d  |  ground %.1f"):format(material(t),x,z,ground-.5)
        if q.desc~=desc then
          q.desc=desc
          p:hud_change(q.hud,"text",("LUANTTD  /  ORIGINAL TERRAIN\n%d × %d   ·   %s"):format(WIDTH,DEPTH,desc))
        end
      end
    end
  end)
  core.register_chatcommand("terrain",{params="[coast | transect | summit | tile X Z | inspect]",
    description="Explore the source Original terrain",func=function(name,param)
      local p=core.get_player_by_name(name)
      if not p then return false end
      local a,b=param:match("^tile%s+(%d+)%s+(%d+)%s*$")
      if a and b then
        local x,z=tonumber(a),tonumber(b)
        if x<2 or x>=WIDTH or z<2 or z>=DEPTH then
          return false,("Playable grid: X 2–%d, Z 2–%d."):format(WIDTH-1,DEPTH-1)
        end
        local t=world.tile(x,z)
        frame(p,{x=x,z=z,y=t.high+9,look_x=x,look_z=z+(z<DEPTH-4 and 4 or -4),look_y=t.base})
        return true
      elseif views[param] then
        frame(p,views[param]);return true
      elseif param=="inspect" then
        local x,z,t=probe(p:get_pos())
        return true,("%s at %d, %d • class %d • corner slope mask %d • level %d–%d"):format(
          material(t),x,z,t.class,t.mask,t.base,t.high)
      end
      return true,"Read-only terrain. Try /terrain coast, transect, summit, tile X Z, or inspect."
    end})
  return {world=world,stats=function()
    return {mapblocks=stats.mapblocks,chunks=stats.chunks,max_chunks_per_block=stats.max_chunks_per_block,
      cache=view.stats().cached}
  end}
end

function E.start(core,modpath,storage)
  local enabled=core.settings:get_bool(E.setting,false)
  local marker=storage:get_string(identity_key)
  if not enabled then
    assert(marker=="","This is an Original terrain exploration world; keep "..E.setting.." enabled.")
    return nil
  end
  assert(storage:get_string("campaign")=="",
    "Original terrain exploration requires a fresh world; a campaign already exists here.")
  local worldpath=core.get_worldpath()
  local manifest=io.open(worldpath.."/world.mt","rb")
  if manifest then
    local saved=manifest:read(32769)
    manifest:close()
    assert(saved and #saved<=32768,"Original exploration world metadata is too large.")
    local backend=("\n"..saved.."\n"):match("\n%s*backend%s*=%s*([%w_%-]+)")
    assert(not backend or backend=="sqlite3","Original terrain exploration expects a SQLite map backend.")
  end
  if marker=="" then
    -- Refuse a pre-existing SQLite map even if an ordinary campaign
    -- previously generated tiles without writing a campaign save.
    local map=io.open(worldpath.."/map.sqlite","rb")
    if map then
      local n=map:seek("end")
      map:close()
      assert(n==0,"Original terrain exploration requires a fresh SQLite map.")
    end
  end
  local path=worldpath.."/"..E.mask_file
  local f=assert(io.open(path,"rb"),"Missing local "..E.mask_file.."; see docs/original-terrain-exploration.md.")
  local bytes=f:read(131073)
  f:close()
  assert(bytes and #bytes<=131072 and core.sha256(bytes)==DIGEST,
    "Original terrain exploration needs the verified local OpenGFX 7.1 mask bank.")
  local function module(rel) return dofile(modpath.."/"..rel..".lua") end
  local Slope=module("openttd/slope")
  local G=module("openttd/original_terrain")(Slope)
  local Stream=module("terrain_stream")(Slope)
  local Host=module("original_terrain_stream")(G,module("world_storage"),Stream,Slope)
  local bank=assert(G.read_masks(bytes))
  local options=E.options(core.settings)
  local world=assert(Host.open(options,bank))
  local identity=world.stats().base_id
  assert(marker=="" or marker==identity,"Original terrain settings differ from those of the saved map.")
  local service=install(core,world,Slope,Stream)
  if marker=="" then storage:set_string(identity_key,identity) end
  core.log("action",("LUANTTD ORIGINAL TERRAIN READY %dx%d seed %u (read-only)"):format(
    options.width,options.depth,options.seed))
  return service
end
return E
