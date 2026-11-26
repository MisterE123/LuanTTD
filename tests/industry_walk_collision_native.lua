-- Native-client Walk on actual projected generated industrial art. Only the
-- test camera is moved; leave all industry nodes, hulls and worker state real.
local owner="IndustryLayoutsQA"
local started,wall,passage,passage_start,tree,tree_start
local function launch()
  local p=core.get_player_by_name(owner)
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    return core.after(.23,launch)
  end
  if started then return end
  started=true
  local disk=assert(OwnerCheckpoint.read())
  local function industry(which,kind,rx,rz,any)
    for _,rec in pairs(disk["stock_"..which.."_industries"] or {}) do
      if (rec.layout or 0)==0 and rec.kind==kind and not rec.removed then
        for _,cell in ipairs(rec.tiles) do
          if cell.completed and cell.x==rec.x+rx and cell.z==rec.z+rz then
            local x,z=cell.x+1,cell.z+1
            local row=disk.tiles[Sim.id(x,z)]
            local near=disk.tiles[Sim.id(x-1,z)]
            if any or (near and near.terrain~="water" and near.h==row.h and not
                (near.stock_industry or near.site or near.house or near.stock_landmark)) then
              return {x=2*x,y=row.h+1,z=2*z,west=Sim.id(x-1,z)}
            end
          end
        end
      end
    end
    error("Missing layout zero "..kind.." and open approach")
  end
  wall=industry("coal","power_station",0,0,false)
  passage=industry("oil","oil_refinery",0,1,true)
  local Terrain=dofile(mod.."/openttd/terrain.lua")
  local tree_art=dofile(mod.."/openttd/tree_display.lua")
  local exact=core.registered_nodes["luanttd_core:stock_tree_628_0_0"]
  local function find_tree()
    local west=math.floor(wall.x/2)
    local north=math.floor(wall.z/2)
    local quarters={[0]=0,2,3,1}
    for radius=2,40 do
      for z=north-radius,north+radius do for x=west-radius,west+radius do
        if math.abs(x-west)==radius or math.abs(z-north)==radius then
          local id=Sim.id(x,z)
          local t=id and disk.tiles[id]
          if t and type(t.wood)=="table" and not (t.stock_void or t.site or t.house or t.stock_industry or t.build) then
            local shape,base=Terrain.tile(disk.corner_grid,x,z)
            if shape==0 then
              for q=0,2,2 do
                local w=t.wood
                local name
                if exact then
                  local form,phase=tree_art.quarter(id-1,x-1,z-1,w.type,w.count,w.growth,q)
                  if form then name=("stock_tree_%03x_0_%d"):format(form,phase) end
                else
                  local stem=quarters[(q-t.variant)%4]
                  if stem<w.count then
                    name=("stock_forest_%d_0"):format(w.type%4)
                    if stem==w.count-1 and core.registered_nodes["luanttd_core:"..name.."_g"..w.growth] then
                      name=name.."_g"..w.growth
                    end
                  end
                end
                if name then return {x=2*x,y=base+2,z=2*z+q/2,name=name} end
              end
            end
          end
        end
      end end
    end
    error("No flat stock tree near power station")
  end
  tree=find_tree()
  local function projected(at,name,ready)
    local n=0
    local function check()
      local node=core.get_node(at)
      if node.name=="luanttd_core:"..name then
        local nd=core.registered_nodes[node.name]
        assert(nd.walkable and nd.collision_box.type=="fixed" and #nd.collision_box.fixed>0)
        -- Luanti projects the authoritative mesh before distant blocks
        -- finish streaming to the renderer. Let the native client receive
        -- the floor before moving its unpaused Walk capsule onto it.
        return core.after(1.6,ready)
      end
      n=n+1
      assert(n<140,"Missing projected "..name..", saw "..node.name)
      core.after(.20,check)
    end
    if world.avatar_state(p) then p:set_physics_override({gravity=0}) end
    p:set_pos({x=at.x-1.55,y=at.y+5,z=at.z+.47})
    check()
  end
  projected(wall,"power_station_0_0",function()
    local aim={x=wall.x-1.05,y=wall.y-.50,z=wall.z+.47}
    p:set_look_horizontal(-math.pi/2)
    assert(world.toggle_walk_at(p,wall.west,aim))
    assert(world.avatar_state(p) and world.avatar_state(p).mode=="walk")
    core.after(.58,function()
      local at=p:get_pos()
      assert(at.x<wall.x-.71)
      core.log("action",("NATIVE INDUSTRY WALK WALL READY: %.3f %.3f %.3f"):format(at.x,at.y,at.z))
    end)
  end)
  core.register_chatcommand("industrywalkqa",{func=function(name,tag)
    assert(name==owner)
    local at=p:get_pos()
    assert(world.avatar_state(p) and world.avatar_state(p).mode=="walk")
    if tag=="wall" then
      -- Native Walk radius is .064. West wall's bbox begins at -.35156.
      assert(math.abs(at.x-(wall.x-.415))<.10 and math.abs(at.y-(wall.y-.50))<.12,
        "Wall collision missing or stopped prematurely: "..core.pos_to_string(at))
      core.log("action",("NATIVE INDUSTRY WALK WALL STOP: %.3f"):format(at.x-wall.x))
      projected(passage,"industry_oil_refinery_0_1",function()
        passage_start={x=passage.x+.49,y=passage.y-.47,z=passage.z-.36}
        local floor_pos={x=math.floor(passage_start.x+.5),y=passage.y-1,z=math.floor(passage_start.z+.5)}
        local floor=core.registered_nodes[core.get_node(floor_pos).name]
        assert(floor.walkable,"Refinery aisle needs a solid floor, saw "..core.get_node(floor_pos).name)
        p:set_pos(passage_start)
        p:set_physics_override({gravity=1})
        p:set_look_horizontal(0)
        p:set_look_vertical(0)
        core.after(.63,function() core.log("action","NATIVE INDUSTRY WALK PASSAGE READY") end)
      end)
    elseif tag=="passage" then
      local progress=at.z-passage_start.z
      assert(progress>1.05 and math.abs(at.x-passage_start.x)<.10 and math.abs(at.y-passage_start.y)<.18,
        "An open refinery aisle blocked a pedestrian: "..core.pos_to_string(at))
      core.log("action",("NATIVE INDUSTRY WALK PASSAGE CLEAR: %.2f nodes of open refinery aisle traversed"):format(progress))
      projected(tree,tree.name,function()
        tree_start={x=tree.x-.45,y=tree.y-1.485,z=tree.z}
        p:set_pos(tree_start)
        p:set_physics_override({gravity=1})
        p:set_look_horizontal(-math.pi/2)
        p:set_look_vertical(0)
        core.after(.63,function() core.log("action","NATIVE INDUSTRY WALK TREE READY") end)
      end)
    elseif tag=="tree" then
      assert(at.x>tree_start.x+.22 and at.x<tree.x-.052 and math.abs(at.z-tree.z)<.09,
        "Could not walk up to the stock tree trunk: "..core.pos_to_string(at))
      core.log("action",("PASS NATIVE INDUSTRY WALK: power wall is solid, refinery aisle is clear, real stock trunk %s stops Walk at %.3f"):format(tree.name,at.x-tree.x))
    else error("unknown native Walk check") end
    return true
  end})
end
core.after(.23,launch)
