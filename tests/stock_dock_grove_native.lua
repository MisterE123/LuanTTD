local owner="StockResidentialQA"
local function begin()
  local player=core.get_player_by_name(owner)
  if not (player and authority and authority.status()=="owned" and #world.hotbar_layout(player)>0) then
    core.after(.25,begin);return
  end
  local function query(q,callback)
    q.player=owner
    assert(authority.query(q,function(r) assert(r.ok,r.why);callback(r) end))
  end
  local function checkpoint() return assert(OwnerCheckpoint.read()) end
  local Track=dofile(mod.."/openttd/rail_track.lua")
  local Terrain=dofile(mod.."/openttd/terrain.lua")
  local Water=dofile(mod.."/openttd/ship_follow.lua")(Track)
  local Net=dofile(mod.."/ship_network.lua")(Sim,Terrain,Water,dofile(mod.."/openttd/ship_facilities.lua")(Track,Water))
  local function look(id)
    local x,z=Sim.xy(id)
    local p={x=x*2-5,y=7,z=z*2+6}
    local d=vector.direction(vector.add(p,{x=0,y=1.625,z=0}),{x=x*2+.5,y=.2,z=z*2+.5})
    player:set_pos(p);player:set_look_horizontal(core.dir_to_yaw(d));player:set_look_vertical(-math.asin(d.y))
  end
  if core.settings:get_bool("luanttd_qa_dock_grove_reopen",false) then
    local save=core.deserialize(storage:get_string("stock_dock_grove_qa"),true)
    local s=checkpoint()
    local record=s.stock_ship_stations[save.station]
    assert(record.land==save.land and s.tiles[save.land].stock_clear_density==0 and not s.tiles[save.land].wood)
    assert(s.companies[owner].stock_town_authority_ratings[save.town]==save.rating)
    core.log("action","PASS NATIVE DOCK GROVE REOPEN")
    return
  end
  local s=checkpoint()
  local best,town_id,stems
  for id,t in pairs(s.tiles) do
    if t.wood then
      local p=Net.quote(s,owner,"dock",id)
      if p then
        local town,d=Sim.road_tree_authority().nearest(s,id)
        if town and d<(s.stock_road_town_policy.dist_local_authority or 20) then
          local n=type(t.wood)=="table" and t.wood.count or 1
          if n and (not stems or n>stems or n==stems and id<best) then best,town_id,stems=id,town.id,n end
        end
      end
    end
  end
  assert(best,"No ordinary priced wooded slope in town range")
  local req={mode="ship",operation="build",kind="dock",tile=best}
  -- Pause the ordinary clock before obtaining the construction quote
  -- used for the comparison, so a month tick can't change town rating.
  query({kind="transport_quote",request=req},function(first)
    query({kind="command",command={kind="speed",speed=0,revision=first.revision}},function()
      look(best)
      core.after(2.3,function()
        core.log("action","NATIVE DOCK GROVE BEFORE")
        core.after(1.6,function()
          local before=checkpoint()
          local c=before.companies[owner]
          local initial=c.stock_town_authority_ratings and c.stock_town_authority_ratings[town_id] or 500
          query({kind="transport_quote",request=req},function(q)
            assert(q.value.cost==350+stems*20,q.value.cost)
            assert(before.tiles[best].wood and not before.tiles[best].ship)
            query({kind="command",command={kind="transport_commit",token=q.value.token,revision=q.revision}},function(built)
              local after=checkpoint()
              local company=after.companies[owner]
              assert(company.cash==c.cash-q.value.cost and company.stock_town_authority_ratings[town_id]==initial-35)
              local id=assert(built.value.id)
              assert(after.stock_ship_stations[id].land==best and not after.tiles[best].wood)
              storage:set_string("stock_dock_grove_qa",core.serialize({station=id,land=best,town=town_id,rating=initial-35}))
              core.after(2.5,function()
                core.log("action",("PASS NATIVE DOCK GROVE %d stems, $%d, town -35, shore %d"):format(stems,q.value.cost,best))
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end
core.after(.25,begin)
