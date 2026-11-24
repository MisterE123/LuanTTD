-- Shared stock tile graphics keep the same original City assets.
-- Only the three Metropolitan-only roles require new meshes.
return function(profile)
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
  local rows={}
  for _,t in ipairs(profile.tiles) do
    local x,z,role=unpack(t)
    local asset=assert(art[role],"Unknown Metropolitan tile graphic")
    -- The two ends of the arrival runway have different threshold numerals.
    if asset=="city_airport_0_5" and x==5 then asset="city_airport_5_5" end
    rows[z]=rows[z] or {}
    rows[z][x]={asset=asset,atlas=asset:match("^metro_") and "metropolitan_airport_atlas" or "city_airport_atlas",role=role}
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
