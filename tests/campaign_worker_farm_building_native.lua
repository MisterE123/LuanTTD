-- Real farm, renderer and Luanti graphics; not an isolated model scene.
local function farm_building_native()
  local p=core.get_player_by_name("FarmBuildingQA")
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.2,farm_building_native);return
  end
  local s=assert(OwnerCheckpoint.read())
  local farm
  for _,i in pairs(s.stock_farm_industries or {}) do
    -- This street-level camera plan is for the original 3×3 yard;
    -- the alternate full-size layouts have their own native proof.
    if i.kind=="farm" and not i.removed and (i.layout or 0)==0 and (not farm or i.id<farm.id) then farm=i end
  end
  assert(farm,"No original 3×3 farm in the ordinary worker-generated world")
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
  local function pasture()
    aim({"paddocks",7.0,1.45,3.75,4.47,.18,3.53})
    core.log("action","FARM_BUILDING_QA paddocks")
    local starts,moved,stepped={},{},{}
    local function inspect(sample)
      local count=0
      for _,o in ipairs(core.get_objects_inside_radius({x=fx+4.4,y=level,z=fz+3.5},3)) do
        local e=o:get_luaentity()
        local kind=e and e.name:match("^luanttd_core:farm_livestock_(.+)$")
        if kind then
          local p=o:get_pos()
          local x,z=p.x-fx,p.z-fz
          local i=z<2.5 and 1 or z<3.5 and 2 or x>4.55 and 3 or z<4.55 and 4 or 5
          assert(math.abs(p.y-level-.026)<.003 and x>3.88 and x<5.03)
          assert(i<=3 and kind~="pig" or i>=4 and kind=="pig")
          assert(z>1.98 and z<5.08 and not (z>3.35 and z<3.68),"escaped livestock")
          if not starts[i] then starts[i]=p end
          if vector.distance(p,starts[i])>.11 then moved[i]=true end
          if (o:get_properties().mesh or ""):match("_step_[ab]%.obj$") then stepped[i]=true end
          count=count+1
        end
      end
      assert(count==5,"worker farm should show three cattle and two pigs")
      if sample<19 then core.after(.24,function()inspect(sample+1)end)
      else
        for i=1,5 do assert(moved[i] and stepped[i],"livestock did not visibly wander and animate: "..i) end
        core.log("action","PASS NATIVE FARM LIVESTOCK: three cattle and two pigs wandered within the two painted pens")
        core.log("action","PASS NATIVE WORKER FARM BUILDINGS: all 9 stock pieces and five gameplay camera angles")
      end
    end
    core.after(.55,function()inspect(1)end)
  end
  local function walk(n)
    if n>#views then
      pasture()
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
