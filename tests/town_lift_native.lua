-- Open a real worker-owned Temperate city and watch its original moving
-- lift inside the new native 3D office; the test never manufactures a house.
local T=dofile(mod.."/openttd/terrain.lua")
local Front=dofile(mod.."/house_frontage.lua")
local owner="StockResidentialQA"
local function ask()
  local p=core.get_player_by_name(owner)
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.2,ask);return
  end
  local state=assert(OwnerCheckpoint.read())
  local resume=core.settings:get_bool("luanttd_qa_town_lift_restart",false)
  local prior=core.deserialize(storage:get_string("town_lift_qa"),true)
  local target=resume and assert(prior,"Reopen must verify the same stock office") or nil
  for id,t in ipairs(state.tiles) do
    if resume then break end
    local h=t.source_house
    if t.house and h and h.id==0x04 and h.completed and Front.road(Sim,state,id,t) then
      local x,z=Sim.xy(id)
      local dx,dz,f=Front.placement(Sim,state,id,t,false,h.render_parcel or t.parcel)
      local _,_,deck=T.tile(state.corner_grid,x,z)
      target={id=id,x=2*x+dx,y=deck+1,z=2*z+dz,f=f}
      if f==0 then break end
    end
  end
  assert(target,"No hosted completed stock office with a street-facing lift shaft")
  if resume then
    local initial=state.tiles[target.id].source_house
    assert(initial and initial.completed and initial.id==0x04 and initial.lift_position~=nil,
      "The pinned office's discrete lift motion did not persist") end
  local normals={{0,1},{1,0},{0,-1},{-1,0}}
  local dir=normals[target.f+1]
  local focus={x=target.x+.35,z=target.z+.35,y=target.y+.72}
  local sight={x=focus.x+dir[1]*4.8+dir[2]*1.15,z=focus.z+dir[2]*4.8-dir[1]*1.15,y=focus.y+.12}
  p:set_pos(sight)
  local dx,dy,dz=focus.x-sight.x,focus.y-sight.y-1.625,focus.z-sight.z
  p:set_look_horizontal(math.atan2(-dx,dz))
  p:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
  local low,high,native_low,native_high=math.huge,-math.huge,math.huge,-math.huge
  local count=0
  local function watch(limit)
    local world=assert(OwnerCheckpoint.read())
    local h=world.tiles[target.id].source_house
    local pos=h.lift_position
    if pos then low,high=math.min(low,pos),math.max(high,pos) end
    local node=core.get_node_or_nil(target)
    local car,current
    if node and node.name=="luanttd_core:town_stock_04" then
      assert(node.param2==target.f)
      for _,ref in ipairs(core.get_objects_inside_radius(target,2)) do
        local ent=ref:get_luaentity()
        local at=ref:get_pos()
        if ent and ent.name=="luanttd_core:town_office_lift" and at
          and math.abs(at.x-target.x)<.05 and math.abs(at.z-target.z)<.05 then
          local yaw=ref:get_yaw()
          assert(math.abs(math.sin(yaw+target.f*math.pi/2))<.001)
          current=at.y-target.y
          assert(ref:get_properties().mesh=="bl_town_stock_04_lift.obj")
          assert(current>=-.001 and current<=36*.0475+.001,"Cab outside its native shaft")
          native_low,native_high=math.min(native_low,current),math.max(native_high,current)
          count=count+1
          car=true
          break
        end
      end
    end
    -- A checkpoint and a projection may coalesce different tick batches.
    -- Require real travel in both, not a fortuitous mid-trip camera sample.
    -- Durable snapshots are seconds apart and can miss the ends of a
    -- trip. The in-world cab must still visibly traverse at least 12
    -- positions; the saved worker state must show a real change too.
    if car and high>low and native_high-native_low>=12*.0475-.001 and count>=4 then
      if resume then
        core.log("action","PASS NATIVE TOWN LIFT REOPEN: same worker-owned office continued stock cab travel after restart")
      else
        storage:set_string("town_lift_qa",core.serialize(target))
        core.log("action",("NATIVE TOWN LIFT FRAME: house %d, painted facing=%d, stock range %d to %d")
          :format(target.id,target.f,low,high))
        core.after(1.6,function()
          core.log("action","PASS NATIVE TOWN LIFT: real generated stock office, worker-authoritative car motion on its Blender shaft")
        end)
      end
      return
    end
    assert(limit>0,("No stock lift travel in rendered office %d: worker range %s..%s, native %.2f..%.2f, %d samples")
      :format(target.id,tostring(low),tostring(high),native_low,native_high,count))
    core.after(.27,function()watch(limit-1) end)
  end
  core.after(.4,function()watch(160) end)
end
core.after(.2,ask)
