-- The dry beach, channel, crop row and stock timber bridge use the production renderer.
return function(api)
  local m=core.get_modpath("luanttd_core")
  local S,Sim,R,W=api.s,api.Sim,api.render,api.world
  local T=dofile(m.."/openttd/terrain.lua")
  local function ht(x,z) return (x<=12 or x>=17) and 1 or 0 end
  S.speed=0
  -- This temporary terrain replacement is not a live factory. Remove the
  -- detached winding-reel visuals from the part of the map being painted.
  for _,ind in pairs(S.stock_coal_industries or {}) do
    if ind.kind=="coal_mine" and ind.x+2>=8 and ind.x+2<=22 and ind.z+2>=8 and ind.z+2<=22 then ind.removed=true end
  end
  S.corner_grid.levels=T.new(Sim.W,Sim.H,ht).levels
  local dirty={}
  for z=8,22 do for x=8,22 do
    local id=assert(Sim.id(x,z))
    local mask,base=T.tile(S.corner_grid,x,z)
    local water=x>=12 and x<=16 and z~=17
    S.tiles[id]={terrain=water and "water" or "grass",water_class=water and "sea" or nil,
      coastal_water=water and mask~=0 or nil,h=base,variant=0}
    dirty[#dirty+1]=id
    if z==17 then
      S.stock_farm_fields[id]={slope=mask,base=base,variant=3}
    else S.stock_farm_fields[id]=nil end
  end end
  S.stock_farm_fields[Sim.id(9,19)]={slope=0,base=1,variant=3,fences={[2]=3}}
  S.tiles[Sim.id(11,19)].house=true
  local ok,why=Sim.road_bridge(S,"WalkQA",Sim.id(12,11),Sim.id(16,11),0)
  assert(ok,why)
  local bridge=S.stock_road_bridges[S.tiles[Sim.id(12,11)].road_bridge_id]
  assert(bridge.deck and #bridge.middle>0)
  local pusher
  local phases={}
  local function sample(p)
    local v=p:get_pos()
    local a=W.avatar_state(p)
    if a and not a.leaving then
      if phases.phase=="shore" then
        if a.swimming and v.x>26 and math.abs(v.y-.32)<.1 then phases.floated=true end
        if phases.floated and not a.swimming and v.x<24.8 and v.y>.63 then phases.climbed=true end
      elseif phases.phase=="bridge" then
        if not a.swimming and v.x>26.5 and v.x<33 and math.abs(v.y-(bridge.deck+.5))<.13 then phases.deck=true end
        if phases.deck and not a.swimming and v.x>34.5 and v.y>1.43 then phases.bridge_exit=true end
      elseif phases.phase=="field" then
        if not a.swimming and v.x>23.6 and v.x<25.4 and v.y>.56 and v.y<1.49 then phases.field_grade=true end
        if phases.field_grade and not a.swimming and v.x<23.6 and v.y>1.43 then phases.field_up=true end
      end
    end
    return v,a
  end
  local elapsed=0
  core.register_globalstep(function(dt)
    elapsed=elapsed+dt
    if elapsed<.22 then return end
    elapsed=0
    if pusher then sample(pusher) end
  end)
  local function setup(p,tag)
    assert(not W.avatar_state(p),"exit avatar before resetting")
    local x,z,yaw
    if tag=="shore" then x,z,yaw=24.55,28.5,-math.pi/2
    elseif tag=="bridge" then x,z,yaw=22.0,22.5,-math.pi/2
    elseif tag=="field" then x,z,yaw=25.7,34.5,math.pi/2
    elseif tag=="fence" then x,z,yaw=18.35,38.5,-math.pi/2
    else error(tag) end
    p:set_pos({x=x,y=5,z=z});p:set_look_horizontal(yaw);p:set_look_vertical(1.567)
    phases.phase=tag
  end
  core.register_chatcommand("swimprobe",{func=function(n,tag)
    local p=assert(core.get_player_by_name(n))
    if tag=="shore" or tag=="bridge" or tag=="field" or tag=="fence" then setup(p,tag);return true end
    local v,a=sample(p)
    local flags=p:hud_get_flags()
    core.log("action",("COAST_SWIM %s %.3f %.3f %.3f swimming=%s %s"):format(tag,v.x,v.y,v.z,tostring(a and a.swimming),core.serialize(phases):gsub("%s","")))
    if tag=="house" then for y=1,3 do core.log("action", "QA house node "..y.." "..core.get_node({x=22,y=y,z=38}).name) end end
    if tag=="float" then assert(a and a.swimming and phases.floated,"did not float in channel")
    elseif tag=="climb" then assert(a and not a.swimming and phases.climbed,"did not climb rocky coast")
    elseif tag=="span" then assert(a and not a.swimming and phases.deck and phases.bridge_exit,"did not cross timber bridge")
    elseif tag=="crop" then assert(a and not a.swimming and phases.field_grade and phases.field_up,"did not climb plowed field")
    elseif tag=="barrier" then
      assert(a and v.x>19.10 and v.x<19.49,"walking must stop just before the mesh-aligned fence")
    elseif tag=="jumped" then
      assert(a and v.x>20.15 and v.x<21.95,"jump must clear the fence")
    elseif tag=="house" then
      assert(a and v.x>21.65 and v.x<22.12,"walking must stop at the mesh-aligned house")
    elseif tag=="returned" then
      assert(not a and flags.hotbar and p:get_properties().eye_height>1 and math.abs(v.x-25.7)<.05)
    else error(tag) end
    core.log("action","COAST_SWIM_PASS "..tag)
    return true
  end})
  core.register_on_joinplayer(function(p)
    if p:get_player_name()~="WalkQA" then return end
    core.emerge_area({x=15,y=-1,z=15},{x=45,y=5,z=45},function(_,_,left)
      if left~=0 then return end
      core.after(.3,function()
        R.update(dirty)
        local b=core.registered_nodes[core.get_node({x=28,y=bridge.deck,z=22}).name]
        local field=core.registered_nodes[core.get_node({x=24,y=1,z=34}).name]
        assert(b and b.mesh and b.mesh:find("bridge_wood") and b.walkable,"missing actual timber deck collision")
        assert(field and field.mesh=="bl_farm_land_12.obj" and field.walkable,"missing actual field collision")
        local house="luanttd_core:scenery_house_0"
        assert(core.registered_nodes[house].walkable and #core.registered_nodes[house].collision_box.fixed>1)
        assert(core.get_node({x=22,y=2,z=38}).name==house,"house fixture must render")
        p:set_clouds({density=0})
        setup(p,"shore")
        pusher=p
        core.log("action","WALK_QA ready")
      end)
    end)
  end)
end
