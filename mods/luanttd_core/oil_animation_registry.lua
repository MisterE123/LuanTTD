-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 src/animated_tile.cpp, native oil-well subset.
-- Ordered activation and deferred deletion are distinct. A stop leaves
-- its slot until the next animation pass removes it by swapping the tail.
local M={}
local function state(s)
  s.stock_oil_animated=s.stock_oil_animated or {}
  s.stock_oil_animation_order=s.stock_oil_animation_order or {}
  return s.stock_oil_animated,s.stock_oil_animation_order
end
function M.add(s,id)
  local members,order=state(s)
  if members[id] then return end
  for _,old in ipairs(order) do
    -- Re-activation before the deferred removal keeps the same slot.
    if old==id then members[id]=true;return end
  end
  order[#order+1],members[id]=id,true
end
function M.bind(s,tiles,run,random)
  local members,order=state(s)
  local present,missing={},{}
  for _,id in ipairs(order) do present[id]=true end
  for id,tile in pairs(tiles) do
    if tile.gfx>=30 and tile.gfx<=32 then
      if not present[id] then missing[#missing+1]=id end
      members[id]=true
    else members[id]=nil end
  end
  -- A checkpoint predating ordered animation can still recover genuine
  -- animated GFX, in stable map order. Ordinary new worlds record the
  -- actual activation order before their first checkpoint.
  table.sort(missing)
  for _,id in ipairs(missing) do order[#order+1]=id end
  for id in pairs(members) do if not tiles[id] then members[id]=nil end end
  return function(id,on)
    if on then M.add(s,id)
    else members[id]=nil end
  end,function(tick)
    local i=1
    while i<=#order do
      local id=order[i]
      if not members[id] then
        order[i]=order[#order]
        order[#order]=nil
      else
        local tile=assert(tiles[id],"Missing active oil well")
        if tick%8==0 then
          local changed,keep=run(tile,tick,random)
          if changed and not keep then members[id]=nil end
        end
        i=i+1
      end
    end
  end
end
return M
