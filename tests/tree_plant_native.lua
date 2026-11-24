-- Ordinary generated campaign, real Luanti client keyboard and mouse.
local patch,start_y,starting_cash,ready,moved,slot,home_slot,selected
local function native_tree_qa()
  local p=core.get_player_by_name("SteelReview")
  if not (p and authority and authority.status()=="owned") then core.after(.2,native_tree_qa);return end
  local s=assert(OwnerCheckpoint.read())
  local company=s.companies.SteelReview
  if not company then core.after(.2,native_tree_qa);return end
  if not patch then
    local function clear(x,z)
      local id=Sim.id(x,z)
      local t=s.tiles[id]
      local shape,h=api.terrain.tile(id)
      if t and shape==0 and t.terrain~="water" and t.h>=1 and not t.stock_void and not
        (t.wood or t.house or t.site or t.owner or t.build or t.station or t.stock_landmark or t.stock_industry or
          t.stock_clear_ground or s.stock_farm_fields and s.stock_farm_fields[id]) then return id,h end
    end
    for z=3,Sim.H-3 do
      for x=3,Sim.W-5 do
        local a,h=clear(x,z)
        local b,g=clear(x+1,z)
        local c,k=clear(x+2,z)
        if a and b and c and h==g and h==k then patch,start_y={a,b,c},h;break end
      end
      if patch then break end
    end
    assert(patch,"No ordinary clear flat strip for tree gesture")
    local x,z=Sim.xy(patch[1])
    p:set_pos({x=2*x+.5,y=start_y+7,z=2*z+.5})
    p:set_look_vertical(1.56)
    p:set_look_horizontal(0)
    starting_cash=company.cash
    core.log("action","NATIVE TREE QA CAMERA")
  end
  if not ready then
    if api.world.target(p)==patch[1] then
      core.log("action","NATIVE TREE QA READY");ready=true
    else
      local x,z=Sim.xy(patch[1])
      p:set_pos({x=2*x+.5,y=start_y+7,z=2*z+.5})
      p:set_look_horizontal(0)
      p:set_look_vertical(1.56)
    end
  end
  if not home_slot and api.world.menu(p)=="home" then
    for i=1,10 do
      if p:get_inventory():get_stack("main",i):get_name()=="luanttd_core:menu_section_terrain" then
        home_slot=i;core.log("action","NATIVE TREE QA HOME "..i);break
      end
    end
  end
  if not slot and api.world.menu(p)=="terrain" then
    for i=1,10 do
      if p:get_inventory():get_stack("main",i):get_name()=="luanttd_core:menu_landscape_plant_tree" then
        slot=i;core.log("action","NATIVE TREE QA SLOT "..i);break
      end
    end
  end
  local wield=p:get_wielded_item():get_name()
  if not selected and wield=="luanttd_core:menu_landscape_plant_tree" then
    selected=true;core.log("action","NATIVE TREE QA SELECTED")
  end
  local keys=p:get_player_control()
  if not moved and wield=="luanttd_core:menu_landscape_plant_tree" and (keys.dig or keys.LMB) then
    moved=true
    core.after(.4,function()
      local x,z=Sim.xy(patch[3])
      p:set_pos({x=2*x+.5,y=start_y+7,z=2*z+.5})
      p:set_look_vertical(1.56)
      core.log("action","NATIVE TREE QA DRAG END")
    end)
  end
  if moved and company.cash==starting_cash-60 then
    for _,id in ipairs(patch) do
      local t=s.tiles[id]
      assert(t.wood and t.wood.count==1 and t.wood.growth==0,"Real gesture charged without planting expected trees")
    end
    core.log("action","PASS NATIVE TREE PLANT: real mouse drag placed three live trees for $60")
    return
  end
  core.after(.16,native_tree_qa)
end
core.after(.2,native_tree_qa)
