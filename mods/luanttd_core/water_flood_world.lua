-- Native adapter for ordinary stock clear ground, sea, shore, trees and
-- the mounted standard railway half. Protected live routes aren't cut.
return function(Sim,Terrain,Flood,Track,Slope,RailWater)
  local W={}
  local adjacent_layers={"level_crossing_tiles","bridge_above","aqueduct_above","tunnel_below",
    "rail_bridge_above","rail_tunnel_below"}
  local function rail_ok(s,id,t)
    if not (RailWater and t.build=="stock_rail" and t.rail_tracks and (t.rail_type or 0)==0) then return false end
    if t.ship or t.tram or t.airfield or t.level_crossing or t.rail_station_id or t.rail_waypoint_id or
        t.rail_depot_dir~=nil or t.rail_span_id then return false end
    for _,k in ipairs(adjacent_layers) do if s[k] and s[k][id] then return false end end
    local x,z=Sim.xy(id)
    local shape=Terrain.tile(s.corner_grid,x,z)
    return shape~=0
  end
  local function rail_remove_safe(s,id)
    local t=s.tiles[id]
    if t.signal or t.rail_reserved and t.rail_reserved~=0 or t.reserved_rail and t.reserved_rail~=0
        or s.stock_rail_run or s.stock_rail_platform_run then return false end
    local d=s.stock_rail_dispatch
    if not d then return true end
    if d.signals and d.signals.records and d.signals.records[id] or
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
      if kind=="rail" then
        local f,c=Track.foundation(slope,t.rail_tracks)
        if f=="invalid" then return {kind="protected"} end
        local adjusted,rise=Slope.foundation(slope,f,c)
        return {kind=kind,id=id,slope=slope,base=base,foundation_slope=adjusted,
          foundation_base=base+rise,tracks=t.rail_tracks,ground=t.rail_ground or 0,water_ground=t.rail_ground==13}
      end
      if kind=="object" then return {kind=kind,slope=slope,base=base,can_flood=true} end
      return {kind=kind,slope=slope,base=base,water_class=kind=="station" and "sea" or t.water_class,
        rocks=t.stock_water_rocks or (kind=="clear" and t.stock_clear_ground==2) or nil,
        water_ground=kind=="trees" and t.wood.ground==3 or nil}
    end
    if RailWater then
      function B.flood_rail(_,_,t)
        return RailWater.flood(t.slope,t.tracks,t.ground,function() return rail_remove_safe(s,t.id) end)
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
  function W.visit(s,x,z,board)
    if not s.corner_grid then return 0 end
    local source=Sim.id(x,z)
    local tile=source and s.tiles[source]
    if not tile then return 0 end
    if not (tile.rail_ground==13 and rail_ok(s,source,tile)) and
        (tile.terrain~="water" or not tile.coastal_water and (tile.stock_canal or
         tile.water_class=="river" or tile.water_class=="canal" or tile.build=="canal")) then return 0 end
    local B=board or W.board(s)
    local changes=Flood.visit(B,x,z)
    if #changes==0 then return 0 end
    s.changed=s.changed or {}
    for _,change in ipairs(changes) do
      local id=Sim.id(change.x,change.z)
      local t=assert(s.tiles[id])
      local actual=class(s,id,t)
      -- Several adjacent eligible parcels of one HQ may have been
      -- quoted before the first parcel cleared the whole building.
      assert(actual==change.from or change.from=="object" and actual=="clear")
      local _,base=Terrain.tile(s.corner_grid,change.x,change.z)
      if change.from=="rail" then
        local q=change.rail
        if q.kind=="coast" then
          t.rail_tracks,t.rail_ground,t.rail_type,t.build,t.owner=nil,nil,nil,nil,nil
          apply(t,"coast",base)
        else
          t.rail_tracks,t.rail_ground=q.tracks,q.ground
        end
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
      s.changed[#s.changed+1]=id
    end
    s.topology=(s.topology or 0)+1
    return #changes
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
