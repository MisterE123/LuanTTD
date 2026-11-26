-- Native adapter for ordinary stock clear ground, sea, shore, trees and
-- the mounted standard railway half. Protected live routes aren't cut.
return function(Sim,Terrain,Flood,Track,Slope,RailWater)
  local W={}
  local adjacent_layers={"level_crossing_tiles","bridge_above","aqueduct_above","tunnel_below",
    "rail_bridge_above","rail_tunnel_below"}
  local function rail_ok(s,id,t)
    if not (RailWater and t.build=="stock_rail" and t.rail_tracks and (t.rail_type or 0)==0) then return false end
    if t.ship or t.tram or t.airfield or t.level_crossing or t.rail_waypoint_id or
        t.rail_depot_dir~=nil or t.rail_span_id then return false end
    for _,k in ipairs(adjacent_layers) do if s[k] and s[k][id] then return false end end
    return true
  end
  local function rail_remove_safe(s,id,allow_signal)
    local t=s.tiles[id]
    if t.signal or t.rail_reserved and t.rail_reserved~=0 or t.reserved_rail and t.reserved_rail~=0
        or s.stock_rail_run or s.stock_rail_platform_run then return false end
    local d=s.stock_rail_dispatch
    if not d then return true end
    if d.signals and d.signals.records and d.signals.records[id] and not allow_signal or
        d.life and d.life.claims and d.life.claims[id] then return false end
    for _,r in ipairs(d.runs or {}) do
      for _,p in ipairs(r.consist and r.consist.parts or {}) do if p.tile==id then return false end end
      if not r.crashed then
        if r.ordered_tiles and r.ordered_tiles[id] then return false end
        for _,p in ipairs(r.route or {}) do if p.tile==id then return false end end
      end
    end
    return true
  end
  local function floodable_object(t)
    local k=t.stock_landmark and t.stock_landmark.kind
    return k=="statue" or k=="lighthouse" or k=="transmitter" or k=="headquarters" or
      (t.stock_object and t.stock_object.kind=="owned_land")
  end
  local function protected(s,id,t)
    if t.ship or t.tram or t.airfield or t.station or t.house or t.site or t.stock_industry or t.stock_landmark or t.road_town or
      t.signal or t.rail_tracks or t.rail_span_id or t.road_bridge_id or t.road_tunnel_id or t.level_crossing then return true end
    for _,k in ipairs(adjacent_layers) do if s[k] and s[k][id] then return true end end
    return false
  end
  local function class(s,id,t)
    if not t then return end
    if t.stock_void then return "void" end
    if t.ship and t.ship.water_ground and t.ship.water_class=="sea" then return "station" end
    if rail_ok(s,id,t) then return "rail" end
    if t.build=="stock_rail_bridge" and t.rail_span_id then return "rail_bridge" end
    if t.build=="road_station" and t.station and t.stop_axis and (t.roadtype or 0)==0
        and not (t.road_stop_pair or t.tram or t.ship or t.airfield or t.rail_tracks or t.level_crossing) then
      for _,k in ipairs(adjacent_layers) do if s[k] and s[k][id] then return "protected" end end
      return "through_stop"
    end
    if floodable_object(t) and (t.terrain=="grass" or t.terrain=="hill") then
      for _,k in ipairs(adjacent_layers) do if s[k] and s[k][id] then return "protected" end end
      return "object"
    end
    if protected(s,id,t) then return "protected" end
    if t.build and t.build~="canal" then return "protected" end
    if t.build=="canal" or t.stock_canal then return "canal" end
    if t.wood then
      return type(t.wood)=="table" and not t.owner and "trees" or "protected"
    end
    if t.terrain=="water" then
      if t.coastal_water then return "coast" end
      return t.water_class or "sea"
    end
    if t.terrain=="grass" or t.terrain=="hill" then
      if not t.owner and not t.build then return "clear" end
    end
    return "protected"
  end
  function W.board(s)
    local B={}
    function B.tile(x,z)
      local id=Sim.id(x,z)
      local t=id and s.tiles[id]
      if not t then return end
      local kind=class(s,id,t)
      if kind=="protected" or kind=="canal" or kind=="river" then return {kind=kind} end
      local slope,base=Terrain.tile(s.corner_grid,x,z)
      if kind=="rail_bridge" then
        if slope~=0 or not B.bridge_ends then return {kind="protected"} end
        local other,water_z=B.bridge_ends(id)
        if not other then return {kind="protected"} end
        for _,k in ipairs(adjacent_layers) do
          if s[k] and (s[k][id] or s[k][other]) then return {kind="protected"} end
        end
        return {kind=kind,id=id,span=t.rail_span_id,slope=slope,base=base,other=other,water_z=water_z}
      end
      if kind=="rail" then
        local platform=t.rail_station_id~=nil
        if platform and (slope~=0 or not B.clear_platform or not B.clear_platform(id,false)) then return {kind="protected"} end
        local f,c=Track.foundation(slope,t.rail_tracks)
        if f=="invalid" then return {kind="protected"} end
        local adjusted,rise=Slope.foundation(slope,f,c)
        return {kind=kind,id=id,slope=slope,base=base,foundation_slope=adjusted,
          foundation_base=base+rise,platform=platform,tracks=t.rail_tracks,ground=t.rail_ground or 0,water_ground=t.rail_ground==13}
      end
      if kind=="through_stop" then return {kind=kind,id=id,slope=slope,base=base} end
      if kind=="object" then return {kind=kind,slope=slope,base=base,can_flood=true} end
      return {kind=kind,slope=slope,base=base,water_class=kind=="station" and "sea" or t.water_class,
        rocks=t.stock_water_rocks or (kind=="clear" and t.stock_clear_ground==2) or nil,
        water_ground=kind=="trees" and t.wood.ground==3 or nil}
    end
    function B.flood_road_stop(t)
      if not B.road_stop_flood or not B.clear_road_stop then return false end
      B.road_stop_flood(t.id,B.tick)
      return B.clear_road_stop(t.id,false,B.tick)
    end
    function B.flood_bridge(t)
      if not B.flood_vehicles or not B.clear_bridge then return false end
      B.flood_vehicles(t.id,B.tick,t.other,t.water_z)
      -- Both endpoints reference the bridge occupancy. Do not clear a
      -- wreck/claim or invalidate an active route the dispatcher can't yet replan.
      return rail_remove_safe(s,t.id) and rail_remove_safe(s,t.other)
    end
    if RailWater then
      function B.flood_rail(_,_,t)
        if B.flood_vehicles then B.flood_vehicles(t.id,B.tick) end
        -- Flat plots go through LandscapeClear as OWNER_WATER. Never
        -- clear under any body/claim or still-ordered unsupported actor.
        local function removable(removed)
          local allow=B.clear_signals and B.clear_signals(t.id,removed,false)
          return rail_remove_safe(s,t.id,allow)
        end
        if t.slope==0 then
          if removable() then return {kind="sea",platform=t.platform} end
          return
        end
        return RailWater.flood(t.slope,t.tracks,t.ground,removable)
      end
      function B.dry_rail(_,_,t)
        return {tracks=t.tracks,ground=RailWater.dry_ground(t.tracks)}
      end
    end
    return B
  end
  local function apply(t,kind,base,rocks)
    t.h=base
    t.stock_river_bits,t.stock_clear_ground,t.stock_clear_density,t.stock_water_rocks=nil,nil,nil,nil
    if kind=="clear" then
      t.terrain,t.water_class,t.coastal_water="grass",nil,nil
      t.owner=nil
      if t.build=="canal" then t.build=nil end
      t.stock_canal=nil
      if rocks then t.stock_clear_ground=2 end
    else
      t.terrain,t.water_class,t.coastal_water="water","sea",kind=="coast" and true or nil
      if rocks and kind=="coast" then t.stock_water_rocks=true end
    end
  end
  function W.visit(s,x,z,board,tick)
    if not s.corner_grid then return 0 end
    local source=Sim.id(x,z)
    local tile=source and s.tiles[source]
    if not tile then return 0 end
    if not (tile.rail_ground==13 and rail_ok(s,source,tile)) and
        (tile.terrain~="water" or not tile.coastal_water and (tile.stock_canal or
         tile.water_class=="river" or tile.water_class=="canal" or tile.build=="canal")) then return 0 end
    local B=board or W.board(s)
    B.tick=tick
    local changes=Flood.visit(B,x,z)
    if #changes==0 then return 0 end
    s.changed=s.changed or {}
    local cleared_spans,applied={},0
    for _,change in ipairs(changes) do
      local id=Sim.id(change.x,change.z)
      local t=assert(s.tiles[id])
      local actual=class(s,id,t)
      local changed=true
      -- Several adjacent eligible parcels of one HQ may have been
      -- quoted before the first parcel cleared the whole building.
      assert(actual==change.from or change.from=="object" and actual=="clear"
        or change.from=="rail_bridge" and cleared_spans[change.span] and actual=="clear")
      local _,base=Terrain.tile(s.corner_grid,change.x,change.z)
      if change.from=="rail" then
        local q=change.rail
        if (q.removed or q.kind=="sea") and B.clear_signals then
          assert(B.clear_signals(id,q.removed,true),"Unclearable rail signal on a committed tide tile")
        end
        if q.platform then
          assert(B.clear_platform(id,true),"Station footprint changed during a committed tide tile")
        end
        if q.kind=="coast" or q.kind=="sea" then
          t.rail_tracks,t.rail_ground,t.rail_type,t.build,t.owner=nil,nil,nil,nil,nil
          apply(t,q.kind,base)
        else
          t.rail_tracks,t.rail_ground=q.tracks,q.ground
        end
      elseif change.from=="through_stop" then
        -- An earlier parcel of this same station could have changed
        -- its active order guard. Do not commit a now-unsafe removal.
        changed=B.clear_road_stop(id,true,B.tick)
        if changed then apply(t,"sea",base) end
      elseif change.from=="rail_bridge" then
        if not cleared_spans[change.span] then
          for _,dirty in ipairs(assert(B.clear_bridge(id),"A quoted coastal rail bridge changed")) do
            if dirty~=id then s.changed[#s.changed+1]=dirty end
          end
          cleared_spans[change.span]=true
        end
        apply(t,"sea",base)
      elseif change.kind=="shore_trees" then
        apply(t,"coast",base)
        t.wood.ground,t.wood.density,t.wood.water_class=3,3,"sea"
      elseif change.kind=="dry_trees" then
        apply(t,"clear",base)
        t.wood.ground,t.wood.density,t.wood.water_class=0,3,nil
      else
        if change.from=="trees" then t.wood=nil end
        if change.from=="object" then
          local st=t.stock_landmark
          if st and st.kind=="headquarters" and Sim.hq_flood_clear then
            for _,parcel in ipairs(Sim.hq_flood_clear(s,st.owner,st.hq)) do
              if parcel~=id then s.changed[#s.changed+1]=parcel end
            end
          elseif st and st.kind=="statue" then
            local town=s.stock_town_growth and s.stock_town_growth.towns[st.town]
            if town and town.statues and town.statues[st.owner]==id then
              town.statues[st.owner]=nil
              s.stock_statue_count=math.max(0,(s.stock_statue_count or 1)-1)
            end
          end
          t.stock_object,t.stock_landmark,t.owner=nil,nil,nil
        end
        apply(t,change.kind,base,change.rocks)
      end
      if changed then s.changed[#s.changed+1]=id;applied=applied+1 end
    end
    if applied>0 then s.topology=(s.topology or 0)+1 end
    return applied
  end

  function W.is_water(t)
    return t and (t.terrain=="water" or t.build=="canal" or t.stock_canal)
  end

  local function quote(s,B,owner,id,x,z,occupied,terraform)
    local tile=s.tiles[id]
    local rec=B.tile(x,z)
    rec.owner=tile.owner
    rec.occupied=occupied and occupied(id)
    -- Stock Map::MaxX/Y is width/depth minus 1 (zero-based). The
    -- non-freeform test is IsInsideMM(coord,1,MaxX()-1), upper exclusive.
    local g=s.corner_grid
    local opts={owner=owner,clear_allowed=g.freeform_edges or
      x>=2 and z>=2 and x<=g.width-2 and z<=g.depth-2}
    if terraform then return Flood.terraform_water(rec,opts) end
    return Flood.clear_water(rec,opts)
  end

  function W.clear_quote(s,owner,id,occupied)
    local x,z=Sim.xy(id)
    if not W.is_water(s.tiles[id]) then return nil,"PROTECTED_TILE" end
    return quote(s,W.board(s),owner,id,x,z,occupied,false)
  end

  -- Tree tiles may retain a coast visual/underlying water class. RC1
  -- dispatches LandscapeClear to ClearTile_Trees for these parcels, not
  -- to ClearTile_Water. Keep actual facilities or active vessels protected.
  function W.road_tree_coast_quote(s,owner,id,occupied)
    local t=s.tiles[id]
    if t.owner and t.owner~=owner then return nil,"OWNED_BY_ANOTHER" end
    if t.stock_void or t.build or t.stock_canal or t.stock_object or protected(s,id,t) then
      return nil,"PROTECTED_TILE"
    end
    if occupied(id) then return nil,"VEHICLE_IN_THE_WAY" end
    return Sim.road_site_clear_cost(t)
  end

  function W.clear_apply(s,id)
    local t=s.tiles[id]
    local x,z=Sim.xy(id)
    local _,base=Terrain.tile(s.corner_grid,x,z)
    if t.stock_canal and t.owner then
      local owner=s.companies[t.owner]
      if owner then owner.water_infrastructure=math.max(0,(owner.water_infrastructure or 0)-1) end
    end
    apply(t,"clear",base)
  end

  -- TerraformTile_Water clearance participates in both native checks.
  -- Stage successful level-drag substeps without billing the same water
  -- twice. MP_VOID stores a height, not an MP_WATER record to clear.
  function W.terraform(s,owner,occupied)
    local changed={}
    local B=W.board(s)
    local A={}
    function A.quote(x,z)
      local id=Sim.id(x,z)
      if changed[id] then return 0 end
      return quote(s,B,owner,id,x,z,occupied,true)
    end
    function A.stage(step)
      for _,q in ipairs(step.dirty) do
        local id=Sim.id(q.x,q.z)
        local t=id and s.tiles[id]
        if W.is_water(t) and not t.stock_void then changed[id]=true end
      end
    end
    function A.commit(plan)
      A.stage(plan)
      for id in pairs(changed) do W.clear_apply(s,id) end
    end
    return A
  end
  return W
end
