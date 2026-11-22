-- Appended to a disposable native game; uses actual paid Sim and renderer.
return function(api)
  local S,Sim,R=api.s,api.Sim,api.render
  local T=dofile(core.get_modpath("bayline").."/openttd/terrain.lua")
  local function id(x,z) return assert(Sim.id(x,z)) end
  S.corner_grid.levels=T.new(Sim.W,Sim.H,function(x,z)
    if z>=9 and z<=16 and (x>=14 or (x==13 and z==12)) then return 1 end
    return 0
  end).levels
  for z=7,18 do for x=8,19 do
    local i=id(x,z)
    S.tiles[i]={terrain="grass",variant=(3*x+z)%4,h=0}
  end end
  -- A low junction opposite a solitary raw high corner, followed by the
  -- leveled high road. Looks like the reported duplicate road underneath.
  local cost=0
  local function road(ax,az,bx,bz)
    local route=Sim.line(id(ax,az),id(bx,bz))
    local _,quote=assert(Sim.plan(S,"GradeQA","road",route))
    local ok,why=Sim.build(S,"GradeQA","road",route)
    assert(ok,why);cost=cost+quote
  end
  road(10,11,17,11)
  road(10,9,10,13)
  local a,base,f=Sim.road_surface(S,id(12,11))
  assert(a==3 and base==0 and f=="x")
  a,base,f=Sim.road_surface(S,id(13,11))
  assert(a==0 and base==1 and f=="leveled")
  assert(Sim.road_connected(S,id(12,11),2) and cost>0)
  local ground=core.registered_nodes["bayline:road_10_plain_1"]
  local flat=core.registered_nodes["bayline:road_foundation_10_1"]
  local wedge=core.registered_nodes["bayline:road_grade_3_foundation"]
  assert(ground.tiles[3]=="bl_grass_side.png" and flat.tiles[3]=="bl_road_surface_retaining.png")
  assert(#wedge.tiles==1 and wedge.tiles[1]=="bl_road_grade_foundation_10.png")
  core.register_on_joinplayer(function(p)
    if p:get_player_name()~="GradeQA" then return end
    local from={x=22,y=1.4,z=17}
    local at={x=25.45,y=.98,z=22.5}
    p:set_physics_override({gravity=0})
    p:set_pos(from)
    p:set_look_horizontal(math.atan2(from.x-at.x,at.z-from.z))
    p:set_look_vertical(math.atan2(from.y+1.47-at.y,math.sqrt((at.x-from.x)^2+(at.z-from.z)^2)))
    for _,fl in ipairs{"hotbar","healthbar","crosshair","wielditem","breathbar","minimap","minimap_radar"} do
      p:hud_set_flags({[fl]=false})
    end
    core.emerge_area({x=16,y=-1,z=15},{x=37,y=5,z=33},function(_,_,remaining)
      if remaining~=0 then return end
      local dirty={}
      for z=8,16 do for x=9,18 do dirty[#dirty+1]=id(x,z) end end
      R.update(dirty)
      local function at(x,y,z) return core.get_node({x=x,y=y,z=z}).name end
      assert(at(24,1,22)=="bayline:road_grade_3_foundation")
      assert(not at(25,0,23):find("plain") and not at(24,0,22):find("plain"))
      assert(at(26,1,22)=="bayline:road_foundation_10_2")
      core.log("action","ROAD_GRADE_FOUNDATION_READY cost="..cost)
    end)
  end)
end
