-- SPDX-License-Identifier: GPL-2.0-only
-- A station view of the source climate industry pool. Do not persist a
-- second set of industry, construction, production or cargo records.
local M={}
local supported={[13]=true,[19]=true,[21]=true,[22]=true,[24]=true}
local cargo={[4]="fruit",[6]="maize",[9]="water",[11]="food"}
function M.bind(firms)
  local result={}
  for _,firm in ipairs(firms) do
    if supported[firm.type] then
      -- The views are used by the station adapter only. Economic writes
      -- (accepted waiting, output waiting, and delivery flags) go to the
      -- same physical rows that the source landscape subsequently reads.
      for _,p in ipairs(firm.produced) do p.cargo=assert(cargo[p.id]) end
      for _,p in ipairs(firm.accepted) do p.cargo=assert(cargo[p.id]) end
      result[firm.id]=setmetatable({tiles=firm.cells},{
        __index=firm,__newindex=firm,
      })
    end
  end
  return result
end
return M
