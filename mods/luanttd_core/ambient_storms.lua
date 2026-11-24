-- Player-local weather scenery. It owns neither nodes, entities nor simulation state.
local M={}
local period,duration=257,24
local cloud="bl_storm_cloud.png"
local rain="bl_storm_rain.png"
local bolt="bl_storm_bolt.png"
local mist="bl_storm_mist.png"
local function pos(x,y,z) return {x=x,y=y,z=z} end
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end

function M.start(core,enabled)
  if not core.add_particle or not core.add_particlespawner then return end
  local viewers,age,acc,cursor={},period-60,0,0
  local function particle(name,at,size,life,tex,glow,velocity)
    core.add_particle({playername=name,pos=at,velocity=velocity or pos(0,0,0),expirationtime=life,
      size=size,texture={name=tex,alpha_tween={1,1,0},blend="alpha"},
      glow=glow,collisiondetection=false})
  end
  local function cell(p)
    local at=p:get_pos()
    local aim=p:get_look_dir()
    local length=math.sqrt(aim.x^2+aim.z^2)
    if length<.05 then return end
    local x,z=aim.x/length,aim.z/length
    return {x=at.x+x*50-z*10,z=at.z+z*50+x*10,
      y=at.y+clamp(aim.y*42,5,19)}
  end
  local function lightning(name,c,second)
    -- Stepped squares read as voxel lightning against the local cloud;
    -- no screen tint, exposure change, sky flash or repeated flicker.
    local shift=second and 6 or -5
    local west=c.x+shift
    for i=0,16 do
      local x=west+math.floor(i/3)*.64-((math.floor(i/2)%2)*1.02)
      local y=c.y-2-i*.75
      particle(name,pos(x,y,c.z),10.0,.67,bolt,13)
      if i>=6 and i<=10 then
        particle(name,pos(x-(i-5)*.48,y+.38,c.z+.4),6.2,.67,bolt,11)
      end
    end
  end
  local function update(p,phase,cycle)
    local name=p:get_player_name()
    if not enabled(p) then return end
    local c=viewers[name]
    if not c or c.cycle~=cycle then
      c=cell(p)
      if not c then return end
      c.cycle=cycle;viewers[name]=c
    end
    local at=p:get_pos()
    local dx,dz=at.x-c.x,at.z-c.z
    local d2=dx*dx+dz*dz
    if d2<34^2 or d2>88^2 or math.abs(at.y-c.y)>35 then return end
    local kind=cycle%3
    local opacity=math.floor(clamp(math.min(phase,duration-phase)/5,0,1)*205)
    if opacity<12 then return end
    if kind==0 then
      -- Thin drifting wisps in the far scenery; never replace world fog.
      local alpha=math.floor(opacity*.56)
      for i=-1,1 do
        particle(name,pos(c.x+i*5,c.y-6+math.abs(i),c.z+i*3),100,1.3,
          mist.."^[opacity:"..alpha,4,pos(.9,.1,.45))
      end
      return
    end
    local storm=kind==1
    if not storm then opacity=math.floor(opacity*.58) end
    local tex=cloud..(storm and "" or "^[brighten").."^[opacity:"
    particle(name,pos(c.x+2,c.y+1.2,c.z-3),145,1.0,
      tex..math.floor(opacity*.70),2)
    particle(name,pos(c.x,c.y,c.z),200,1.0,tex..opacity,2)
    core.add_particlespawner({playername=name,amount=storm and 110 or 48,time=.75,
      minpos=pos(c.x-10,c.y-4,c.z-7),maxpos=pos(c.x+10,c.y+.5,c.z+7),
      minvel=pos(.45,-13,.3),maxvel=pos(.9,-10,.65),
      minexptime=.35,maxexptime=1.0,minsize=3.3,maxsize=5.1,
      texture={name=rain,alpha_tween={1,.68,0}},glow=4,vertical=true,
      collisiondetection=false})
    if not storm then return end
    if phase>=17 then
      if not c.second and (not c.first or phase-c.first>=6) then
        c.second=true;lightning(name,c,true)
      end
    elseif phase>=8 and not c.first then
      c.first=phase;lightning(name,c,false)
    end
  end
  core.register_on_leaveplayer(function(p) viewers[p:get_player_name()]=nil end)
  core.register_globalstep(function(dt)
    age=age+dt
    local phase=age%period
    if phase>=duration then
      if next(viewers) then viewers={} end
      acc=0
      return
    end
    acc=acc+dt
    if acc<.97 then return end
    acc=acc%.97
    local players=core.get_connected_players()
    if #players==0 then return end
    for i=0,math.min(7,#players-1) do
      update(players[(cursor+i)%#players+1],phase,math.floor(age/period))
    end
    cursor=(cursor+8)%#players
  end)
end
return M
