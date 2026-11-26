do
  local bay=core.settings:get_bool("luanttd_qa_coastal_road_bay",false)
  local F=dofile(mod.."/qa_coastal_road_stop.lua")(Sim,dofile(mod.."/openttd/terrain.lua"),
    dofile(mod.."/openttd/town_passengers.lua"),dofile(mod.."/campaign_road_construction.lua"),bay)
  core.after(0,function()
    local proof=S.road_flood_native
    if not proof then
      S.road_flood_native=F.start(S)
      api.save()
      core.log("action","ROAD_FLOOD_NATIVE_SAVED_WRECK")
      core.request_shutdown("Saved a real bus wreck at its through stop",false,0)
      return
    end
    assert(F.finish(S,proof))
    api.save()
    core.log("action","ROAD_FLOOD_NATIVE_PASS reserved riders destroyed, wreck reloaded, pavement submerged only once clear")
    core.request_shutdown("The bus wreck retired and the dry stop survived",false,0)
  end)
end
