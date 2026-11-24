-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1: station_cmd.cpp CmdBuildRoadStop,
-- CalculateRoadStopCost, FindJoiningBaseStation and BuildStationPart;
-- road_gui.cpp PlaceRoad_BusStation / PlaceRoad_TruckStation.
return function(Stop)
  local A={}
  function A.footprint(board,first,last,dir,through,spread)
    if type(dir)~="number" or dir%1~=0 or dir<0 or dir>3 then return nil,"PARAMETERS" end
    local x,z=board.xy(first)
    local u,v=board.xy(last)
    if not (x and u) then return nil,"PARAMETERS" end
    if not through then
      -- The bay tool sizes along its prescribed strip in road_gui.
      if dir%2==0 then u=x else v=z end
    end
    local l,r,t,b=math.min(x,u),math.max(x,u),math.min(z,v),math.max(z,v)
    local w,h=r-l+1,b-t+1
    if w>spread or h>spread then return nil,"STATION_SPREAD" end
    local tile=board.id(l,t)
    if not tile or not board.id(r,b) then return nil,"PARAMETERS" end
    local ids={}
    for zz=t,b do for xx=l,r do ids[#ids+1]=assert(board.id(xx,zz)) end end
    return {tile=tile,w=w,h=h},ids
  end
  local function union(board,a,b)
    if not a then return b end
    local x,z=board.xy(a.tile)
    local u,v=board.xy(b.tile)
    local l,t=math.min(x,u),math.min(z,v)
    return {tile=board.id(l,t),w=math.max(x+a.w,u+b.w)-l,h=math.max(z+a.h,v+b.h)-t}
  end
  function A.find_join(board,area,over,company,join,adjacent,allow_distant)
    if join and (not allow_distant or not board.station(join)) then return nil,"INVALID_STATION_TO_JOIN" end
    if over and adjacent and over~=join then return nil,"MUST_REMOVE_ROAD_STOP_FIRST" end
    local selected=over and board.station(over) or nil
    if not selected and not adjacent then
      for _,id in ipairs(board.surrounding(area)) do
        local st=board.station(id)
        if st and st.owner==company then
          if selected and selected.id~=id then return nil,"ADJOINS_MULTIPLE_STATIONS" end
          selected=st
        end
      end
    end
    selected=selected or (join and board.station(join))
    if selected and selected.owner~=company then return nil,"OWNED_BY" end
    return selected
  end
  function A.quote(board,req,opts)
    local spread=opts.spread or 12
    local area,ids=A.footprint(board,req.first,req.last,req.dir,req.through,spread)
    if not area then return nil,ids end
    if board.authority then
      local ok,why=board.authority(area.tile)
      if not ok then return nil,why end
    end
    local over,z,price,edits=nil,nil,0,{}
    for _,id in ipairs(ids) do
      local row,why=Stop.tile(board.tile(id),req,opts,z)
      if not row then return nil,why end
      if over and row.station and over~=row.station then return nil,"ADJOINS_MULTIPLE_STATIONS" end
      over=over or row.station
      z=row.z
      price=price+row.cost
      edits[#edits+1]={id=id,station=row.station,z=row.z,cost=row.cost}
    end
    local st,why=A.find_join(board,area,over,opts.company,req.join,req.adjacent,opts.distant_join)
    if why then return nil,why end
    local extent=union(board,st and st.spread,area)
    if math.max(extent.w,extent.h)>spread then return nil,"STATION_SPREAD" end
    return {area=area,ids=ids,cost=price,z=z,changes=edits,join=st and st.id,spread=extent}
  end
  return A
end
