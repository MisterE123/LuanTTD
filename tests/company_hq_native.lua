-- Click the ordinary Company hotbar in a genuine generated Luanti world.
-- The fixture only picks a reproducible camera position and observes state.
local player="SteelReview"
local request,paused,cash,home,slot,selected
local site,moved_site,level,ready,move_camera
local built,visual,move_ready
local object_autoslope=core.settings:get_bool("luanttd_qa_object_autoslope",false)
local resculpted
local function aim(p,id)
  local x,z=Sim.xy(id)
  p:set_pos({x=2*x+.5,y=level+7,z=2*z+.5})
  p:set_look_horizontal(0);p:set_look_vertical(1.56)
end
local function exhibit(p,id)
  local x,z=Sim.xy(id)
  p:set_pos({x=2*x+1.5,y=level+5.6,z=2*z-6.4})
  p:set_look_horizontal(0);p:set_look_vertical(.56)
end
local function check()
  local p=core.get_player_by_name(player)
  if not (p and authority and authority.status()=="owned") then core.after(.2,check);return end
  local s=assert(OwnerCheckpoint.read())
  local c=s.companies[player]
  if not c then core.after(.2,check);return end
  if not request then
    request=true
    assert(authority.query({kind="company",player=player},function(reply)
      assert(reply.ok,tostring(reply.why))
      assert(authority.query({kind="command",player=player,command={kind="speed",speed=0,revision=reply.revision}},function(r)
        assert(r.ok,tostring(r.why));paused=true
      end))
    end))
  end
  if not paused or s.speed~=0 then core.after(.2,check);return end
  if not site then
    local function candidate(x,z)
      local lvl
      for dz=0,1 do for dx=0,2 do
        local id=Sim.id(x+dx,z+dz)
        local t=s.tiles[id]
        local shape,h=api.terrain.tile(id)
        if not t or shape~=0 or h<1 or lvl and lvl~=h or t.terrain=="water" or t.stock_void or
          t.wood or t.stock_clear_ground or t.stock_clear_density==0 or
          t.site or t.owner or t.build or t.house or t.stock_landmark or t.stock_industry or
          s.stock_farm_fields and s.stock_farm_fields[id] then return end
        lvl=h
      end end
      return lvl
    end
    -- Avoid the horizon and stand the camera inside the visible map.
    for z=12,Sim.H-5 do
      for x=8,Sim.W-6 do
        local h=candidate(x,z)
        if h then site,moved_site,level=Sim.id(x,z),Sim.id(x+1,z),h;break end
      end
      if site then break end
    end
    assert(site,"No safe six-parcel plateau for headquarters QA")
    cash=c.cash
  end
  if not ready then
    if api.world.target(p)==site then ready=true;core.log("action","NATIVE HQ READY")
    else aim(p,site) end
  end
  local function find(item)
    for i=1,10 do
      if p:get_inventory():get_stack("main",i):get_name()=="luanttd_core:"..item then return i end
    end
  end
  if not home and api.world.menu(p)=="home" then
    home=find("menu_section_company")
    if home then core.log("action","NATIVE HQ HOME "..home) end
  end
  if not slot and api.world.menu(p)=="company" then
    slot=assert(find("menu_company_hq"))
    core.log("action","NATIVE HQ SLOT "..slot)
  end
  if not selected and p:get_wielded_item():get_name()=="luanttd_core:menu_company_hq" then
    selected=true;core.log("action","NATIVE HQ SELECTED")
  end
  local hq=s.stock_company_hqs and s.stock_company_hqs[player]
  local function painted(hq)
    for part,id in ipairs(hq.tiles) do
      local x,z=Sim.xy(id)
      local node=core.get_node({x=x*2,y=hq.level+1,z=z*2}).name
      if node~=("luanttd_core:stock_company_hq_%d_%d"):format(hq.stage,part) then return false end
    end
    return true
  end
  if hq and not built then
    assert(#hq.tiles==4 and hq.origin==site and c.cash==cash-80,"Wrong initial HQ site or price")
    if painted(hq) then
      exhibit(p,hq.origin)
      built=true;core.log("action","NATIVE HQ BUILT")
      if object_autoslope then
        local x,z=Sim.xy(hq.origin)
        assert(authority.query({kind="terrain_quote",player=player,
          request={operation="lower",first=Sim.id(x+1,z+1)}},function(q)
          assert(q.ok and q.value.cost==1250 and #q.value.tiles==4,tostring(q.why))
          assert(authority.query({kind="command",player=player,command={kind="terrain_commit",
            revision=q.revision,token=q.value.token}},function(r)
            assert(r.ok,tostring(r.why))
            resculpted=true
          end))
        end))
      else
        core.after(2.5,function() move_camera=true end)
      end
    end
  end
  if object_autoslope and resculpted and hq and painted(hq) then
    local walls=0
    for _,id in ipairs(hq.tiles) do
      local x,z=Sim.xy(id)
      if s.tiles[id].h==hq.level-1 and core.get_node({x=x*2,y=hq.level,z=z*2}).name==
          "luanttd_core:road_retaining" then walls=walls+1 end
    end
    if walls==4 then
      assert(hq.origin==site and hq.level==level and c.cash==cash-80-1250)
      exhibit(p,hq.origin)
      core.log("action","PASS NATIVE HQ: placed by mouse, four RC1 paid foundations, original meshes fixed at the same height")
      return
    end
  end
  if move_camera and not move_ready then
    if api.world.target(p)==moved_site then move_ready=true;core.log("action","NATIVE HQ MOVE READY")
    else aim(p,moved_site) end
  end
  if move_ready and hq and hq.origin==moved_site and painted(hq) then
    local fee=math.floor((cash-80-c.loan)/100)+40
    assert(c.cash==cash-80-fee and not s.tiles[site].stock_landmark and not s.tiles[site].owner,"Incorrect relocation")
    exhibit(p,hq.origin)
    core.log("action","PASS NATIVE HQ: real four-parcel Company placement and overlapping relocation")
    return
  end
  core.after(.16,check)
end
core.after(.2,check)
