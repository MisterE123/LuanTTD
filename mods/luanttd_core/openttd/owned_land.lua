-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 contributors, object_cmd.cpp CmdBuildObject,
-- CmdBuildObjectArea, ClearTile_Object, company_cmd.cpp; table/object_land.h.
-- The native host owns LandscapeClear, dirty tiles, and company accounting.
return function(Area)
  local K={unit=65536,rate=32*65536,burst=2048}
  function K.price(base)
    return (base or 40)*10
  end
  function K.resale(base)
    return math.floor((base or 40)*10/5)
  end
  function K.replenish(allowed,frames)
    return math.min((allowed or K.burst*K.unit)+frames*K.rate,K.burst*K.unit)
  end
  function K.quote(grid,x,z,u,v,diagonal,opts)
    if not opts.towns then return nil,"MUST_FOUND_TOWN_FIRST" end
    local iter=assert(Area.points(grid,u,v,x,z,diagonal))
    local q={items={},cost=0}
    local limit=K.replenish(opts.allowance,0)
    local tries=math.floor(limit/K.unit)
    local clear,remaining=opts.clear_allowance,opts.cash
    local last="SITE_UNSUITABLE"
    for a,b in iter do
      if tries<=0 then last="BUILD_OBJECT_LIMIT_REACHED";break end
      tries=tries-1
      local tile,err=opts.tile(a,b)
      if tile and tile.kind=="owned_land" then
        last=tile.owner==opts.owner and "YOU_ALREADY_OWN_IT" or "OWNED_BY_ANOTHER"
      elseif tile and tile.bridge_above then last="MUST_DEMOLISH_BRIDGE_FIRST"
      elseif tile then
        if clear<K.unit then last="CLEARING_LIMIT_REACHED"
        else
          local debit,why=opts.clear(tile)
          if debit==nil then last=why
          else
            local cost=K.price(opts.build_price)+debit
            if cost>0 and remaining<cost then last="NOT_ENOUGH_MONEY";break end
            q.items[#q.items+1]={tile=tile,cost=cost}
            q.cost=q.cost+cost
            remaining=remaining-cost
            clear=clear-K.unit
            limit=limit-K.unit
          end
        end
      else last=err or "SITE_UNSUITABLE" end
    end
    if #q.items==0 then return nil,last end
    q.allowance,q.clear_allowance=limit,clear
    return q
  end
  return K
end
