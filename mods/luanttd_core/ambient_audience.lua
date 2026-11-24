-- SPDX-License-Identifier: GPL-2.0-only
-- A conservative camera cone, not an occlusion test. Bounded by the
-- existing scenic actor caps; capture each player's pose once per sweep.
local A={}
local cone_squared=math.cos(math.rad(65))^2
function A.capture(players,enabled)
  local viewers,watchers={},{}
  for _,p in ipairs(players) do
    if enabled(p) then
      local at=p:get_pos()
      if at then
        local look=p.get_look_dir and p:get_look_dir()
        -- No object-property copies or raycasts: the widened cone and
        -- near-distance guard absorb approximate eye/third-person offsets.
        viewers[#viewers+1]={player=p,at=at,eye=at.y+1.4,look=look}
        watchers[p:get_player_name()]=true
      end
    end
  end
  return viewers,watchers
end

function A.visible(viewers,at,radius,near)
  local max2,near2=radius^2,(near or 6)^2
  for _,v in ipairs(viewers) do
    local x,y,z=at.x-v.at.x,at.y-v.eye,at.z-v.at.z
    local ds=x*x+y*y+z*z
    -- Cover near-peripheral movement and third-person camera offsets.
    if ds<=near2 then return true end
    if ds<max2 and v.look then
      local l=v.look
      local dot=x*l.x+y*l.y+z*l.z
      if dot>0 and dot*dot>=ds*cone_squared then return true end
    end
  end
  return false
end

function A.retire(actor,viewers,at,radius,dt)
  if #viewers==0 or not at then return true end
  if A.visible(viewers,at,radius) then
    actor.ambient_unseen=0
    return false
  end
  actor.ambient_unseen=(actor.ambient_unseen or 0)+dt
  return actor.ambient_unseen>=.85
end

function A.same_set(a,b)
  for n in pairs(a) do if not b[n] then return false end end
  for n in pairs(b) do if not a[n] then return false end end
  return true
end
return A
