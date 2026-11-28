-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 economy.cpp DeliverGoodsToIndustry
-- and DeliverGoods. The host provides the already ordered catchment list.
local D={}
local min=math.min

function D.to_industries(st,cargo,pieces,source,near,industry_at,input_at,options)
  options=options or {}
  local left=pieces
  local served={}
  for _,c in ipairs(near) do
    if left==0 then break end
    local ind=industry_at(c.id)
    if ind and not ind.removed and ind.id~=source then
      local entry=input_at(ind,cargo)
      if entry and (not options.refuses or not options.refuses(ind,cargo))
          and (ind.exclusive_supplier==nil or ind.exclusive_supplier==st.owner) then
        if options.enqueue then options.enqueue(ind) end
        local count=min(left,65535-entry.waiting)
        entry.waiting=entry.waiting+count
        if options.history then options.history(entry,count) end
        entry.last_accepted=options.economy_date
        left=left-count
        served[#served+1]={id=ind.id,units=count}
        if options.monitor then options.monitor(st,ind,cargo,count) end
      end
    end
  end
  return pieces-left,served
end

function D.acceptance_split(pieces,industrial,always_accepted)
  local total=always_accepted and pieces or industrial
  return total,total-industrial
end

return D
