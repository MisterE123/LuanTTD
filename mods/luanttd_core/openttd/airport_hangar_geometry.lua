-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. Pinned airport.cpp GetVehiclePosOnBuild and
-- aircraft_cmd.cpp CmdBuildAircraft offsets, kept apart from ownership.
return function(A)
  local H={}
  local function get(i)
    return A.hangars and A.hangars[i+1]
  end
  function H.index(x,z)
    for i,v in ipairs(A.hangars) do
      if v[1]==x and v[2]==z then
        local at=i-1
        assert(A.layout[at][1][1]==1,"hangar rows must lead the stock board")
        return at,v[4],v[3]
      end
    end
  end
  function H.spawn(i)
    local v=get(i)
    if not v then return end
    return v[1]*16+5,v[2]*16+3,v[3]
  end
  function H.exit(i)
    local v=get(i)
    return v and v[3]
  end
  return H
end
