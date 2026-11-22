-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors. No warranty.
-- OpenTTD 14.1 pathfinder/yapf/yapf_ship.cpp, yapf_node_ship.hpp,
-- yapf_base.hpp and table/settings/pathfinding_settings.ini.
-- Low-level tile search only; never invent a region corridor, direction
-- reversal, aimless route, docking slot or physical motion.
return function(Track,Water,SearchFactory)
  local C={TILE_LENGTH=100,TILE_CORNER_LENGTH=71,MAX_NODES=5120}
  local floor=math.floor
  local dirs_x,dirs_z={[0]=-1,0,1,0},{[0]=0,1,0,-1}
  C.default_settings={ship_curve45_penalty=100,ship_curve90_penalty=600}

  function C.curve_cost(prior,td,settings)
    settings=settings or {}
    if Track.has(Track.crossing_trackdirs(prior),td) then
      return settings.ship_curve90_penalty or C.default_settings.ship_curve90_penalty
    end
    if Track.next_trackdir(prior)~=td then
      return settings.ship_curve45_penalty or C.default_settings.ship_curve45_penalty
    end
    return 0
  end

  -- Board contract: docking_occupancy(tile) -> visible ship count (exclude
  -- aircraft and hidden/depot ships). speed fractions are stock 0..255
  -- penalties, where 0 is full vehicle speed; rivers are inland.
  function C.tile_cost(board,v,id,td,prior,skip,settings)
    local cost=Track.track(td)<2 and C.TILE_LENGTH or C.TILE_CORNER_LENGTH
    cost=cost+C.curve_cost(prior,td,settings)
    if Water.is_docking(board,id) and board.docking_occupancy then
      cost=cost+board.docking_occupancy(id)*3*C.TILE_LENGTH
    end
    cost=cost+C.TILE_LENGTH*skip
    local wc=assert(Water.water_class(board.tile(id)),"Navigable tile missing water class")
    local frac=(wc=="sea" and v.ocean_speed_frac or wc~="sea" and v.canal_speed_frac) or 0
    assert(frac>=0 and frac<=255 and frac%1==0,"Ship speed fraction must be a byte")
    if frac>0 then cost=cost+floor(C.TILE_LENGTH*(1+skip)*frac/(256-frac)) end
    return cost
  end

  -- For a ship order, closest_station_tile gives the same selection
  -- CalcClosestStationTile supplies for the heuristic. An optional
  -- region patch restriction supplies stock high-level output externally.
  -- The actual docking destination is independent of that heuristic tile.
  function C.destination(board,v,order)
    if order.kind=="station" then
      local id=order.tile or board.closest_station_tile(order.station,v.tile)
      if id==nil then return nil end
      return {kind="station",station=order.station,tile=id}
    end
    if order.kind=="region" then
      if not board.region or not board.region_patch or order.tile==nil then return nil end
      return {kind="region",tile=order.tile,region=order.region,patch=order.patch}
    end
    if order.tile==nil then return nil end
    return {kind="tile",tile=order.tile,trackdirs=Water.at(board,order.tile)}
  end

  function C.detect(board,d,id,td)
    if d.kind=="station" then return Water.ship_destination(board,id,d.station) end
    if d.kind=="region" then return board.region(id)==d.region and board.region_patch(id)==d.patch end
    return d.tile==id and Track.has(d.trackdirs,td)
  end

  function C.estimate(board,d,node)
    local id,td=node.last_tile,node.last_td
    if C.detect(board,d,id,td) then return node.cost end
    local a,b=board.xy(id)
    local x,z=board.xy(d.tile)
    local exit=Track.exit_side(td)
    local dx,dz=math.abs(2*a+dirs_x[exit]-2*x),math.abs(2*b+dirs_z[exit]-2*z)
    return node.cost+math.min(dx,dz)*C.TILE_CORNER_LENGTH+(math.abs(dx-dz)-1)*(C.TILE_LENGTH/2)
  end

  -- YAPF ships have one tile per node (except for a structure skip).
  -- The shared stock base's existing Lua API doesn't pass the follower
  -- result to the cost callback, so recompute the same pure transition.
  function C.calc(board,v,_,node,settings,max_cost,record)
    local parent=node.parent
    local f=Water.follow(board,v,parent.last_tile,parent.last_td)
    if not f.ok or f.tile~=node.tile or not Track.has(f.trackdirs,node.td) then return false end
    node.cost=parent.cost+C.tile_cost(board,v,node.tile,node.td,parent.last_td,f.skip,settings)
    if max_cost and max_cost>0 and node.cost>max_cost then return false end
    if record then record(node.tile,node.td) end
    return true
  end

  -- Reuse the exact OpenTTD base node set/heap and exit-dir based key via
  -- the general subset of yapf_road_search.lua. Ship search never enables
  -- "disable_node_optimization"; its stock specialization always uses the
  -- exit-dir key. The default 5120 is (4+1)*16^2*4, not road's 10000.
  local Adapter={trackdirs=Water.trackdirs,exit_direction=Water.exit_direction}
  function Adapter.follow(board,v,id,td)
    local f=Water.follow(board,v,id,td)
    if f.ok and board.region_corridor and not board.region_corridor[board.region(f.tile)] then
      f.ok=false -- CYapfFollowShipT allows children only in the corridor
    end
    return f
  end
  local Base=SearchFactory(Adapter,C)
  local function ship_settings(settings)
    local s={}
    for k,v in pairs(settings or {}) do s[k]=v end
    s.disable_node_optimization=false
    s.max_search_nodes=s.max_search_nodes or C.MAX_NODES
    return s
  end
  function C.find(board,v,origin,trackdirs,d,settings,options)
    if not d then return false,nil,{closed_count=0,capped=false} end
    return Base.find(board,v,origin,Track.intersect(trackdirs,Water.at(board,origin)),
      d,ship_settings(settings),options)
  end
  function C.trace(board,v,d,node,settings,options)
    return Base.trace(board,v,d,node,ship_settings(settings),options)
  end
  return C
end
