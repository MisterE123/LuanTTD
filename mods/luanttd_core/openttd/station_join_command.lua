-- SPDX-License-Identifier: GPL-2.0-only
-- Translated from OpenTTD 16.0-RC1 station_cmd.cpp: GetStationAround,
-- FindJoiningBaseStation, BuildStationPart and CmdBuildAirport.
-- Command-side selection, not the GUI's spiral list of distant choices.
local M={BUS=4,AIRPORT=8}
local min,max=math.min,math.max

local function valid_area(board,area,spread)
  if area.w<1 or area.h<1 then return false end
  local x,z=board.xy(area.tile)
  if not board.id(x,z) or not board.id(x+area.w-1,z+area.h-1) then return false end
  if area.w>spread or area.h>spread then return false,"STATION_TOO_SPREAD_OUT" end
  return true
end

local function combined_ok(board,area,old,spread)
  if not old or old.w==0 or old.h==0 then return true end
  local x,z=board.xy(area.tile)
  local u,v=board.xy(old.tile)
  return max(x+area.w,u+old.w)-min(x,u)<=spread and max(z+area.h,v+old.h)-min(z,v)<=spread
end

-- Invalid StationID is nil; NEW_STATION is represented separately.
-- Callers own the placement/terrain check. The adapter supplies station
-- lookup by physical tile and pool ID, and optional retired-station lookup.
function M.find(board,area,owner,p)
  local explicit=p.join_id
  if p.new_station then explicit=nil end
  local chosen,check_surrounding
  if p.existing_id~=nil then
    if p.allow_adjacent and p.existing_id~=explicit then
      return nil,p.overlap_error or "MUST_REMOVE_RAILWAY_STATION_FIRST"
    end
    local candidate=board.station(p.existing_id)
    if candidate and board.matches(candidate) then chosen=candidate end
    check_surrounding=chosen==nil
  else
    check_surrounding=not p.allow_adjacent
  end
  if check_surrounding then
    local x,z=board.xy(area.tile)
    for v=z-1,z+area.h do
      for u=x-1,x+area.w do
        local t=board.id(u,v)
        local st=t and board.station_at(t)
        if st and st.owner==owner and board.matches(st) then
          if not chosen then chosen=st
          elseif chosen.id~=st.id then return nil,"ADJOINS_MORE_THAN_ONE_EXISTING" end
        end
      end
    end
  end
  if not chosen and explicit~=nil then chosen=board.station(explicit) end
  return chosen
end

-- Country and larger airports share the same join command. Terrain and
-- town-authority checks remain the owning airport command's responsibility.
function M.airport_target(board,area,owner,p)
  if not p.new_station and p.join_id~=nil and
      (not p.distant or not board.station(p.join_id)) then return nil,"INVALID_STATION" end
  local ok,why=valid_area(board,area,p.spread)
  if not ok then return nil,why or "INVALID_STATION_AREA" end
  local st
  st,why=M.find(board,area,owner,p)
  if why then return nil,why end
  if not st and not p.new_station and board.closest_deleted then
    st=board.closest_deleted(area.tile,owner)
  end
  if not st then return false end -- allocate a fresh station
  if st.owner~=owner then return nil,"NOT_STATION_OWNER" end
  if not combined_ok(board,area,st.spread,p.spread) then return nil,"STATION_TOO_SPREAD_OUT" end
  if st.airport then return nil,"TOO_CLOSE_TO_ANOTHER_AIRPORT" end
  return st
end
-- Station::AddFacility (station.cpp). The caller has already committed
-- to building, and computes the physical spread after adding the facility.
-- In particular, an occupied station keeps the sign & random bits: never
-- burn a Random word just because a different transport mode is attached.
function M.add_facility(st,kind,tile,owner,build_date,random_word)
  local facilities=st.facilities or 0
  if facilities==0 then
    local word=random_word()
    st.tile,st.random_bits=tile,word%65536
  end
  if facilities%(kind*2)<kind then facilities=facilities+kind end
  st.facilities,st.owner,st.build_date=facilities,owner,build_date
  return st
end
return M
