-- Appended only to a disposable copy of the game. Ordinary terrain, stock
-- town growth, native mesh registration, real worker, real typed Bulldozer.
local hooks={}
local authority=dofile(mod.."/campaign_authority_host.lua")(core,mod,hooks)
core.after(.2,function()
  assert(api.generated_world and S.stock_generated_profile and S.passenger_house_clock)
  local Art=dofile(mod.."/stock_town_art.lua")
  local owner="TownArtQA"
  local T=dofile(mod.."/openttd/terrain.lua")
  local exercise_foundation=core.settings:get_bool("luanttd_qa_house_autoslope",false)
  local company=Sim.company(S,owner)
  local cash,day=company.cash,S.day
  local root
  for _,tile in ipairs(S.tiles) do
    local h=tile.source_house
    if h and h.root and h.completed and h.id==0x14 then
      local matches=true
      if exercise_foundation then
        for _,member in ipairs(assert(Art.footprint(Sim,S,h))) do
          local x,z=Sim.xy(member.id)
          local shape,base=T.tile(S.corner_grid,x,z)
          if base<=0 or shape~=0 then matches=false;break end
        end
      end
      if matches then root=h;break end
    end
  end
  assert(root,"Default test generation had no completed football ground")
  local members=assert(Art.footprint(Sim,S,root))
  assert(#members==4)
  local lowered_at=assert(Sim.id(root.x+1,root.z+1))
  local lower_cost=0
  local owner_file="stock-town-native.chk"
  local checkpoint=dofile(mod.."/campaign_checkpoint.lua")(core,dofile(mod.."/packed_campaign.lua"),owner_file)
  local finished,command,expected_cost,stopping,reshaping,formed
  local phase="handing off the generated campaign"
  function hooks.freeze_host() api.authority_handoff=true end
  function hooks.seal_checkpoint() checkpoint.write_state(S);return owner_file end
  function hooks.ready() phase="waiting for the four painted football-ground tiles" end
  function hooks.present(v) end
  function hooks.stopped(why,_,elapsed,detail)
    assert(why=="stopped" and finished and elapsed>day,detail or why)
    assert(S.day==day and company.cash==cash and Art.footprint(Sim,S,root))
    core.log("action","STOCK_TOWN_CITY_NATIVE_OK native 4-piece football ground, worker permits child bulldoze, durable one debit and all four parts cleared")
    core.request_shutdown("Stock Town QA passed",false,0)
  end
  local function ask(req,result)
    req.player=owner
    assert(authority.query(req,function(reply) assert(reply.ok,reply.why);result(reply) end))
  end
  local function painted(expected)
    local verified=0
    for _,m in ipairs(members) do
      local x,z=Sim.xy(m.id)
      local tag=("luanttd_core:town_stock_14_%d"):format(m.record.asset_part)
      local n=core.get_node({x=2*x,y=S.tiles[m.id].h+1,z=2*z})
      if expected then
        local def=core.registered_nodes[tag]
        assert(def and def.mesh=="bl_"..tag:sub(14)..".obj")
      end
      if (expected and n.name==tag) or (not expected and n.name=="air") then verified=verified+1 end
      if expected and exercise_foundation and formed then
        local supporting=core.get_node({x=2*x,y=S.tiles[m.id].h,z=2*z})
        if supporting.name~="luanttd_core:road_retaining" then return false end
      end
    end
    return verified==4
  end
  local painter=dofile(mod.."/campaign_projection_painter.lua")(render,function(_,ok,reason)
    assert(ok,reason)
    if exercise_foundation and not reshaping and painted(true) then
      reshaping=true
      phase="quoting the stock foundation under four stadium parts"
      ask({kind="terrain_quote",request={operation="lower",first=lowered_at}},function(q)
        lower_cost=q.value.cost
        assert(lower_cost==1250,"The corner shared by four stadium tiles should bill each foundation")
        ask({kind="command",command={kind="terrain_commit",revision=q.revision,token=q.value.token}},function()
          local live=assert(checkpoint.read())
          assert(live.companies[owner].cash==cash-lower_cost)
          assert(#assert(Art.footprint(Sim,live,root))==4)
          for _,m in ipairs(members) do
            local x,z=Sim.xy(m.id)
            local _,base,top=T.tile(live.corner_grid,x,z)
            assert(base==S.tiles[m.id].h-1 and top==S.tiles[m.id].h)
          end
          formed=true
          phase="waiting for the four existing stadium pieces to repaint above new foundations"
        end)
      end)
    elseif (not exercise_foundation or formed) and not command and painted(true) then
      if exercise_foundation then
        core.log("action","STOCK HOUSE AUTOSLOPE NATIVE: same four stadium meshes, now resting on paid foundations")
      end
      command=true
      phase="quoting demolition from the child tile"
      ask({kind="terrain_quote",request={operation="bulldoze",first=members[4].id}},function(q)
        phase="committing the single demolition debit"
        expected_cost=q.value.cost
        assert(expected_cost>0)
        ask({kind="command",command={kind="terrain_commit",revision=q.revision,token=q.value.token}},function(r)
          assert(#r.value==4)
          local live=assert(checkpoint.read())
          assert(live.companies[owner].cash==cash-lower_cost-expected_cost)
          for _,m in ipairs(members) do assert(not live.tiles[m.id].source_house) end
          finished=true
          phase="waiting for the four tiles to repaint clean"
        end)
      end)
    elseif finished and not stopping and painted(false) then
      stopping=true
      phase="stopping the proven worker"
      assert(authority.query({kind="stop"},function() end))
    end
  end)
  hooks.present=painter.present
  local function tick()
    authority.step(.25,{{x=2*root.x,z=2*root.z,name=owner}},1)
    painter.step()
    core.after(.14,tick)
  end
  local caps={autoplay=true,seconds_per_day=.18,durable_actions=true}
  for k,value in pairs(api.capabilities) do if caps[k]==nil then caps[k]=value end end
  assert(authority.start(caps,Sim.W,Sim.H))
  tick()
  core.after(22,function()
    error(("Native stock town replay timed out %s (worker %s, football ground at %d,%d)")
      :format(phase,authority.status(),root.x,root.z))
  end)
end)
