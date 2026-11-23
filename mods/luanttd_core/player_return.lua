-- SPDX-License-Identifier: GPL-2.0-only
-- A world-local location per player. This is presentation state, not a
-- company or worker checkpoint; changing worlds never shares bookmarks.
return function(core,storage)
  local M={}
  local prefix="return_view_v1:"
  local function within(n,limit)
    return type(n)=="number" and n==n and math.abs(n)<=limit
  end
  local function valid(a)
    local p=type(a)=="table" and a.pos
    return type(p)=="table" and within(p.x,31000) and within(p.y,31000) and within(p.z,31000)
      and within(a.yaw,2*math.pi+.01) and within(a.pitch,math.pi/2+.01)
  end
  function M.read(player)
    local raw=storage:get_string(prefix..player:get_player_name())
    if raw=="" then return end
    local data=core.parse_json(raw)
    if valid(data) then return data end
  end
  function M.save(player,pos,yaw,pitch)
    local data={pos=pos,yaw=yaw,pitch=pitch}
    if not valid(data) then return false end
    storage:set_string(prefix..player:get_player_name(),core.write_json(data))
    return true
  end
  return M
end
