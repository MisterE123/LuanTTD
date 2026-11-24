-- The fixture only sets up the lookout and reads the authoritative checkpoint.
-- Real Luanti clicks buy and resell the selected plot.
local plot,base,starting_cash,ready,home,land,sell,settled
local pause_requested,paused,bought,returned
local function check()
  local p=core.get_player_by_name("SteelReview")
  if not (p and authority and authority.status()=="owned") then core.after(.2,check);return end
  local s=assert(OwnerCheckpoint.read())
  local c=s.companies.SteelReview
  if not c then core.after(.2,check);return end
  if not pause_requested then
    pause_requested=true
    assert(authority.query({kind="company",player="SteelReview"},function(reply)
      assert(reply.ok,tostring(reply.why))
      assert(authority.query({kind="command",player="SteelReview",
        command={kind="speed",speed=0,revision=reply.revision}},function(r)
          assert(r.ok,tostring(r.why));paused=true
        end))
    end))
  end
  if not paused or s.speed~=0 then core.after(.2,check);return end
  if not plot then
    for z=3,Sim.H-4 do
      for x=3,Sim.W-4 do
        local id=Sim.id(x,z)
        local t=s.tiles[id]
        local slope,h=api.terrain.tile(id)
        if t and slope==0 and t.terrain~="water" and h>=1 and not
            (t.stock_void or t.wood or t.house or t.site or t.owner or t.build or t.stock_landmark or
            t.stock_industry or t.stock_clear_ground or t.stock_clear_density==0 or
            s.stock_farm_fields and s.stock_farm_fields[id]) then
          plot,base=id,h;break
        end
      end
      if plot then break end
    end
    assert(plot,"No ordinary flat plot at full grass density")
    starting_cash=c.cash
  end
  local x,z=Sim.xy(plot)
  if not ready and api.world.target(p)==plot then
    ready=true;core.log("action","NATIVE LAND READY")
  elseif not ready then
    p:set_pos({x=2*x+.5,y=base+6,z=2*z+.5})
    p:set_look_horizontal(0);p:set_look_vertical(1.56)
  end
  local function find(item)
    for i=1,10 do
      if p:get_inventory():get_stack("main",i):get_name()=="luanttd_core:"..item then return i end
    end
  end
  if not home and api.world.menu(p)=="home" then
    home=find("menu_section_terrain")
    if home then core.log("action","NATIVE LAND HOME "..home) end
  end
  if not land and api.world.menu(p)=="terrain" then
    land=find("menu_landscape_purchase_land")
    sell=find("menu_clear")
    assert(land and sell,"Buy Land and Bulldoze must both be in Landscaping")
    core.log("action","NATIVE LAND BUY SLOT "..land)
    core.log("action","NATIVE LAND SELL SLOT "..sell)
  end
  if not settled and p:get_wielded_item():get_name()=="luanttd_core:menu_landscape_purchase_land" then
    local selected,hit=api.world.target(p)
    if selected==plot then
      api.world.hud(p)
      local status,_,ids,valid=ui.world_status(p,plot,true,hit)
      if ids and #ids==1 and ids[1]==plot and valid and status:find("420",1,true) then
        assert(ui.is_world_tool("landscape_purchase_land"))
        settled=true;core.log("action","NATIVE LAND SELECTED")
      end
    end
  end
  local pos={x=x*2,y=base+2,z=z*2}
  local post=core.get_node(pos).name
  if not bought and s.tiles[plot].stock_object and post=="luanttd_core:owned_land_0" then
    assert(c.cash==starting_cash-420 and s.tiles[plot].owner=="SteelReview","Incorrect land purchase")
    bought=true
    -- Move to an oblique inspection view so the player can see the face and post.
    p:set_pos({x=x*2+.5,y=base+2.8,z=z*2+5.0})
    p:set_look_horizontal(math.pi)
    p:set_look_vertical(.65)
    core.log("action","NATIVE LAND BOUGHT")
  end
  if bought and not returned and p:get_wielded_item():get_name()=="luanttd_core:menu_clear" then
    if api.world.target(p)==plot then
      returned=true;core.log("action","NATIVE LAND SELL READY")
    else
      p:set_pos({x=2*x+.5,y=base+6,z=2*z+.5})
      p:set_look_horizontal(0);p:set_look_vertical(1.56)
    end
  end
  if returned and not s.tiles[plot].stock_object and not post:find("owned_land",1,true) then
    if core.get_node({x=x*2,y=base,z=z*2}).name~="luanttd_core:stock_clear_grass_0" then core.after(.16,check);return end
    assert(s.tiles[plot].stock_clear_density==0,"the stock land sale must begin grass regrowth")
    assert(c.cash==starting_cash-340 and not s.tiles[plot].owner,"Land resale did not issue the stock $80 refund")
    core.log("action","PASS NATIVE OWNED LAND: mouse purchased and resold the visible company stake")
    return
  end
  core.after(.16,check)
end
core.after(.2,check)
