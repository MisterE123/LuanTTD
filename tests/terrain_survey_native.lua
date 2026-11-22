-- This disposable fixture deliberately has no simulation/campaign modules.
local ns="stock_survey:"
local path=core.get_modpath(core.get_current_modname())
local function module(name) return dofile(path.."/"..name..".lua") end
local function json(name)
  local f=assert(io.open(path.."/"..name..".json","rb"))
  local bytes=f:read("*a");f:close()
  return assert(core.parse_json(bytes))
end
local Slope,Road=module("slope"),module("road_slope")
local W=module("world_storage")
local Stream=module("terrain_stream")(Slope)
local Sparse=module("openttd_sparse")(W,module("openttd_map"),core.sha256)
local base=Sparse.prepare(json("snapshot"))
local ground=module("openttd_ground").prepare(json("ground"),base)
local world=base.new_world()
local stream=Stream.new(Stream.for_overlay(world,Sparse.unpack_tile,ground),{size=8,capacity=36})
local views=json("views")
local C=Stream.cover
local floor,max,min=math.floor,math.max,math.min
local RADIUS,BUDGET,CLEAR=20,2,4
core.set_mapgen_setting("mg_name","singlenode",true)
core.set_mapgen_setting("mg_flags","light",true)
core.register_alias("mapgen_stone","air")
core.register_alias("mapgen_water_source","air")
local masks={}
for s=0,30 do
  if s<15 or s==23 or s==27 or s==29 or s==30 then masks[#masks+1]=s end
end
local function mesh(name,file,texture)
  core.register_node(ns..name,{description=name,drawtype="mesh",mesh=file..".obj",tiles={texture..".png"},
    paramtype="light",sunlight_propagates=true,walkable=false,pointable=false,groups={not_in_creative_inventory=1}})
end
for g=0,3 do
  core.register_node(ns.."fill"..g,{description="Survey earth",tiles={"bl_grass"..g..".png","bl_grass0.png","bl_grass_side.png"},
    drawtype="nodebox",node_box={type="fixed",fixed={-.5,-.5,-.5,.5,.485,.5}},
    groups={not_in_creative_inventory=1}})
  mesh("tree"..g,"bl_scenery_tree_"..g,"bl_scenery_palette")
  for _,s in ipairs(masks) do
    local file="bl_land_"..s
    mesh("land"..s.."_"..g,file,"bl_grass"..g)
    mesh("water"..s.."_"..g,file,"bl_water"..g)
    mesh("coast"..s.."_"..g,file,"survey_coast_"..s.."_"..g)
  end
end
for bits=1,15 do
  -- Stock ordinary roads may be flat, retain a straight two-corner ramp,
  -- or use their exact leveling/incline foundation. No crossing/stop art guessed.
  for _,s in ipairs({0,3,6,9,12}) do
    mesh("road"..s.."_"..bits,"bl_land_"..s,"bl_road_surface_"..bits)
  end
end
local live={}
local bu,ev,maxbuilt,maxresident,totalroad,totalcoast,maxclear,resident=0,0,0,0,0,0,0,0
local function terrain_name(p,g)
  if p.cover==C.COAST or p.cover==C.COAST_TREES then return "coast"..p.mask.."_"..g end
  if p.cover==C.WATER_FLAT or p.cover==C.WATER_GRADED or p.cover==C.LOCK or p.cover==C.DEPOT then
    return "water"..p.mask.."_"..g
  end
  return "land"..p.mask.."_"..g
end
local function visit(t,f)
  for dz=0,1 do for dx=0,1 do
    for y=t.bottom,t.y do f(t.fill,t.x+dx,y,t.z+dz) end
  end end
  f(t.node,t.x,t.y+1,t.z)
  if t.tree then local a=t.tree; f(a.name,a.x,a.y,a.z) end
end
local function put_chunk(ch)
  local jobs={}
  for z=ch.z,ch.z+ch.depth-1 do for x=ch.x,ch.x+ch.width-1 do
    local p=Stream.profile(ch,x,z)
    if p.cover~=C.VOID then
      local g=(x*17+z*11+x*z*3)%4
      local top,name=p.base,terrain_name(p,g)
      local _,bits=Sparse.unpack_tile(p.word)
      local rec=bits and bits~=0 and base.source_road_tile(x,z)
      if rec and rec.kind=="road" and rec.road_type==0 then
        local shape,raise=Slope.foundation(p.mask,Road.foundation(p.mask,bits))
        if shape==0 or shape==3 or shape==6 or shape==9 or shape==12 then
          top,name=p.base+raise,"road"..shape.."_"..bits
          totalroad=totalroad+1
        end
      end
      local tree
      if p.class==4 and p.cover~=C.COAST_TREES and ((x*991+z*613)%6)==0
        and Stream.height(ch,x,z,.75,.75)==p.high+.5 then
        -- Only place a node mesh where its rooting datum matches terrain.
        tree={x=2*x+1,z=2*z+1,y=p.high+1,name="tree"..g}
      end
      if p.cover==C.COAST or p.cover==C.COAST_TREES then totalcoast=totalcoast+1 end
      jobs[#jobs+1]={x=2*x,z=2*z,y=top,bottom=max(-1,top-2),node=name,fill="fill"..g,tree=tree}
    end
  end end
  local groups={}
  local function add(name,x,y,z)
    if not groups[name] then groups[name]={} end
    local g=groups[name]
    g[#g+1]={x=x,y=y,z=z}
  end
  for _,t in ipairs(jobs) do visit(t,add) end
  for name,positions in pairs(groups) do core.bulk_set_node(positions,{name=ns..name}) end
  for _,t in ipairs(jobs) do
    assert(core.get_node({x=t.x,y=t.y+1,z=t.z}).name==ns..t.node,"native terrain anchor missing")
  end
  live[ch.id]=jobs
  resident=resident+1
end
local function remove_chunk(id)
  local jobs=assert(live[id])
  local cells={}
  local function add(_,x,y,z) cells[#cells+1]={x=x,y=y,z=z} end
  for _,t in ipairs(jobs) do visit(t,add) end
  if #cells>0 then core.bulk_set_node(cells,{name="air"}) end
  live[id]=nil
  ev=ev+1
  resident=resident-1
end
local function refresh(tx,tz)
  local frame=assert(stream.update(max(1,min(base.width,tx)),max(1,min(base.depth,tz)),RADIUS,BUDGET))
  assert(frame.built<=BUDGET)
  local seen,retired={},{}
  for _,c in ipairs(frame.chunks) do seen[c.id]=true end
  for id in pairs(live) do if not seen[id] then retired[#retired+1]=id end end
  table.sort(retired)
  local cleared=min(#retired,CLEAR)
  for i=1,cleared do remove_chunk(retired[i]) end
  local drawn,queued=0,0
  for _,c in ipairs(frame.chunks) do
    if not live[c.id] then
      if drawn<BUDGET and resident<36 then put_chunk(c);drawn=drawn+1
      else queued=queued+1 end
    end
  end
  assert(drawn<=BUDGET and resident<=36 and cleared<=CLEAR)
  bu=bu+drawn
  maxbuilt=max(maxbuilt,drawn)
  maxresident=max(maxresident,resident)
  maxclear=max(maxclear,cleared)
  frame.pending=frame.pending+queued+#retired-cleared
  return frame
end
local function orient(p,from,at)
  p:set_pos(from)
  local dx,dy,dz=at.x-from.x,at.y-from.y-1.47,at.z-from.z
  p:set_look_horizontal(math.atan2(-dx,dz))
  p:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
end
local mode,current,stable,phase="coast","",nil,nil
local last,elapsed=0,0
local hud
local emerged,emerge_generation=false,0
core.register_on_mods_loaded(function() core.set_timeofday(.5) end)
local function target(name)
  local a=views[name]
  local x,z=2*a.x+.5,2*a.z+.5
  if name=="coast" then
    return {x=x-15,y=a.y+12,z=z-21},{x=x+2,y=1.5,z=z+4}
  end
  return {x=x-12,y=a.y+12,z=z-18},{x=x+1,y=a.y-2,z=z+3}
end
local function emerge_camera(x1,z1,x2,z2)
  emerged=false
  emerge_generation=emerge_generation+1
  local token=emerge_generation
  local margin=2*(RADIUS+8)+3
  local lo={x=floor(min(x1,x2)-margin),y=-3,z=floor(min(z1,z2)-margin)}
  local hi={x=floor(max(x1,x2)+margin),y=views.max_height+3,z=floor(max(z1,z2)+margin)}
  core.emerge_area(lo,hi,function(_,action,left)
    assert(action~=core.EMERGE_CANCELLED and action~=core.EMERGE_ERRORED,"could not emerge disposable survey air")
    if left==0 and token==emerge_generation then emerged=true end
  end)
end
local function setup_view(p,name)
  mode,current,stable,phase=name,"",nil,nil
  local from,at=target(name)
  orient(p,from,at)
  emerge_camera(from.x,from.z,from.x,from.z)
end
local function pose_fly(p,t)
  local a=views.fly
  local x=2*(a.x1+(a.x2-a.x1)*t)+.5
  local z=2*a.z+.5
  orient(p,{x=x,y=a.y+9,z=z-6},{x=x+8,y=a.y-3,z=z+7})
end
core.register_on_joinplayer(function(p)
  p:set_physics_override({gravity=0,speed=1})
  core.set_player_privs(p:get_player_name(),{fly=true,noclip=true,shout=true})
  p:override_day_night_ratio(.96)
  p:set_sky({type="plain",base_color="#b9d6e9",clouds=false})
  p:set_sun({visible=false,sunrise_visible=false})
  p:set_moon({visible=false})
  p:set_stars({visible=false})
  for _,flag in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[flag]=false})
  end
  hud=p:hud_add({type="text",position={x=.027,y=.09},alignment={x=1,y=0},
    text="LuanTTD | PRIVATE TERRAIN SURVEY",number=0xf8f6e8,scale={x=100,y=30},size={x=1.05,y=1.05}})
  setup_view(p,"coast")
end)
core.register_chatcommand("survey",{
  params="coast|roads|fly",description="Private terrain survey proof",
  func=function(name,cmd)
    local p=core.get_player_by_name(name)
    if not p then return false end
    if cmd=="coast" or cmd=="roads" then setup_view(p,cmd);return true
    elseif cmd=="fly" then
      mode,current,stable,phase="fly","",nil,"prepare"
      elapsed=0;last=0
      pose_fly(p,0)
      local route=views.fly
      emerge_camera(2*route.x1+.5,2*route.z-5.5,2*route.x2+.5,2*route.z-5.5)
      return true
    end
    return false,"Choose coast, roads or fly"
  end,
})
local accumulator=0
core.register_globalstep(function(dt)
  local p=core.get_connected_players()[1]
  if not p or not emerged then return end
  if phase=="moving" then
    elapsed=min(6,elapsed+dt)
    pose_fly(p,elapsed/6)
  end
  accumulator=accumulator+dt
  if accumulator<.09 then return end
  accumulator=0
  local a=p:get_pos()
  local tx,tz=floor((a.x+.5)/2),floor((a.z+.5)/2)
  local f=refresh(tx,tz)
  if mode=="fly" then
    local c=floor((tx-1)/8)
    if phase=="moving" and c~=last then
      core.log("action",("TERRAIN_SURVEY_CROSS chunk=%d tile=%d"):format(c,tx))
      last=c
    end
    if phase=="prepare" and f.pending==0 then
      phase,last="moving",c
      core.log("action","TERRAIN_SURVEY_FLY_START")
    elseif phase=="moving" and elapsed>=6 then phase="settle"
    elseif phase=="settle" and f.pending==0 then
      phase=nil
      core.log("action","TERRAIN_SURVEY_FLY_END")
    end
  end
  if mode..":"..tx..":"..tz..":"..#f.chunks..":"..f.pending~=current then
    current=mode..":"..tx..":"..tz..":"..#f.chunks..":"..f.pending
    p:hud_change(hud,"text",("LuanTTD  |  PRIVATE TERRAIN SURVEY\n%s  •  tile %d,%d  •  %d/%d chunks"):format(
      mode:upper(),tx,tz,#f.chunks,#f.chunks+f.pending))
  end
  if f.pending==0 and not phase and stable~=mode then
    stable=mode
    core.log("action",("TERRAIN_SURVEY_READY %s built=%d evicted=%d maxbuilt=%d resident=%d road=%d coast=%d maxclear=%d"):format(
      mode,bu,ev,maxbuilt,maxresident,totalroad,totalcoast,maxclear))
  end
end)
