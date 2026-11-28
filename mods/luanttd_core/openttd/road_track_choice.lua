-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors. No warranty.
-- Ordinary bus/truck subset of OpenTTD 16.0-RC1 RoadFindPathToDest,
-- CYapfFollowRoadT::ChooseRoadTrack and YapfRoadVehicleChooseTrack.
-- Stock RV movement code consumes the reverse state; it is not a normal
-- trackdir. Caller should handle red crossing signals after this choice.
return function(F,C,S)
  local R={}
  local reverse_td={[0]=6,7,14,15}
  local function clear(cache)
    for i=#cache,1,-1 do cache[i]=nil end
  end
  local function allowed(board,v,tile,entry,settings)
    local t=board.tile(tile)
    if not t then return 0 end
    if t.kind=="depot" and (t.owner~=v.owner or t.dir==entry) then return 0 end
    if t.kind=="bay_stop" then
      if t.owner~=v.owner or t.dir==entry or v.articulated or
          t.stop_type~=(v.bus and "bus" or "truck") then return 0 end
      if settings.roadveh_queue==false and not board.bay_free(tile,0) and
          not board.bay_free(tile,1) then return 0 end
    end
    local reachable=F.reachable_trackdirs(entry)
    local out=0
    for _,td in ipairs(F.trackdirs(F.status(t,false))) do
      if F.has_trackdir(reachable,td) then out=out+2^td end
    end
    return out
  end

  -- Station adapter: cache_trimmed_station_area(station, stop_type, vehicle)
  -- -> {tile,w,h}, nil otherwise. Only supply when the primary stop is a
  -- drive-through or another usable stop exists. Area is the unexpanded
  -- stock station area; the eight-tile margin is applied here.
  local function append_choices(board,v,d,best,found,origin,cache)
    if not best then return nil end
    local nodes={}
    while best.parent do nodes[#nodes+1]=best;best=best.parent end
    for i=#nodes,math.max(#nodes-7,1),-1 do
      local n=nodes[i]
      if n.is_choice then cache[#cache+1]={tile=n.tile,td=n.td} end
    end
    if found and #cache>0 and origin==v.dest_tile then cache[#cache]=nil end
    if d.kind=="station" and board.cache_trimmed_station_area and #cache>0 then
      local area=board.cache_trimmed_station_area(d.station,d.stop_type,v)
      if area and area.tile~=nil then
        local x,y=board.xy(area.tile)
        while #cache>0 do
          local ax,ay=board.xy(cache[#cache].tile)
          if ax<x-8 or ay<y-8 or ax>=x+area.w+8 or ay>=y+area.h+8 then break end
          cache[#cache]=nil
        end
      end
    end
    return best.td
  end

  -- Return td, path_found (nil when search wasn't needed), reason. Stock
  -- random choice for vehicles without orders uses the adapter's RNG.
  -- no destination is passed as nil instead of relying on tile index 0.
  function R.choose(board,v,tile,entry,order,cache,settings)
    settings=settings or {}
    local function finish(td,path_found,reason)
      if board.red and board.red(tile,td) then return nil,path_found,"signal" end
      return td,path_found,reason
    end
    local tds=F.trackdirs(allowed(board,v,tile,entry,settings))
    if #tds==0 then clear(cache);return finish(reverse_td[entry],nil,"reverse") end
    if v.reverse_requested then
      v.reverse_requested=false
      if v.tile~=tile then return finish(reverse_td[entry],nil,"reverse") end
    end
    if not order then return finish(tds[board.random_range(#tds)+1],nil,"unordered") end
    if #tds==1 then
      if cache[1] and cache[1].tile==tile then clear(cache) end
      return finish(tds[1],nil,"unique")
    end
    if cache[1] then
      local first=cache[1]
      if first.tile==tile then
        for _,td in ipairs(tds) do
          if td==first.td then table.remove(cache,1);return finish(td,nil,"cached") end
        end
      end
      clear(cache)
    end
    if order.kind~="station" and tile==order.tile then
      return finish(F.direction_trackdir(entry),true,"destination")
    end
    local d=C.destination(board,v,order)
    local mask=F.origin_trackdirs(board.tile(tile),false,entry)
    local found,best=S.find(board,v,tile,mask,d,settings)
    local td=append_choices(board,v,d,best,found,tile,cache)
    local selected,result,why=finish(td or tds[1],found,"search")
    return selected,result,why,best,d
  end

  return R
end
