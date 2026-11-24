-- Disposable native startup/viewport probe for the actual generated stock mill.
local expected=tonumber(core.settings:get("luanttd_qa_steel_layout")) or 1
local observed=false
local settle_at
local function ready()
  if observed then return end
  local viewer=core.get_player_by_name("SteelReview")
  if not (viewer and authority and authority.status()=="owned") then core.after(.2,ready);return end
  -- Let the ordinary initial spawn relocate the player before moving
  -- the QA camera to the mill, or the capture will show the town square.
  if not settle_at then settle_at=core.get_us_time()+5000000 end
  if core.get_us_time()<settle_at then core.after(.2,ready);return end
  local selected
  for _,p in pairs(S.stock_heavy_placements or {}) do
    if p.kind=="steel_mill" and p.layout==expected then selected=p;break end
  end
  if not selected then
    local world_state=assert(OwnerCheckpoint.read())
    for _,p in pairs(world_state.stock_heavy_placements or {}) do
      if p.kind=="steel_mill" and p.layout==expected then selected=p;break end
    end
  end
  assert(selected and #selected.cells==(expected==1 and 14 or 12),"Stock fresh seed did not generate the expected mill")
  local x,z,h=selected.x,selected.z,selected.level
  local at={x=2*x+3.6,y=h+1.65,z=2*z+3.1}
  local camera={x=at.x+6.6,y=h+8.7,z=at.z+13}
  viewer:set_pos(camera)
  local d={x=at.x-camera.x,y=at.y-camera.y-1.47,z=at.z-camera.z}
  viewer:set_look_horizontal(math.atan2(-d.x,d.z))
  viewer:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
  observed=true
  local function mounted()
    for _,c in ipairs(selected.cells) do
      local name=core.get_node({x=2*c.x,y=h+1,z=2*c.z}).name
      local config=core.registered_nodes[name]
      local mesh=("bl_%s_%d_%d.obj"):format(selected.style,c.offset_x,c.offset_z)
      if not config or config.mesh~=mesh then core.after(.22,mounted);return end
    end
    if expected==1 then
      for _,dx in ipairs({0,3}) do
        local hole=core.get_node({x=2*(x+dx),y=h+1,z=2*(z+3)}).name
        assert(not hole:match("industry_steel_mill"),"Occupied a stock layout hole")
      end
    end
    core.log("action",("PASS NATIVE STOCK STEEL MILL: seed=%d layout=%d has %d mounted stock mesh cells")
      :format(S.seed,expected,#selected.cells))
  end
  mounted()
end
core.after(.2,ready)
