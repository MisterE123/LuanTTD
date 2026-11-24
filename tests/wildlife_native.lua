-- Real engine mesh/observer check with a small water, farm and woodland
-- scene. The production ambient module decides where to place each animal.
local mod=core.get_modpath(core.get_current_modname())
local Vfile=dofile(mod.."/ambient_wildlife.lua")
local media={}
for _,folder in ipairs({"models","textures"}) do
  for _,f in ipairs(core.get_dir_list(mod.."/"..folder,false)) do media[f]=true end
end
local Sim={}
function Sim.id(x,z)
  if x>0 and x<96 and z>0 and z<96 then return (z-1)*96+x end
end
function Sim.xy(id) return (id-1)%96+1,math.floor((id-1)/96)+1 end
local shore,farm,woods=40,46,59
local view={}
function view.host_tile(id)
  local x=Sim.xy(id)
  if x<shore then return {terrain="water",h=0,water_class="sea"} end
  if x<farm then return {terrain="water",h=0,water_class="sea",coastal_water=true} end
  if x<woods then return {terrain="grass",h=0} end
  return {terrain="grass",h=1,wood=true}
end
function view.host_record(name,id)
  local x=Sim.xy(id)
  if name=="stock_farm_fields" and x>=farm and x<woods then return {} end
end
function view.surface(id) return view.host_tile(id).h+.5 end
local V=Vfile(core,Sim,view,media)
local Audience=dofile(mod.."/ambient_audience.lua")
for _,entry in ipairs({{"sea","bl_water0.png"},{"grass","bl_grass1.png"},{"soil","bl_grass3.png"}}) do
  core.register_node(":".."wqa:"..entry[1],{description=entry[1],tiles={entry[2]},pointable=false,walkable=false})
end
for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
core.set_mapgen_setting("mg_name","singlenode",true)
local origins={
  {x=62,y=11,z=86},{x=91,y=10,z=103},{x=112,y=10,z=77},
}
local species={"whale","porpoise","seagull","eagle","fox"}
local joining=false
local function place()
  local vm=core.get_voxel_manip()
  local aa,bb=vm:read_from_map({x=28,y=-1,z=35},{x=167,y=2,z=158})
  local area=VoxelArea:new({MinEdge=aa,MaxEdge=bb})
  local buffer=vm:get_data()
  local sea,field,land=core.get_content_id("wqa:sea"),core.get_content_id("wqa:soil"),core.get_content_id("wqa:grass")
  for x=28,167 do
    local i=math.floor((x+.5)/2)
    local h=i>=woods and 1 or 0
    local node=i<farm and sea or i<woods and field or land
    for z=35,158 do buffer[area:index(x,h,z)]=node end
  end
  vm:set_data(buffer);vm:write_to_map()
end
local function actors()
  local found={}
  for _,o in ipairs(core.get_objects_inside_radius({x=97,y=5,z=90},100)) do
    local e=o:get_luaentity()
    local kind=e and e.name:match("^luanttd_core:wildlife_(.+)$")
    if kind then
      assert(o:get_properties().mesh:find("bl_wildlife_"..kind,1,true))
      found[kind]=o
    end
  end
  return found
