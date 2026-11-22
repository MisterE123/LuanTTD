-- Copied only into isolated native test installs; never part of the game.
return function(settings,mod)
  local seeded=settings:get_bool("luanttd_qa_coastal_layout",false)
  local plain=settings:get_bool("luanttd_qa_plain_layout",false)
  local scenario=settings:get("bayline_scenario")
  for _,item in ipairs({{"farm","bayline_road_farm_preview"},{"oil","bayline_road_oil_preview"},
      {"coastal","bayline_stock_coastal_flood"},{"south_coast","bayline_ship_coal_coastal_scenario"}}) do
    if not scenario and settings:get_bool(item[2],false) then scenario=item[1] end
  end
  local qa={enabled=seeded or plain or (scenario and scenario~="generated"),scenario=scenario,
    interval=tonumber(settings:get("bayline_seconds_per_day")),
    explorer=settings:get_bool("bayline_original_terrain_exploration",false)}
  if seeded then
    qa.terrain=function(Sim,Terrain,s,grid)
      if s.seed~=1751 then return grid end
      local generated,stats=dofile(mod.."/qa_coastal_corridor.lua")(Sim,Terrain,s,grid)
      s.qa_coastal,s.stock_coastal_profile=stats,true
      return generated
    end
  end
  return qa
end
