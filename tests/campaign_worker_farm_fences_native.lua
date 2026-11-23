-- Loaded after the real game init by the native fixture only.
local FenceProbeTerrain=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
local function farm_fence_native()
  local p=core.get_player_by_name("FarmFenceQA")
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.2,farm_fence_native);return
  end
  local disk=assert(OwnerCheckpoint.read())
  local edges={[0]={0,0,0,1},[1]={0,1,1,1},[2]={1,0,1,1},[3]={0,0,1,0}}
  local target
  for id=1,Sim.W*Sim.H do
    local f=api.farm_world.field(disk,id)
    if f then
      local x,z=Sim.xy(id)
      for side=0,3 do
        local style=f.fences[side]
        local e=edges[side]
        if style and style>=1 and style<=6 then
          local xa,za,xb,zb=x+e[1],z+e[2],x+e[3],z+e[4]
          local a,b=FenceProbeTerrain.corner(disk.corner_grid,xa,za),FenceProbeTerrain.corner(disk.corner_grid,xb,zb)
          local nx,nz=x+(side==0 and -1 or side==2 and 1 or 0),z+(side==3 and -1 or side==1 and 1 or 0)
          local neighbor=Sim.id(nx,nz)
          local other=neighbor and api.farm_world.field(disk,neighbor)
          -- Pick a true perimeter fence so the expected source tile is unambiguous.
          if math.abs(a-b)<=1 and not other then
            target={tile=id,x=x,z=z,side=side,rise=math.abs(a-b),style=style,
              pos={x=xa+xb-.5,y=math.min(a,b)+.5,z=za+zb-.5},
              dx=(a>b and -1 or 1)*(xb-xa),dz=(a>b and -1 or 1)*(zb-za),
              soil={x=2*x,y=f.base+1,z=2*z}}
            break
          end
        end
      end
      if target then break end
    end
  end
  assert(target,"Generated world has no stock farm perimeter to test")
  local place=target.pos
  local stem=("farm_fence_%d_%d"):format(target.style,target.rise)
  local function camera()
    p:set_pos({x=place.x+(target.side==0 and -4 or target.side==2 and 4 or 0),y=place.y+2,
      z=place.z+(target.side==3 and -4 or target.side==1 and 4 or 0)})
    p:set_look_horizontal(({[0]=-math.pi/2,[1]=math.pi,[2]=math.pi/2,[3]=0})[target.side])
    p:set_look_vertical(.52)
  end
  local function visible()
    local count=0
    for _,ref in ipairs(core.get_objects_inside_radius(place,.04)) do
      local actor=ref:get_luaentity()
      if actor and actor.name:match("^luanttd_core:farm_fence_") then
        assert(actor.name=="luanttd_core:"..stem,"Incorrect fence style or rise")
        assert(ref:get_properties().mesh=="bl_"..stem..".obj","Incorrect fence mesh")
        local yaw=ref:get_yaw()
        assert(math.abs(math.cos(yaw)-target.dx)<.001 and math.abs(math.sin(yaw)-target.dz)<.001,
          "Incorrect stock fence orientation")
        count=count+1
      end
    end
    assert(count<=1,"Duplicate stock farm fence entities on one edge")
    return count==1
  end
  local function poll(predicate,cb,failure,n)
    if predicate() then cb()
    elseif n<60 then core.after(.2,function() poll(predicate,cb,failure,n+1) end)
    else error(failure.." (node "..core.get_node(target.soil).name..", tile "..target.tile..")") end
  end
  local function visible_crop()
    return core.get_node(target.soil).name:find("farm_ground",1,true) and visible()
  end
  camera()
  poll(visible_crop,function()
    core.log("action",("FARM_FENCE_WORKER_VISIBLE: tile %d side %d uses %s at the projected crop edge"):format(
      target.tile,target.side,stem))
    core.after(3,function()
      local x=target.x<Sim.W/2 and Sim.W-5 or 6
      p:set_pos({x=2*x,y=25,z=2*target.z})
      poll(function() return not visible() end,function()
        camera()
        poll(visible_crop,function()
          core.log("action","PASS NATIVE WORKER FARM FENCES: worker-owned crop and stock fence returned after leaving the scene")
        end,"Fence did not return with a fresh worker projection",1)
      end,"Fence was not culled when the viewer departed",1)
    end)
  end,"Worker-owned stock farm fence did not appear",1)
end
core.after(.2,farm_fence_native)
