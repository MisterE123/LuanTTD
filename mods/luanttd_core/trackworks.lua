-- Explicit source rail topology, independent of the legacy rail prototype.
return function(Sim,Track,Follow,Slope,Costs,Search,shape_at)
  local Lab={}
  local pieces={x=0,y=1,upper=2,lower=3,left=4,right=5}
  function Lab.piece(word) return pieces[word] end
  function Lab.span_protected(s,id)
    if id==nil then return false end
    local t=s.tiles[id]
    return t and (t.rail_span_id~=nil or t.level_crossing~=nil) or s.rail_bridge_above and s.rail_bridge_above[id]~=nil or
      s.rail_tunnel_below and s.rail_tunnel_below[id]~=nil or false
  end
  local protected="That tile is protected railway infrastructure."

  local grades={[3]=1,[12]=2,[6]=3,[9]=4}
  function Lab.surface(shape,base,bits)
    local kind,corner=Track.foundation(shape,bits)
    if kind=="invalid" or kind=="rail" or kind=="half" or kind=="steep_both" or kind=="steep_lower" then return end
    local surface,rise=Slope.foundation(shape,kind,corner)
    if surface==0 then return 0,base+rise,kind end
    local axis=surface==3 or surface==12
    if grades[surface] and bits==(axis and 1 or 2) then
      return grades[surface],base+rise,kind,surface
    end
  end
  function Lab.station_bounds(s,st)
    if st.area then return st.area end
    local lo_x,lo_z,hi_x,hi_z=math.huge,math.huge,-math.huge,-math.huge
    for _,id in ipairs(st.tiles) do
      local x,z=Sim.xy(id)
      lo_x,lo_z,hi_x,hi_z=math.min(lo_x,x),math.min(lo_z,z),math.max(hi_x,x),math.max(hi_z,z)
    end
    return {x=lo_x,z=lo_z,w=hi_x-lo_x+1,h=hi_z-lo_z+1}
  end
  function Lab.board(s)
    return {
      tile=function(id)
        local t=s.tiles[id]
        if t and t.rail_tracks then
          return {kind=t.rail_station_id and "station" or t.rail_waypoint_id and "waypoint" or t.rail_depot_dir and "depot" or "rail",
            trackbits=t.rail_tracks,owner=t.owner,railtype=t.rail_type or 0,
            station=t.rail_station_id or t.rail_waypoint_id,axis=t.rail_station_axis or t.rail_waypoint_axis,dir=t.rail_depot_dir,
            slope=shape_at and shape_at(id) or 0}
        end
      end,
      adjacent=function(id,d) return Sim.adjacent(id,4-d) end,
      xy=Sim.xy,tile_at=Sim.id,
      station_area=function(id,kind)
        local st=(kind=="waypoint" and s.stock_rail_waypoints or kind~="waypoint" and s.stock_rail_stations or {})[id]
        if st then
          local area=Lab.station_bounds(s,st)
          return {tile=Sim.id(area.x,area.z),w=area.w,h=area.h},st.tiles[1]
        end
      end,
    }
  end
  function Lab.station_plan(s,owner,first,last)
    if not first or not last then return false,"Select two in-map platform ends." end
    local ax,az=Sim.xy(first)
    local bx,bz=Sim.xy(last)
    if ax~=bx and az~=bz then return false,"A platform must follow one straight axis." end
    local axis=az==bz and 0 or 1
    if first==last then
      if s.tiles[first].rail_tracks==2 then axis=1 end
    end
    local count=math.abs(ax-bx)+math.abs(az-bz)+1
    if count>7 then return false,"Use one to seven connected platform tiles." end
    local dx,dz=axis==0 and 1 or 0,axis==1 and 1 or 0
    local group={}
    for i=0,count-1 do
      local id=Sim.id(math.min(ax,bx)+i*dx,math.min(az,bz)+i*dz)
      local t=s.tiles[id]
      if Lab.span_protected(s,id) then return false,protected end
      if t.owner~=owner or t.rail_tracks~=2^axis or t.rail_station_id or t.rail_waypoint_id or t.rail_depot_dir or
          (shape_at and shape_at(id)~=0) then
        return false,"All platform tiles must be flat, owned, plain straight track."
      end
      group[#group+1]=id
    end
    return true,group,axis
  end
  function Lab.commit_station(s,owner,group,axis,area,join)
    for _,tile in ipairs(group) do
      if Lab.span_protected(s,tile) then return false,protected end
    end
    s.stock_rail_stations=s.stock_rail_stations or {}
    local id=join or s.next_stock_rail_station or 1
    local st=join and s.stock_rail_stations[join]
    if join then
      if not st or st.owner~=owner then return false,"Station changed; select the footprint again." end
      local merged,seen={},{}
      for _,set in ipairs({st.tiles,group}) do
        for _,tile in ipairs(set) do
          if not seen[tile] then seen[tile]=true;merged[#merged+1]=tile end
        end
      end
      table.sort(merged)
      st.tiles,st.area=merged,area
    else
      s.next_stock_rail_station=id+1
      st={id=id,owner=owner,axis=axis,tiles=group,area=area}
      s.stock_rail_stations[id]=st
    end
    for _,tile in ipairs(group) do
      local t=s.tiles[tile]
      t.rail_station_id=id;t.rail_station_axis=axis
      t.build,t.owner,t.rail_tracks,t.wood="stock_rail",owner,2^axis,nil
    end
    s.topology=s.topology+1
    return true,("Rail station #%d: %d platform tile(s)."):format(id,#group),group
  end
  function Lab.station(s,owner,first,last)
    local ok,group,axis=Lab.station_plan(s,owner,first,last)
    if not ok then return false,group end
    return Lab.commit_station(s,owner,group,axis)
  end
  function Lab.waypoint_at(s,tile)
    local t=s.tiles[tile]
    local wp=t and t.rail_waypoint_id and (s.stock_rail_waypoints or {})[t.rail_waypoint_id]
    return wp and wp.tile==tile and wp or nil
  end
  function Lab.commit_waypoint(s,owner,tile,axis,remove)
    local t=s.tiles[tile]
    if not t or t.owner~=owner or t.rail_tracks~=2^axis or Lab.span_protected(s,tile) or
        t.rail_station_id or t.rail_depot_dir then return false,"Choose owned, plain straight track." end
    if remove then
      local wp=Lab.waypoint_at(s,tile)
      if not wp or wp.axis~=axis then return false,"Choose your rail waypoint." end
      s.stock_rail_waypoints[wp.id]=nil
      t.rail_waypoint_id,t.rail_waypoint_axis=nil,nil
    else
      if t.rail_waypoint_id then return false,"A waypoint already stands on this tile." end
      -- Stations and waypoints share OpenTTD's BaseStation ID pool.
      local id=s.next_stock_rail_station or 1
      s.next_stock_rail_station=id+1
      s.stock_rail_waypoints=s.stock_rail_waypoints or {}
      s.stock_rail_waypoints[id]={id=id,owner=owner,axis=axis,tile=tile,tiles={tile}}
      t.rail_waypoint_id,t.rail_waypoint_axis=id,axis
    end
    s.topology=s.topology+1
    return true,remove and "Waypoint removed; the rail remains." or "Rail waypoint built.",{tile}
  end
  function Lab.depot_plan(s,owner,id,dir)
    if Lab.span_protected(s,id) then return false,protected end
    local t=s.tiles[id]
    if not t or type(dir)~="number" or dir%1~=0 or dir<0 or dir>3 or
      t.owner~=owner or t.rail_tracks~=2^(dir%2) or t.rail_station_id or t.rail_waypoint_id or t.rail_depot_dir or
      (shape_at and shape_at(id)~=0) then
      return false,"Select a flat, owned straight at the end of a line."
    end
    local board=Lab.board(s)
    local portal=board.tile(board.adjacent(id,dir))
    local rear=board.tile(board.adjacent(id,Track.reverse_side(dir)))
    if not portal or portal.owner~=owner or Track.intersect(Track.status(portal),Track.reachable(dir))==0 or
        (rear and Track.intersect(Track.status(rear),Track.reachable(Track.reverse_side(dir)))~=0) then
      return false,"The depot needs connected track at the front but not at the rear."
    end
    return true,{id}
  end
  function Lab.commit_depot(s,owner,id,dir)
    if Lab.span_protected(s,id) then return false,protected end
    local t=s.tiles[id]
    t.build,t.owner,t.rail_tracks,t.rail_depot_dir,t.wood="stock_rail",owner,2^(dir%2),dir,nil
    s.topology=s.topology+1
    return true,"Rail depot placed.",{id}
  end
  function Lab.depot(s,owner,id,dir)
    local ok,msg=Lab.depot_plan(s,owner,id,dir)
    if not ok then return false,msg end
    return Lab.commit_depot(s,owner,id,dir)
  end
  function Lab.remove_facility(s,owner,id)
    if Lab.span_protected(s,id) then return false,protected end
    local t=s.tiles[id]
    if not t or t.owner~=owner then return false,"Select your rail facility." end
    local group={id}
    if t.rail_station_id then
      local st=s.stock_rail_stations[t.rail_station_id]
      group=st.tiles
      for _,tile in ipairs(group) do
        if Lab.span_protected(s,tile) then return false,protected end
      end
      s.stock_rail_stations[st.id]=nil
      for _,tile in ipairs(group) do
        s.tiles[tile].rail_station_id=nil
        s.tiles[tile].rail_station_axis=nil
      end
    elseif t.rail_depot_dir then
      if Lab.owned_depot_occupied and Lab.owned_depot_occupied(s,id) then
        return false,"The depot contains a purchased train."
      end
      t.rail_depot_dir=nil
    else return false,"No rail facility on that tile." end
    s.topology=s.topology+1
    return true,"Rail facility removed; track retained.",group
  end
  function Lab.service_route(s,owner,origin,station)
    local tracks=Lab.board(s)
    local t=tracks.tile(origin.tile)
    local dest=(s.stock_rail_stations or {})[station]
    if not (t and t.owner==owner and dest and dest.owner==owner and t.station~=station) then return end
    local td=origin.td or (t.kind=="depot" and Track.diagonal_trackdir(t.dir))
    if not td or not Track.has(Track.status(t),td) then return end
    if t.kind=="depot" and Track.exit_side(td)~=t.dir then return end
    local v={tile=origin.tile,owner=owner,compatible={[0]=true,[1]=true},railtype=0,max_speed=80,length=8}
    local target=Costs.destination(tracks,v,{kind="station",station=station})
    local found,best=Search.find(tracks,v,{tile=origin.tile,td=td},target)
    if not found then return end
    local trace=Search.trace(tracks,v,best)
    local dense={}
    for _,match in ipairs(trace) do
      local f=match.follow
      if f and f.station and f.skip>0 then
        local id=f.station_entry
        for _=1,f.skip do
          dense[#dense+1]={tile=id,td=match.td}
          id=tracks.adjacent(id,f.exit)
        end
        assert(id==match.tile)
      end
      dense[#dense+1]={tile=match.tile,td=match.td}
    end
    return dense,best.cost
  end
  function Lab.plan(s,start,goal,owner)
    if start==goal then return end
    local tracks=Lab.board(s)
    local a,b=tracks.tile(start),tracks.tile(goal)
    if not (a and b and a.owner==owner and b.owner==owner and b.slope==0) then return end
    local v={tile=start,owner=owner,compatible={[0]=true,[1]=true},railtype=0,max_speed=80,length=16}
    local best,best_board
    local all=Track.trackdirs(a.trackbits)
    -- Survey a one-tile test platform on the requested straight, not a
    -- plain-tile dead end (OpenTTD does not treat that as a train order).
    -- This is a temporary search goal; no station is created in the world.
    for axis=0,1 do
      if Track.has(b.trackbits,axis) then
        local board={
          tile=function(id)
            if id==goal then return {kind="station",axis=axis,station=1,owner=owner,railtype=b.railtype,slope=0} end
            return tracks.tile(id)
          end,
          adjacent=tracks.adjacent,xy=tracks.xy,tile_at=tracks.tile_at,
          station_area=function() return {tile=goal,w=1,h=1},goal end,
        }
        local destination=Costs.destination(board,v,{kind="station",station=1})
        -- No vehicle is running, so survey both starting directions.
        for td=0,13 do
          if Track.valid_trackdir(td) and Track.has(all,td) then
            local found,node=Search.find(board,v,{tile=start,td=td},destination)
            if found and (not best or node.cost<best.cost) then best,best_board=node,board end
          end
        end
      end
    end
    if not best then return end
    return Search.trace(best_board,v,best),best.cost
  end
  function Lab.inspect(s,id,owner)
    local board=Lab.board(s)
    local tile=board.tile(id)
    if not tile or tile.owner~=owner then return end
    local all=Track.trackdirs(tile.trackbits)
    local count=0
    for td=0,13 do
      if Track.valid_trackdir(td) and Track.has(all,td) and
          Follow.follow(board,{owner=owner,compatible={[0]=true,[1]=true}},id,td).ok then
        count=count+1
      end
    end
    return tile.trackbits,count
  end
  function Lab.piece_plan(s,owner,id,track,remove,shape)
    if Lab.span_protected(s,id) then return false,protected end
    local t=s.tiles[id]
    if not t then return false,"That tile is outside the region." end
    if shape==nil or t.stock_void or t.terrain=="water" or t.site or t.house or t.tram or t.ship or t.airfield or t.stock_industry or t.stock_landmark or
        (t.build and t.build~="stock_rail") or (t.owner and t.owner~=owner) or t.rail_station_id or t.rail_waypoint_id or t.rail_depot_dir then
      return false,"Trackworks currently needs clear, dry ground in your company."
    end
    if not Track.valid_trackdir(track) or track>=6 then return false,"Invalid track piece." end
    local old=t.rail_tracks or 0
    local bit=Track.trackbit(track)
    local new=remove and Track.remove(old,bit) or Track.union(old,bit)
    if new==old then return false,"That track piece is already in the requested state." end
    if t.rail_type==1 and new>0 and new~=1 and new~=2 and new~=4 and new~=8 and new~=16 and new~=32 then
      return false,"Convert to ordinary rail before adding a junction."
    end
    if new>0 and not Lab.surface(shape,0,new) then
      return false,"This piece needs a supported foundation. Try flat ground or a straight track aligned with the slope."
    end
    return true,{id=id,tracks=new,prior=old,shape=shape,track=track,remove=remove}
  end
  function Lab.commit_piece(s,owner,plan)
    if Lab.span_protected(s,plan.id) then return false,protected end
    local t=s.tiles[plan.id]
    local new=plan.tracks
    t.build=new>0 and "stock_rail" or nil
    t.owner=new>0 and owner or nil
    t.rail_tracks=new>0 and new or nil
    if new==0 then t.rail_type=nil end
    t.wood=nil
    s.topology=s.topology+1
    return true
  end
  function Lab.change(s,owner,id,track,remove,shape)
    local ok,p=Lab.piece_plan(s,owner,id,track,remove,shape)
    if not ok then return false,p end
    return Lab.commit_piece(s,owner,p)
  end
  return Lab
end
