-- Ordinary generated campaign, real Luanti client keyboard and mouse.
local patch,start_y,starting_cash,ready,moved,slot,home_slot,selected
local pause_requested,paused,aim_end,settled_end,palette_closed
core.register_on_player_receive_fields(function(p,form,fields)
  if form=="luanttd_core:plant_tree_palette" and fields.quit and p:get_player_name()=="SteelReview" then
    palette_closed=true
    core.log("action","NATIVE TREE QA PALETTE CLOSED")
  end
end)
-- Use the same UI handler as the player, but do not treat unrelated
-- stale client dig/input state during the palette as a tree gesture.
local actual_begin=ui.begin_tree
ui.begin_tree=function(p,id)
  local accepted=actual_begin(p,id)
  if accepted and p:get_player_name()=="SteelReview" and palette_closed and not moved then
    assert(patch and id==patch[1],"Tree drag did not start on the selected clear tile")
    moved=true
    core.log("action","NATIVE TREE QA DRAG START")
    core.after(.25,function() aim_end=true end)
  end
  return accepted
end
local function native_tree_qa()
  local p=core.get_player_by_name("SteelReview")
  if not (p and authority and authority.status()=="owned") then core.after(.2,native_tree_qa);return end
  local s=assert(OwnerCheckpoint.read())
  local company=s.companies.SteelReview
  if not company then core.after(.2,native_tree_qa);return end
  if not pause_requested then
    pause_requested=true
    local who=p:get_player_name()
    assert(authority.query({kind="company",player=who},function(status)
      assert(status.ok,tostring(status.why))
      assert(authority.query({kind="command",player=who,
        command={kind="speed",speed=0,revision=status.revision}},function(reply)
          assert(reply.ok,tostring(reply.why));paused=true
        end))
    end))
  end
  if not paused or s.speed~=0 then core.after(.2,native_tree_qa);return end
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
  if aim_end and not settled_end then
    if api.world.target(p)==patch[3] then
      settled_end=true
      core.log("action","NATIVE TREE QA DRAG END")
    else
      local x,z=Sim.xy(patch[3])
      p:set_pos({x=2*x+.5,y=start_y+7,z=2*z+.5})
      p:set_look_horizontal(0)
      p:set_look_vertical(1.56)
    end
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
