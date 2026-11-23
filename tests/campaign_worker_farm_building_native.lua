-- Real farm, renderer and Luanti graphics; not an isolated model scene.
local function farm_building_native()
  local p=core.get_player_by_name("FarmBuildingQA")
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.2,farm_building_native);return
  end
  local s=assert(OwnerCheckpoint.read())
  local farm
  for _,i in pairs(s.stock_farm_industries or {}) do
    if i.kind=="farm" and not i.removed and (not farm or i.id<farm.id) then farm=i end
  end
  assert(farm,"No farm in the ordinary worker-generated world")
  local fx,fz=2*(farm.x+1),2*(farm.z+1)
  local level=assert(s.tiles[Sim.id(farm.x+1,farm.z+1)]).h+.5
  local TerrainProbe=dofile(mod.."/openttd/terrain.lua")
  -- Stock industry placement requires level footprint cells, so verify
  -- both sides from the uneven surrounding terrain, not a fictitious slope
  -- under a building (the port never accepts one).
  for dx=0,2 do for dz=0,2 do
    assert(TerrainProbe.tile(s.corner_grid,farm.x+1+dx,farm.z+1+dz)==0)
  end end
  local views={
    {"survey",7.9,4.5,8.9,2.7,.65,2.3},
    {"barn",5.4,.10,3.15,4.48,.75,.21},
    {"silos",2.0,.17,2.18,.35,.88,.55},
    {"farmhouse",3.85,-.45,4.48,2.80,.60,2.03},
    {"rear",3.0,1.8,-4.60,3.81,.67,1.01},
  }
  local function aim(v)
    local _,x,y,z,tx,ty,tz=unpack(v)
    p:set_pos({x=fx+x,y=level+y,z=fz+z})
    local dx,dy,dz=tx-x,ty-y-1.47,tz-z
    p:set_look_horizontal(math.atan2(-dx,dz))
    p:set_look_vertical(-math.atan2(dy,math.sqrt(dx*dx+dz*dz)))
  end
  local function visible()
    for dx=0,2 do for dz=0,2 do
      local node=core.get_node({x=fx+2*dx,y=level+.5,z=fz+2*dz})
      if node.name~=("luanttd_core:industry_farm_%d_%d"):format(dx,dz) then return false end
    end end
    return true
  end
  local function walk(n)
    if n>#views then
      core.log("action","PASS NATIVE WORKER FARM BUILDINGS: all 9 stock pieces and five gameplay camera angles")
      return
    end
    assert(visible(),"Farm footprint unmaterialized")
    local v=views[n];aim(v)
    core.log("action","FARM_BUILDING_QA "..v[1])
    core.after(3.4,function() walk(n+1) end)
  end
  local function ready(n)
    if visible() then walk(1)
    elseif n<70 then core.after(.2,function()ready(n+1)end)
    else error("Worker did not paint the full stock farm footprint") end
  end
  core.set_timeofday(.5)
  aim(views[1]);ready(1)
end
core.after(.2,farm_building_native)
