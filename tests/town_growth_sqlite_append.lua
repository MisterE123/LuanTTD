-- Appended to the real game init in an isolated Luanti world. The same
-- settings and production mount are exercised on both process starts.
do
  local F=dofile(mod.."/town_growth_live_fixture.lua")
  local specs=dofile(mod.."/openttd/town_passengers.lua").specs
  local function tile_nodes(id)
    local t=S.tiles[id]
    local x,z=Sim.xy(id)
    return core.get_node({x=2*x,y=t.h+1,z=2*z}).name,
      core.get_node({x=2*x+1,y=t.h,z=2*z+1}).name
  end
  core.register_on_mods_loaded(function()
    core.after(0,function()
      core.emerge_area({x=0,y=-16,z=0},{x=47,y=15,z=47},function(_,action,remaining)
        assert(action~=core.EMERGE_CANCELLED and action~=core.EMERGE_ERRORED)
        if remaining~=0 then return end
        core.after(0,function()
          local phase=core.settings:get("bayline_growth_fixture")
          if phase=="DEFAULT" then
            assert(not api.town_growth and not S.stock_town_growth)
            core.log("action","TOWN GROWTH SQLITE DEFAULT OFF")
          else
            assert(api.town_growth and S.stock_town_growth)
            local saw={}
            local ground
            local function visible()
              if S.changed then render.update(S.changed);S.changed=nil end
              local t=S.stock_town_growth.towns[1]
              if not t.last_build then return end
              local id=t.last_build.tile
              local title,neighbor=tile_nodes(id)
              local h=S.tiles[id].source_house
              ground=ground or neighbor
              assert(neighbor==ground and neighbor:match("^bayline:grass"),neighbor)
              if h.completed then
                assert(title:match("^bayline:scenery_house_") or title=="bayline:town_shop",title)
                saw.complete=true
              else
                assert(title=="bayline:house_build_stage_"..h.stage,title)
                saw[h.stage]=true
              end
            end
            if phase=="SAVE" then
              local qa=F.first(Sim,S,visible)
              assert(saw[0] and saw[1] and not saw[2])
              storage:set_string("growth_qa",core.serialize(qa))
              api.save()
              core.log("action",("TOWN GROWTH SQLITE SAVE REAL SERVICE; stage %d at tick %d"):format(qa.stage,qa.tick))
            else
              assert(phase=="RESTORE")
              local qa=assert(core.deserialize(storage:get_string("growth_qa"),true))
              assert(core.settings:get_bool("bayline_stock_town_growth",true)==false)
              visible()
              local h=F.second(Sim,S,qa,specs,visible)
              assert(saw[1] and saw[2] and saw.complete and not saw[0])
              core.log("action",("TOWN GROWTH SQLITE RESTORE COMPLETE; built %d, complete %d, first cargo %d")
                :format(h.built_tick,h.completed_tick,h.first_cargo_tick))
            end
          end
          core.request_shutdown("Stock town growth assertions passed",false,0)
        end)
      end)
    end)
  end)
end
