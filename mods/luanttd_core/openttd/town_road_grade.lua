-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors; 16.0-RC1 town_cmd.cpp, IsRoadAllowedHere.
-- The existing (possibly founded) slope and neighbor test are inputs.
-- The native command adapter owns only legal terrain effects.
return function(chance)
  local M={}
  function M.allowed(slope,direction,room,generating,random,terraform,x,z)
    if slope==0 then return room end
    local desired=direction%2==0 and 12 or 9 -- NE on X; NW on Y
    if slope~=desired and slope~=15-desired then
      if not chance(1,8,random()) then return false end
      local success=false
      if not generating and chance(1,10,random()) then
        local low=slope%16 -- DoCommand applies only corner bits
        local mask=chance(1,16,random()) and low or 15-low
        success=not not terraform(x,z,mask,false,nil,random)
      end
      if not success and chance(1,3,random()) then return room end
      return false
    end
    return room
  end
  return M
end
