-- Stock tile artwork is shared by graphic role, not by layout footprint.
return function(profile,layout)
  local A={}
  local art={
    [0]="city_airport_4_1", -- APT_APRON
    [1]="city_airport_1_0", -- APT_APRON_FENCE_NW
    [2]="city_airport_5_1", -- APT_APRON_FENCE_SW
    [3]="city_airport_1_2", -- APT_STAND
    [5]="city_airport_1_4", -- APT_APRON_S
    [12]="city_airport_4_2", -- APT_APRON_HOR
    [13]="city_airport_5_2", -- APT_APRON_N_FENCE_SW
    [15]="city_airport_2_5", -- APT_RUNWAY_2
    [18]="city_airport_0_5", -- APT_RUNWAY_END_FENCE_SE
    [19]="city_airport_0_1", -- APT_BUILDING_2
    [20]="city_airport_5_3", -- APT_TOWER_FENCE_SW
    [21]="city_airport_2_1", -- APT_ROUND_TERMINAL
    [22]="city_airport_0_2", -- APT_BUILDING_3
    [23]="city_airport_0_0", -- APT_BUILDING_1
    [24]="city_airport_5_0", -- APT_DEPOT_SE
    [25]="city_airport_2_0", -- APT_STAND_1
    [26]="city_airport_3_1", -- APT_STAND_PIER_NE
    [27]="city_airport_2_2", -- APT_PIER_NW_NE
    [28]="city_airport_1_1", -- APT_PIER
    [45]="metro_runway_end", -- APT_RUNWAY_END
    [46]="metro_runway_5", -- APT_RUNWAY_5
    [52]="metro_radar_fence_ne", -- APT_RADAR_FENCE_NE
  }
  if layout=="commuter" or layout=="international" or layout=="intercontinental" then
    art[48]="commuter_apron_fence_ne"
    art[47]="commuter_tower"
    art[54]="commuter_helipad_2_fence_nw"
  end
  if layout=="international" or layout=="intercontinental" then
    local hub={
      [0]="apron", [1]="apron_fence_nw", [2]="apron_fence_sw",
      [3]="stand", [48]="apron_fence_ne",
      [29]="grass", [49]="runway_end_fence_nw", [50]="runway_fence_nw",
      [51]="radar_fence_sw", [53]="helipad_1", [55]="helipad_2", [56]="apron_fence_ne_sw",
      [57]="runway_end_fence_nw_sw", [58]="runway_end_fence_se_sw", [59]="runway_end_fence_ne_nw",
      [60]="runway_end_fence_ne_se", [65]="apron_fence_se", [69]="low_building",
      [71]="apron_half_east", [72]="apron_half_west", [73]="flag_perimeter",
    }
    for role,asset in pairs(hub) do art[role]="hub_"..asset end
    art[32]="city_airport_0_3"
  end
  local rows={}
  for _,t in ipairs(profile.tiles) do
    local x,z,role=unpack(t)
    local asset=assert(art[role],"Unknown stock airport tile graphic")
    -- The two ends of the arrival runway have different threshold numerals.
    if asset=="city_airport_0_5" and x==profile.W-1 then asset="city_airport_5_5" end
    rows[z]=rows[z] or {}
    rows[z][x]={asset=asset,atlas=asset:match("^metro_") and "metropolitan_airport_atlas" or asset:match("^commuter_") and "commuter_airport_atlas" or asset:match("^hub_") and "hub_airport_atlas" or "city_airport_atlas",role=role}
  end
  A.rows=rows
  function A.missing(files)
    for z=0,profile.H-1 do for x=0,profile.W-1 do
      local row=rows[z][x]
      local mesh,tex="bl_"..row.asset..".obj","bl_"..row.atlas..".png"
      if not files[mesh] then return mesh end
      if not files[tex] then return tex end
    end end
  end
  return A
end
