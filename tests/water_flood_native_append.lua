-- Appended only to a private test copy of normal game init. The actual
-- stock coastal settings, /landscape and production renderer are used.
do
  local Terrain=dofile(mod.."/openttd/terrain.lua")
  local function assert_ground(x,z,kind)
    local t=S.tiles[Sim.id(x,z)]
    local slope,base=Terrain.tile(S.corner_grid,x,z)
    assert(t.terrain==kind and slope==0 and base==0)
    local actual=core.get_node({x=2*x,y=0,z=2*z}).name
    assert(actual=="bayline:"..kind..t.variant,actual)
  end
  local function shore_count()
    local n=0
    for z=26,33 do for x=9,15 do
      local t=S.tiles[Sim.id(x,z)]
      if t.coastal_water then
        local mask,base=Terrain.tile(S.corner_grid,x,z)
        local actual=core.get_node({x=2*x,y=base+1,z=2*z}).name
        assert(actual==("bayline:stock_shore_%d_%d"):format(mask,t.variant),actual)
        n=n+1
      end
    end end
    return n
  end
  core.register_on_mods_loaded(function()
    core.after(0,function()
      core.emerge_area({x=10,y=-3,z=24},{x=34,y=14,z=72},function(_,kind,left)
        assert(kind~=core.EMERGE_CANCELLED and kind~=core.EMERGE_ERRORED)
        if left~=0 then return end
        core.after(0,function()
          assert(api.coastal_flood_tools and S.stock_coastal_flood and S.stock_coastal_profile)
          local phase=core.settings:get("bayline_water_flood_native_phase")
          if phase=="SAVE" then
            local command=assert(core.registered_chatcommands.landscape).func
            local run,reply=command("ShoreQA","level 11 33 13 28")
            assert(run and reply:find("$3750",1,true) and not reply:find("partial",1,true),reply)
            run,reply=command("ShoreQA","lower 8 17 10 19")
            assert(run and reply:find("$2250",1,true),reply)
            assert_ground(12,28,"grass");assert_ground(9,18,"grass")
            run,reply=command("ShoreQA","lower 9 18")
            assert(not run and reply:find("Already at sea level.",1,true))
            local day
            for i=1,24 do
              Sim.daily(S)
              if S.changed then render.update(S.changed);S.changed=nil end
              if S.tiles[Sim.id(12,28)].terrain=="water" then day=day or i end
            end
            assert(day and day>1 and day<=12)
            assert_ground(12,28,"water");assert_ground(9,18,"grass")
            local shores=shore_count()
            assert(shores>=9)
            api.save()
            core.log("action",("COASTAL LANDSCAPING NATIVE SAVE: bay wet day %d, %d real shore meshes, dry inland at 0")
              :format(day,shores))
          else
            assert(phase=="RESTORE" and S.day==24 and S.passenger_house_clock.counter==24*74)
            assert_ground(12,28,"water");assert_ground(9,18,"grass")
            assert(shore_count()>=9)
            core.log("action","COASTAL LANDSCAPING NATIVE RESTORE: same coastline and landscape cursor")
          end
          core.request_shutdown("Coastal landscaping native proof finished",false,0)
        end)
      end)
    end)
  end)
end
