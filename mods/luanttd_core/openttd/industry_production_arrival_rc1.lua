-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 economy.cpp TriggerIndustryProduction.
-- Original industries do not install the NewGRF production callbacks.
-- The host owns the subsequent cargo-received random and animation hooks.
local M={}
local floor,min=math.floor,math.min

function M.apply(ind,multiplier,randomise,animate)
  ind.was_cargo_delivered=true
  local used,by_cargo=0,{}
  for input,a in ipairs(ind.accepted) do
    local amount=a.waiting
    if amount~=0 and a.cargo then
      local matrix=assert(multiplier[input],"Missing stock input multiplier row")
      for output,p in ipairs(ind.produced) do
        if p.cargo then
          p.waiting=min(65535,p.waiting+floor(amount*assert(matrix[output])/256))
        end
      end
      a.waiting=0
      used=used+amount
      by_cargo[a.cargo]=(by_cargo[a.cargo] or 0)+amount
    end
  end
  if randomise then randomise(ind,"cargo_received") end
  if animate then animate(ind,"cargo_received") end
  return used,by_cargo
end

return M
