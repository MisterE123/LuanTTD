-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1, animated_tile.cpp. Shared physical tile vector:
-- insertion order and swap-tail deletion matter to RNG-consuming actors.
local A={}
function A.new() return {order={},states={},roles={}} end
function A.add(a,id,role)
  if not a.states[id] then a.order[#a.order+1]=id end
  a.states[id],a.roles[id]=true,role
end
function A.delete(a,id,immediate)
  if not a.states[id] then return end
  if not immediate then a.states[id]="deleted";return end
  a.states[id],a.roles[id]=nil,nil
  for i,v in ipairs(a.order) do
    if v==id then
      a.order[i]=a.order[#a.order];a.order[#a.order]=nil
      return
    end
  end
end
function A.step(a,tick,animate)
  local i=1
  while i<=#a.order do
    local id=a.order[i]
    if a.states[id]~=true then
      a.states[id],a.roles[id]=nil,nil
      a.order[i]=a.order[#a.order];a.order[#a.order]=nil
    else
      if not animate(id,a.roles[id],tick) then A.delete(a,id,false) end
      i=i+1
    end
  end
end
return A
