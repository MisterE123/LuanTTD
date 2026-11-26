-- Player-local presentation for the shared cosmetic weather field.
local M={}
local dir=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/"
local Field=dofile(dir.."ambient_weather_field.lua")
local Wind=dofile(dir.."ambient_wind.lua")
local entity="luanttd_core:voxel_cloud"
local rain,bolt,spray="bl_weather_rain_streak.png","bl_storm_bolt.png","bl_weather_spray.png"
local floor,abs,sqrt=math.floor,math.abs,math.sqrt
local function pos(x,y,z) return {x=x,y=y,z=z} end
local function cap(n) return math.max(0,math.min(1,n)) end
local function near(a,b,k) return a+(b-a)*k end
local function art(kind)
  return "bl_voxel_cloud_"..kind..".obj","bl_voxel_cloud_"..kind..".png"
end

function M.start(core,enabled,options)
  if not (core.register_entity and core.add_entity and core.add_particle and core.add_particlespawner) then return end
  options=options or {}
  local viewers,age,acc,cursor={},91,0,0
  local model,texture=art("bank")
  core.register_entity(entity,{
    initial_properties={visual="mesh",mesh=model,textures={texture},visual_size=pos(10,10,10),
      physical=false,pointable=false,collide_with_objects=false,static_save=false,
      shaded=false,backface_culling=true,use_texture_alpha=true,is_visible=false},
    on_activate=function(self,name)
      if name=="" or not core.get_player_by_name(name) or not self.object.set_observers then
        self.object:remove();return
      end
      self.object:set_observers({[name]=true})
    end,
  })
  local function clear(c)
    for _,part in pairs(c.parts) do if part.ref:get_pos() then part.ref:remove() end end
    c.parts={}
  end
  local function drop(name)
    local v=viewers[name]
    if v then for _,rec in pairs(v.cells) do clear(rec) end end
    viewers[name]=nil
  end
  local function volume(c,name,key,kind,at,scale,alpha,shade,yaw)
    local p=c.parts[key]
    local n=floor(cap(alpha)*24+.5)
    if n==0 then
      if p and p.ref:get_pos() then p.ref:remove() end
      c.parts[key]=nil;return
    end
    local x,y,z=floor(scale.x*8+.5),floor(scale.y*8+.5),floor(scale.z*8+.5)
    local tint=floor(cap(shade)*10+.5)
    local spec=n..":"..tint..":"..x..":"..y..":"..z
    if not p or not p.ref:get_pos() then
      local obj=core.add_entity(at,entity,name)
      if not obj or not obj:get_pos() then return end
      p={ref=obj};c.parts[key]=p
      if obj.set_yaw then obj:set_yaw(yaw) end
    else p.ref:move_to(at,true) end
    if p.spec~=spec then
      local mesh,tex=art(kind)
      if tint>0 then
        tex=tex..("^[multiply:#%02x%02x%02x"):format(255-tint*11,255-tint*10,255-tint*7)
      end
      if n<24 then tex=tex..("^[opacity:%d"):format(floor(n*255/24)) end
      p.ref:set_properties({mesh=mesh,textures={tex},visual_size=pos(x/8,y/8,z/8),is_visible=true})
      p.spec=spec
    end
  end
  local function ground(x,z,fallback)
    local y=options.ground and options.ground(x,z)
    return y or fallback or 0
  end
  local function lighting(name,c,side)
    local x,z=c.x+side*(4+c.size),c.z-2.5
    local top,low=c.y+2,ground(x,z,c.base)+.2
    local length=math.max(3,top-low)
    for i=0,15 do
      local px=x+floor(i/3)*.56-((floor(i/2)%2)*1.04)
      local py=top-i*length/15
      local function seg(px,py,pz,size,glow)
        core.add_particle({playername=name,pos=pos(px,py,pz),expirationtime=.46,size=size,
          texture={name=bolt,alpha_tween={1,.93,0},blend="alpha"},glow=glow,collisiondetection=false})
      end
      seg(px,py,z,math.max(6,length*.85),13)
      if i>=5 and i<10 then seg(px-(i-4)*.56,py+.32,z+.25,5.8,11) end
    end
  end
  local function show(p,rec,c,builder,dt,budget)
    local name=p:get_player_name()
    local at=p:get_pos()
    local wx,wz=Wind.sample(c.x,c.z,age)
    local bx,bz,clearance=Field.builder_avoid(at.x,at.z,c,builder,wx,wz)
    -- Crossing the cell's map coordinates high overhead is not an
    -- approach. This is one per-view clearance, never a world gust.
    local deck_y=(rec.ground or ground(c.x,c.z))+5.0+1.4*c.size+c.growth*1.5
    local proximity=1-Field.smooth((abs(at.y-deck_y)-12)/16)
    bx,bz,clearance=bx*proximity,bz*proximity,1-(1-clearance)*proximity
    local k=1-math.exp(-dt/1.7)
    rec.dx,rec.dz=near(rec.dx,bx,k),near(rec.dz,bz,k)
    rec.clear=near(rec.clear,clearance,k)
    local px,pz=c.x+rec.dx,c.z+rec.dz
    local gy=ground(px,pz,rec.ground)
    local g1,g2=ground(px+12,pz+2,gy),ground(px-12,pz-2,gy)
    local target=.38*gy+.62*math.max(gy,g1,g2)
    rec.ground=rec.ground and near(rec.ground,target,1-math.exp(-dt/3)) or target
    local a=c.alpha*rec.fade*rec.clear
    local spread=.81+.21*c.alpha
    local w=c.size*spread
    local growth=c.growth
    local altitude=rec.ground+5.0+1.4*c.size+growth*1.5
    local yaw=-.21+c.skew
    local function place(key,kind,dx,dy,dz,sx,sy,sz,alpha,shade)
      volume(rec,name,key,kind,pos(px+dx,altitude+dy,pz+dz),pos(sx,sy,sz),alpha,shade,yaw)
    end
    place("deck","bank",0,0,0,12.6*w,8+growth*3.1,11.3*w,a,growth*.85+c.rain*.22)
    place("tail","wisp",11*w,-1,4.5,7.6*w,5.7,7.9*w,a*.62*(1-.4*growth),growth*.36)
    -- The connected crown rises from the parent deck, not a detached
    -- cap on a narrow stalk. Its sheared edge spreads downwind.
    place("tower","column",-.7*w,.3+1.1*growth,.15,13.0*w,3.2+7.0*growth,11.0*w,math.min(a,a*growth*1.25),growth*.68)
    -- The lower bank fades independently. Hug the sampled contours and
    -- spread horizontally rather than dropping blue rain fog into water.
    place("mist","mist",-6*w,ground(px-7,pz+2,gy)+1.55-altitude,2.4,12.7*w,6.2,9*w,a*c.mist*.82,.06)
    if c.rain*a>.10 and age>=rec.next_rain and budget>0 then
      rec.next_rain=age+.87
      local amount=math.min(budget,floor(108*c.rain*a+.5))
      local span=10.5*w
      core.add_particlespawner({playername=name,amount=amount,time=.74,
        minpos=pos(px-span,altitude-1,pz-4),maxpos=pos(px+span,altitude+1.2,pz+4),
        minvel=pos(wx*.34,-14,wz*.34),maxvel=pos(wx*.9+.1,-10,wz*.9+.28),
        minexptime=.56,maxexptime=math.min(1.14,.58+(altitude-gy)/21),minsize=4.2,maxsize=6.6,
        texture={name=rain,alpha_tween={.80,.65,0}},glow=1,vertical=true,collisiondetection=false})
      budget=budget-amount
      local wet=math.min(budget,floor(15*c.rain*a))
      if wet>1 then
        core.add_particlespawner({playername=name,amount=wet,time=.48,
          minpos=pos(px-8,gy+.11,pz-3),maxpos=pos(px+8,gy+.25,pz+3),
          minvel=pos(-.1,.18,-.12),maxvel=pos(.62,.54,.44),minexptime=.20,maxexptime=.46,
          minsize=1.5,maxsize=2.8,texture={name=spray,alpha_tween={.18,.54,0}},glow=0,collisiondetection=false})
        budget=budget-wet
      end
    end
    local t=c.time
    if a*growth>.36 then
      local spot={x=px,y=altitude,z=pz,size=w,base=rec.ground}
      -- The cloud's brightness never flashes. Only the fork is emissive.
      if not rec.first and t>=74 and t<79 then rec.first=true;lighting(name,spot,-1)
      elseif not rec.second and t>=99 and t<104 then rec.second=true;lighting(name,spot,1) end
    end
    return budget
  end
  local function update(p)
    local name=p:get_player_name()
    local at=p:get_pos()
    if not at or not enabled(p) then drop(name);return end
    local v=viewers[name] or {cells={},last=age-.35}
    viewers[name]=v
    local dt=math.min(age-v.last,1.5);v.last=age
    local candidates=(options.cells or Field.cells)(at.x,at.z,age,Wind.prevailing,options.seed and options.seed() or 0)
    local wanted,count={},0
    for _ in pairs(v.cells) do count=count+1 end
    for i=1,math.min(3,#candidates) do
      local c=candidates[i]
      wanted[c.key]=c
      if not v.cells[c.key] and count<4 then
        v.cells[c.key]={parts={},dx=0,dz=0,clear=1,fade=0,next_rain=age,weather=c}
        count=count+1
      end
    end
    local builder=not options.spectator or not options.spectator(p)
    local budget=146
    local keys={}
    for k in pairs(v.cells) do keys[#keys+1]=k end
    table.sort(keys)
    for _,key in ipairs(keys) do
      local r,c=v.cells[key],wanted[key]
      if c then r.weather=c end
      r.fade=cap(r.fade+(c and .41 or -.3)*dt)
      if not c and r.fade<=.01 then clear(r);v.cells[key]=nil
      else budget=show(p,r,r.weather,builder,dt,budget) end
    end
  end
  core.register_on_leaveplayer(function(p) drop(p:get_player_name()) end)
  core.register_globalstep(function(dt)
    if options.clock then
      local fixed=options.clock()
      if fixed==nil then return end
      age=fixed
    else age=age+dt end
    acc=acc+dt
    if acc<.28 then return end
    acc=acc%.28
    local players=core.get_connected_players()
    if #players==0 then return end
    local n=math.min(8,#players)
    for i=0,n-1 do update(players[(cursor+i)%#players+1]) end
    cursor=(cursor+n)%#players
  end)
end
return M
