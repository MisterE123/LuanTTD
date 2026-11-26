-- Native visual only. One stationary linked mechanism per visible oil
-- well; no MapBlock resends or physics moved by an animation frame.
return function(core,Sim,anchors)
  local V={}
  local refs,poses,elapsed={}, {},.08
  local name="luanttd_core:oil_well_pump"
  local meshes={}
  for phase=0,11 do meshes[phase]=("bl_industry_oil_well_pose_%02d.obj"):format(phase) end
  core.register_entity(name,{
    initial_properties={visual="mesh",mesh=meshes[0],textures={"bl_industry_oil_well_atlas.png"},
      visual_size={x=1,y=1,z=1},static_save=false,physical=false,
      pointable=false,collide_with_objects=false,collisionbox={0,0,0,0,0,0},shaded=true},
  })
  function V.observe(next_poses)
    poses=next_poses or {}
  end
  local function clear(id)
    local r=refs[id]
    if r and r.ref:get_pos() then r.ref:remove() end
    refs[id]=nil
  end
  function V.clear()
    for id in pairs(refs) do clear(id) end
    poses={}
  end
  function V.witness(id)
    local r=refs[id]
    if r and r.ref:get_pos() then return r.ref,r.phase end
  end
  function V.step(dt,s)
    elapsed=elapsed+dt
    if elapsed<.06 then return end
    elapsed=elapsed%.06
    local eyes={}
    for _,p in ipairs(core.get_connected_players()) do
      local v=p:get_pos()
      if v then eyes[#eyes+1]=v end
    end
    local keep={}
    for id,row in pairs(poses) do
      local mesh=meshes[row.oil]
      local t=mesh and s.tiles[id]
      local tag=t and t.stock_industry
      -- The actor packet can lead a terrain/closure packet. Require
      -- their authoritative site identity and the already painted base.
      if tag and tag.id==row.site and tag.chain=="oil" and tag.gfx==29 and row.base==t.h then
        local x,z=Sim.xy(id)
        local p={x=2*x,y=row.base+1,z=2*z}
        local visible
        for _,v in ipairs(eyes) do
          -- Keep the complete silhouette throughout the ordinary
          -- 3D interest window, not just while the pump is running.
          if (v.x-p.x)^2+(v.y-p.y)^2+(v.z-p.z)^2<=128^2 then visible=true;break end
        end
        local node=visible and core.get_node_or_nil(p)
        if node and anchors[node.name] then
          local r=refs[id]
          if r and (r.site~=row.site or r.y~=p.y or not r.ref:get_pos()) then clear(id);r=nil end
          if not r then
            local obj=core.add_entity(p,name)
            if obj then r={ref=obj,site=row.site,y=p.y};refs[id]=r end
          end
          if r then
            keep[id]=true
            if r.phase~=row.oil then
              r.ref:set_properties({mesh=mesh})
              r.phase=row.oil
            end
          end
        end
      end
    end
    for id in pairs(refs) do if not keep[id] then clear(id) end end
  end
  return V
end