end
core.register_on_joinplayer(function(p)
  if joining then return end
  joining=true
  local n=p:get_player_name()
  p:set_physics_override({gravity=0,speed=0,jump=0})
  p:set_sky({type="plain",base_color="#a7cfed",clouds=false})
  for _,k in ipairs({"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"}) do
    p:hud_set_flags({[k]=false})
  end
  p:override_day_night_ratio(1)
  p:set_pos(origins[1])
  -- Use the real connected player's camera API rather than a synthetic
  -- view vector. A turn should defer then permit the same actor's exit.
  local target={x=origins[1].x+13,y=origins[1].y+1.5,z=origins[1].z}
  local retiring={}
  p:set_look_horizontal(-math.pi/2);p:set_look_vertical(0)
  local watching=Audience.capture({p},V.enabled)
  for _=1,20 do assert(not Audience.retire(retiring,watching,target,80,.20)) end
  p:set_look_horizontal(math.pi/2)
  local away=Audience.capture({p},V.enabled)
  for _=1,4 do assert(not Audience.retire(retiring,away,target,80,.20)) end
  assert(Audience.retire(retiring,away,target,80,.20))
  core.log("action","WILDLIFE_NATIVE_VIEW_PASS signed camera direction, visible retirement deferred, exit after sustained look-away")
  core.emerge_area({x=28,y=-1,z=35},{x=167,y=20,z=158},function(_,_,remaining)
    if remaining~=0 then return end
    place()
    -- Sample all three habitats deterministically, with the real viewer
    -- identity, then pause the scene for five separate camera elevations.
    local viewers={}
    for _,origin in ipairs(origins) do
      viewers[#viewers+1]={get_pos=function()return origin end,get_player_name=function()return n end,
        get_meta=function()return p:get_meta() end}
    end
    local snapshots,observed={},{}
    local function remember(kind,o)
      snapshots[kind]={at=o:get_pos(),rot=o:get_rotation()}
    end
    for _=1,500 do
      V.step(.20,viewers)
      for kind,o in pairs(actors()) do
        local at=o:get_pos()
        local r=o:get_rotation()
        if kind=="whale" then
          if at.y<-.44 then observed.whale_dive=true end
          if at.y>.36 and at.y<.42 and math.abs(r.x)<.07 then remember(kind,o) end
          if at.y>1.30 then observed.whale_breach=true end
        elseif kind=="porpoise" then
          if at.y<.09 then observed.porpoise_swim=true end
          if at.y>1.13 then remember(kind,o) end
        else
          if kind=="fox" then
            local size=o:get_properties().visual_size
            assert(size.x==.5 and size.y==.5)
          end
          remember(kind,o)
        end
      end
      local complete=true
      for _,kind in ipairs(species) do if not snapshots[kind] then complete=false end end
      if complete and observed.whale_dive and observed.whale_breach and observed.porpoise_swim then break end
    end
    assert(observed.whale_dive and observed.whale_breach and observed.porpoise_swim,"missing native swim poses")
    local found,still={},{}
    for _,kind in ipairs(species) do
      local shot=assert(snapshots[kind],"missing native "..kind)
      -- The original may have completed its complete encounter before
      -- all five views were captured. Replay its measured pose using
      -- the same real registered mesh, outside the production actor list.
      local o=assert(core.add_entity(shot.at,"luanttd_core:wildlife_"..kind))
      found[kind]=o
      still[#still+1]=o
    end
    local function aim(i)
      local kind=species[i]
      if not kind or not core.get_player_by_name(n) then return end
      local shot=snapshots[kind]
      local at=shot.at
      found[kind]:set_pos(at)
      found[kind]:set_rotation(shot.rot)
      local d=kind=="whale" and 5 or kind=="porpoise" and 2.1 or 1.8
      local dx,dz=d,-.8*d
      local up=kind=="whale" and 2.8 or kind=="porpoise" and .8 or -.15
      local pos={x=at.x+dx,y=at.y+up,z=at.z+dz}
      local dy=at.y-pos.y-(p:get_properties().eye_height or 1.625)
      p:set_look_horizontal(math.atan2(dx,-dz))
      p:set_look_vertical(math.atan2(-dy,math.sqrt(dx^2+dz^2)))
      p:set_pos(pos)
      core.log("action","WILDLIFE_NATIVE_FRAME "..kind)
    end
    for i=1,#species do core.after(4.2*(i-1),aim,i) end
    core.after(4.2*#species,function()
      for _,o in ipairs(still) do o:remove() end
      assert(core.registered_chatcommands.candy.func(n) and not V.enabled(p))
      assert(V.count()==0)
      core.log("action","WILDLIFE_NATIVE_PASS five real meshes, natural swim and leap poses, half-size fox; /candy hides the scene")
    end)
  end)
end)
