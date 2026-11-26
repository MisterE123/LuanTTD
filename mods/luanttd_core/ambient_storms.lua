-- Player-local cosmetic weather: up to four private, unsaved volumes per viewer.
-- Clouds own no nodes, collision, weather state or simulation rules.
local M={}
local period,duration=257,24
local entity="luanttd_core:voxel_cloud"
local styles={"wisp","storm","shower"}
local wind_x,wind_z=.56,.26
local rain="bl_storm_rain.png"
local bolt="bl_storm_bolt.png"
local function pos(x,y,z) return {x=x,y=y,z=z} end
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function cloud_art(kind)
  return "bl_voxel_cloud_"..kind..".obj",{"bl_voxel_cloud_"..kind..".png"}
end

function M.start(core,enabled,clock)
  if not (core.register_entity and core.add_entity and core.add_particle and core.add_particlespawner) then return end
  -- The optional test clock does not affect world or player settings.
  local viewers,age,acc,cursor={},period-60,0,0
  local mesh,textures=cloud_art("storm")
  core.register_entity(entity,{
    initial_properties={visual="mesh",mesh=mesh,textures=textures,visual_size={x=10,y=10,z=10},
      physical=false,pointable=false,collide_with_objects=false,static_save=false,
      shaded=false,backface_culling=true},
    on_activate=function(self,name)
      if name=="" or not core.get_player_by_name(name) or not self.object.set_observers then
        self.object:remove();return
      end
      self.object:set_observers({[name]=true})
    end,
  })
  local function remove(c)
    if not c then return end
    for _,part in pairs(c.parts) do
      if part.ref:get_pos() then part.ref:remove() end
    end
    c.parts={}
  end
  local function volume(c,name,key,kind,at,width)
    local part=c.parts[key]
    if not part or not part.ref:get_pos() then
      local obj=core.add_entity(at,entity,name)
      if not obj or not obj:get_pos() then return end
      part={ref=obj}
      c.parts[key]=part
      local model,tex=cloud_art(kind)
      obj:set_properties({mesh=model,textures=tex})
    else
      part.ref:move_to(at,true)
    end
    if width and width~=part.width then
      part.width=width
      part.ref:set_properties({visual_size={x=width,y=10,z=10}})
    end
    return part
  end
  local function cell(p,cycle)
    local at=p:get_pos()
    local aim=p:get_look_dir()
    local length=math.sqrt(aim.x^2+aim.z^2)
    if not at or length<.05 then return end
    local x,z=aim.x/length,aim.z/length
    return {x=at.x+x*55-z*5,z=at.z+z*55+x*5,
      y=at.y+clamp(aim.y*38,8,22),cycle=cycle,next_rain=.5,parts={}}
  end
  local function lightning(name,c,second)
    -- Two isolated strikes. No cloud opacity, world exposure or sky flash.
    local shift=second and 5 or -4
    local west=c.x+shift
    for i=0,16 do
      local x=west+math.floor(i/3)*.64-((math.floor(i/2)%2)*1.02)
      local y=c.y-2-i*.75
      local function segment(x,y,z,size,glow)
        core.add_particle({playername=name,pos=pos(x,y,z),expirationtime=.60,size=size,
          texture={name=bolt,alpha_tween={1,1,0},blend="alpha"},glow=glow,collisiondetection=false})
      end
      segment(x,y,c.z,10,13)
      if i>=6 and i<=10 then segment(x-(i-5)*.48,y+.38,c.z+.4,6.2,11) end
    end
  end
  local function update(p,phase,cycle)
    local name=p:get_player_name()
    local anchor=viewers[name]
    if not enabled(p) then remove(anchor);viewers[name]=nil;return end
    if not anchor or anchor.cycle~=cycle then
      remove(anchor)
      anchor=cell(p,cycle)
      if not anchor then return end
      viewers[name]=anchor
    end
    local c=pos(anchor.x+wind_x*phase,anchor.y,anchor.z+wind_z*phase)
    local at=p:get_pos()
    if not at then remove(anchor);return end
    local dx,dz=at.x-c.x,at.z-c.z
    local d2=dx*dx+dz*dz
    if d2<34^2 or d2>88^2 or math.abs(at.y-c.y)>35 then remove(anchor);return end
    local kind=styles[cycle%3+1]
    if not volume(anchor,name,"base",kind,c) then return end
    if kind=="wisp" then return end
    local storm=kind=="storm"
    if storm then
      -- Feeders rise through the shelf before the top spreads downwind.
      -- Stage changes resize only the anvil, not its palette or visibility.
      local rise=clamp(phase/10,0,1)
      local spread=math.floor(clamp((phase-2)/2.6,0,6))
      local dissipate=clamp((phase-19)/5,0,1)
      volume(anchor,name,"feeder_left","storm_feeder",
        pos(c.x-6,c.y-1+rise*4.5,c.z+2))
      volume(anchor,name,"feeder_right","storm_feeder",
        pos(c.x+3,c.y-2+rise*3.4,c.z-2.5))
      volume(anchor,name,"anvil","storm_anvil",
        pos(c.x-1+phase*.18+dissipate*3,c.y+4.1+rise*1.8,c.z-1),
        7+spread*.55)
    end
    local fade=clamp(math.min(phase,duration-phase)/3,0,1)
    if phase>=anchor.next_rain then
      anchor.next_rain=phase+.88
      local span=storm and 10 or 8
      core.add_particlespawner({playername=name,amount=math.floor((storm and 94 or 44)*fade),time=.75,
        minpos=pos(c.x-span,c.y-3,c.z-4),maxpos=pos(c.x+span,c.y+.3,c.z+4),
        minvel=pos(.45,-13,.3),maxvel=pos(.9,-10,.65),
        minexptime=.35,maxexptime=1.0,minsize=3.1,maxsize=4.7,
        texture={name=rain,alpha_tween={1,.68,0}},glow=4,vertical=true,collisiondetection=false})
    end
    if storm and phase>=8 and phase<14 and not anchor.first then
      anchor.first=true;lightning(name,c,false)
    elseif storm and phase>=17 and phase<22 and not anchor.second then
      anchor.second=true;lightning(name,c,true)
    end
  end
  core.register_on_leaveplayer(function(p)
    local name=p:get_player_name()
    remove(viewers[name]);viewers[name]=nil
  end)
  core.register_globalstep(function(dt)
    if clock then
      local initial=clock()
      if not initial then return end
      age,clock=initial,nil
    end
    age=age+dt
    local phase=age%period
    if phase>=duration then
      for _,c in pairs(viewers) do remove(c) end
      viewers={};acc=0
      return
    end
    acc=acc+dt
    if acc<.25 then return end
    acc=acc%.25
    local players=core.get_connected_players()
    if #players==0 then return end
    for i=0,math.min(7,#players-1) do
      update(players[(cursor+i)%#players+1],phase,math.floor(age/period))
    end
    cursor=(cursor+8)%#players
  end)
end
return M
