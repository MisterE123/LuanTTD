-- This source fixture keeps a hand-routed freight regression on exactly the
-- same map as its quoted production/debit goldens. Ordinary town generation
-- and eligibility of the full default roster are tested separately.
local original={[0x06]=true,[0x0E]=true,[0x18]=true,[0x19]=true,[0x1A]=true}
return function(target)
  if target.house then
    local raw=target.house
    function target.house(town,board,x,z,opts,random)
      local restricted=setmetatable({house_supported=function(id,a,b,spec)
        return original[id] and (not board.house_supported or board.house_supported(id,a,b,spec))
      end}, {__index=board})
      return raw(town,restricted,x,z,opts,random)
    end
  else
    for id in pairs(target) do
      if type(id)=="number" and not original[id] then target[id]=nil end
    end
  end
  return target
end
