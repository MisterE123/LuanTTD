-- Start Luanti twice to prove migration doesn't depend on a UI binding
-- or in-memory path/timeline cache.
local path=core.get_modpath(core.get_current_modname()).."/"
local F=dofile(path.."road_oneway_live_fixture.lua")(path,dofile(path.."road_overtake_fixture.lua"))
local storage=core.get_mod_storage()
core.register_alias("mapgen_stone","air")
core.register_alias("mapgen_water_source","air")
core.register_on_mods_loaded(function()
  core.after(0,function()
    local raw=storage:get_string("checkpoint")
    if raw=="" then
      assert(core.settings:get_bool("luanttd_oneway_init",false))
      local s,car,dest=F.fixture()
      F.setup_sign(s)
      local index,x=F.held(s,car)
      storage:set_string("checkpoint",core.serialize({s=s,car=car,dest=dest,index=index,x=x}))
      core.log("action","ONEWAY SQLITE SAVE HOLD x="..x)
    else
      assert(not core.settings:get_bool("luanttd_oneway_init",false))
      local cp=assert(core.deserialize(raw,true))
      local s,car,dest=cp.s,cp.car,cp.dest
      assert(not F.Sim.road_motion_timeline(s,car))
      F.Sim.daily(s) -- no mounting; persisted stock sign is still authoritative
      local v=s.fleet[car]
      assert(v.road_speed_state.index==cp.index and F.Sim.road_motion_frame(s,v)[1]==cp.x)
      assert(v.road_speed_state.waiting=="oneway" and v.road_speed_state.oneway_tile==F.target)
      local ok,cost=F.World.build(s,F.owner,F.id(14,12),F.target,0)
      assert(ok and cost==0 and not s.tiles[F.target].road_disallowed)
      for _=1,12 do
        F.Sim.daily(s)
        if v.last_road_arrival_tick then break end
      end
      assert(v.last_road_arrival_tick and F.reached(s,car,dest))
      core.log("action","ONEWAY SQLITE RESTORE RESUME ARRIVED")
    end
    core.request_shutdown("One-way SQLite assertions completed",false,0)
  end)
end)
