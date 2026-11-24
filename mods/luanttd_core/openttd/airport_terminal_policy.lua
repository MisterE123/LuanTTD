-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. Direct port of FreeTerminal, GetNumTerminals,
-- AirportFindFreeTerminal and AirportFindFreeHelipad from aircraft_cmd.cpp
-- at OpenTTD 16.0-RC1. Wired to grouped airport profiles as a separate kernel.
return function(A)
  local M={}
  local groups=A.terminal_groups
  local max_terminals=8
  local termgroup=255
  local function any(a,b)
    while a>0 and b>0 do
      if a%2==1 and b%2==1 then return true end
      a,b=math.floor(a/2),math.floor(b/2)
    end
    return false
  end
  local function occupy(airport,vehicle,first,last)
    for i=first,last-1 do
      local map=A.terminal_mapping[i+1]
      if not any(airport.flags,map[2]) then
        vehicle.state=map[1]
        airport.flags=airport.flags+map[2]
        return true
      end
    end
    return false
  end
  function M.terminal(airport,vehicle)
    if #groups>1 then
      local row=A.layout[vehicle.pos]
      -- The C++ begins at layout[pos].next. The primary row is not a
      -- group reservation, even when it has heading TERMGROUP.
      for i=2,#row do
        local choice=row[i]
        if choice[1]~=termgroup then return false end
        if not any(airport.flags,choice[2]) then
          local group,start=choice[3]+1,0
          for j=1,group-1 do start=start+groups[j] end
          if occupy(airport,vehicle,start,start+groups[group]) then return true end
        end
      end
    end
    -- Stock falls back to all terminals only at the linked-list end.
    local total=0
    for _,count in ipairs(groups) do total=total+count end
    return occupy(airport,vehicle,0,total)
  end
  function M.helipad(airport,vehicle)
    if A.num_helipads==0 then return M.terminal(airport,vehicle) end
    return occupy(airport,vehicle,max_terminals,max_terminals+A.num_helipads)
  end
  return M
end
