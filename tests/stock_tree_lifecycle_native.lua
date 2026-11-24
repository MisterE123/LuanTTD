-- Appended only to a disposable ordinary campaign. The worker's real
-- source clock advances the trees; the fixture never sets a growth phase.
local waiting,baseline,cam_id=false,nil,nil
local function scene()
  local p=core.get_player_by_name("SteelReview")
  if not (p and authority and authority.status()=="owned") then core.after(.24,scene);return end
  local s=assert(OwnerCheckpoint.read())
  if not baseline then
    baseline={day=s.day,groves={},clock=s.stock_tree_tick_counter}
    for id,t in ipairs(s.tiles) do
      local w=t.wood
      if type(w)=="table" then
        baseline.groves[id]={type=w.type,stage=w.growth,count=w.count}
      end
    end
  end
  local born=0
  for id,t in ipairs(s.tiles) do
    if type(t.wood)=="table" and not baseline.groves[id] then born=born+1 end
  end
  local changed=0
  for id,old in pairs(baseline.groves) do
    local w=s.tiles[id].wood
    if not w or w.growth~=old.stage or w.count~=old.count then changed=changed+1 end
  end
  if not waiting then
    waiting=true
    core.after(5,scene)
    return
  end
  if s.day<baseline.day+3 or changed==0 or born==0 or not s.stock_tree_tick_counter
      or s.stock_tree_tick_counter==baseline.clock then core.after(.3,scene);return end
  if not cam_id then
    for id,t in ipairs(s.tiles) do
      local w=t.wood
      if type(w)=="table" and w.count>=2 and w.growth~=3 and t.terrain~="water" then
        cam_id=id
        local x,z=Sim.xy(id)
        local _,h=api.terrain.tile(id)
        local focus={x=x*2+.5,y=h+1.8,z=z*2+.5}
        local eye={x=focus.x-2.7,y=h+3.3,z=focus.z+5}
        p:set_pos(eye)
        local d={x=focus.x-eye.x,y=focus.y-eye.y-1.47,z=focus.z-eye.z}
        p:set_look_horizontal(math.atan2(-d.x,d.z))
        p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
        break
      end
    end
    assert(cam_id,"No live multiple-stem Temperate tree fixture")
    core.after(.3,scene)
    return
  end
  local old=s.tiles[cam_id].wood
  if not old or old.count<2 or old.growth==3 then cam_id=nil;core.after(.24,scene);return end
  local x,z=Sim.xy(cam_id)
  local shape,h=api.terrain.tile(cam_id)
  local quarter={[0]=0,2,3,1}
  for side=0,3 do
    local i,j=side%2,math.floor(side/2)
    local stem=quarter[(side-s.tiles[cam_id].variant)%4]
    if stem<old.count then
      local node=core.get_node({x=2*x+i,y=h+2,z=2*z+j})
      local registered=core.registered_nodes[node.name]
      local lift=math.floor(api.slope.surface((i+.5)/2,(j+.5)/2,shape)*2+.00001)
      local mesh=("bl_stock_forest_%d_%d"):format(old.type%4,math.min(4,lift))
      if stem==old.count-1 then mesh=mesh.."_g"..old.growth end
      if not registered or registered.mesh~=mesh..".obj" then core.after(.24,scene);return end
    end
  end
  core.log("action",("PASS NATIVE STOCK TREE LIFE: real worker day %d→%d advanced %d groves and added %d; global clock %s→%d; final stem phase %d, earlier stems mature")
    :format(baseline.day,s.day,changed,born,tostring(baseline.clock),s.stock_tree_tick_counter,old.growth))
end
core.after(.24,scene)
