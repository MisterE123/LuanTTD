-- Stock generated worker: fund a living town through the normal priced
-- action and watch a real existing parcel turn over, not scripted tiles.
local owner="StockResidentialQA"
local Terrain=dofile(mod.."/openttd/terrain.lua")
local Art=dofile(mod.."/stock_town_art.lua")
local function begin()
  local player=core.get_player_by_name(owner)
  if not (player and authority and authority.status()=="owned" and #world.hotbar_layout(player)>0) then
    core.after(.2,begin);return
  end
  local raw=assert(OwnerCheckpoint.read())
  if core.settings:get_bool("luanttd_qa_town_rebuild_restart",false) then
    local saved=assert(core.deserialize(storage:get_string("town_rebuild_qa"),true))
    local function verify(left)
      local live=assert(OwnerCheckpoint.read())
      local t=live.stock_town_growth.towns[saved.town]
      local h=live.tiles[saved.id].source_house
      assert(t and type(t.time_until_rebuild)=="number" and h and h.id==saved.expected and h.built_tick==saved.built)
      local x,z=Sim.xy(saved.id)
      local _,_,top=Terrain.tile(live.corner_grid,x,z)
      player:set_pos({x=2*x-3,y=top+4,z=2*z-5})
      player:set_look_horizontal(math.atan2(-3.5,5.5));player:set_look_vertical(.62)
      local asset=h.asset_root and ("%s_%d"):format(Art.asset_name(h.asset_root,0),h.asset_part)
        or Art.asset_name(h.id,Art.look(h.id,x,z))
      local actual={}
      if h.completed then
        -- Different stock parcel looks use distinct registered meshes.
        -- Match the exact asset on the same tile, regardless of the
        -- entrance anchor chosen by the separate frontage renderer.
        local name="luanttd_core:"..asset
        for dx=0,1 do for dz=0,1 do
          local node=core.get_node_or_nil({x=2*x+dx,y=top+1,z=2*z+dz})
          if node and node.name==name then
            assert(core.registered_nodes[name].mesh=="bl_"..asset..".obj")
            core.log("action","PASS NATIVE TOWN REBUILD REOPEN: same parcel finished and rendered "..asset)
            return
          end
          actual[#actual+1]=node and node.name or "unloaded"
        end end
      end
      assert(left>0,("Replacement %d after reopen: completed=%s expected=%s actual=%s")
        :format(saved.id,tostring(h.completed),asset,table.concat(actual,",")))
      core.after(.35,function() verify(left-1) end)
    end
    -- A genuine RC1 replacement needs 24 root visits. Use the ordinary
    -- 4× simulation control on this disposable reopened world instead of
    -- assuming the old, much shorter construction clock.
    local function begin_verification()
      assert(authority.query({kind="company",player=owner},function(row)
        assert(row.ok,row.why)
        assert(authority.query({kind="command",player=owner,
          command={kind="speed",speed=4,revision=row.revision}},function(reply)
          assert(reply.ok,reply.why)
          verify(205)
        end))
      end))
    end
    core.after(.45,begin_verification)
    return
  end
  local town
  for _,id in ipairs(raw.stock_town_growth.order) do
    local t=raw.stock_town_growth.towns[id]
    if not town or t.num_houses>town.num_houses then town=t end
  end
  assert(town and town.num_houses>15,"No sizable stock town to fund")
  local function query(req,f)
    req.player=owner
    assert(authority.query(req,function(r) assert(r.ok,r.why);f(r) end))
  end
  local function command(c,f)
    query({kind="company"},function(row)
      c.revision=row.revision
      query({kind="command",command=c},f)
    end)
  end
  local function fund(needed)
    query({kind="company"},function(row)
      if row.value.cash<needed then
        command({kind="company_loan",amount=10000},function() fund(needed) end)
        return
      end
      local before=assert(OwnerCheckpoint.read())
      local roots={}
      for id,tile in ipairs(before.tiles) do
        local h=tile.source_house
        if tile.house and h and h.town==town.id and h.root and h.completed then
          roots[id]=h
        end
      end
      assert(next(roots))
      command({kind="town_fund_buildings",town=town.id,cost=needed},function()
        local funded=assert(OwnerCheckpoint.read())
        assert(funded.stock_town_growth.towns[town.id].growing)
        assert(funded.companies[owner].expense==before.companies[owner].expense+needed)
        local function watch(n)
          local live=assert(OwnerCheckpoint.read())
          local status=live.stock_town_growth.towns[town.id]
          if status.time_until_rebuild>20 then
            for id,old in pairs(roots) do
              local h=live.tiles[id].source_house
              if h and h.built_tick and h.built_tick~=old.built_tick and h.id~=old.id then
                storage:set_string("town_rebuild_qa",core.serialize({
                  town=town.id,id=id,expected=h.id,built=h.built_tick,
                }))
                local x,z=Sim.xy(id)
                local _,_,top=Terrain.tile(live.corner_grid,x,z)
                local cam={x=2*x-3,y=top+4,z=2*z-5}
                player:set_pos(cam)
                player:set_look_horizontal(math.atan2(-3.5,5.5));player:set_look_vertical(.62)
                core.log("action",("NATIVE TOWN REBUILD RECEIPT: plot %d old=%02x current=%s cooldown=%d company expense=%d")
                  :format(id,old.id,h and ("%02x"):format(h.id) or "clear",status.time_until_rebuild,live.companies[owner].expense))
                core.after(3.1,function()
                  core.log("action","NATIVE TOWN REBUILD FRAME: live municipal renewal, found existing parcel")
                  core.after(1.45,function()core.log("action","PASS NATIVE TOWN REBUILD: paid ordinary town growth triggered one real stock parcel renewal")end)
                end)
                return
              end
            end
          end
          assert(n>0,"Funded town did not execute source renewal after its completed-house countdown")
          core.after(.26,function()watch(n-1)end)
        end
        watch(210)
      end)
    end)
  end
  query({kind="town_authority",town=town.id},function(r) fund(assert(r.value.funding and r.value.funding.cost)) end)
end
core.after(.2,begin)
