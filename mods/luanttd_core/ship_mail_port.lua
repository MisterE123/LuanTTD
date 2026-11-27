-- SPDX-License-Identifier: GPL-2.0-only
-- Dry-ship Mail admission only. The shared town Mail allocator and
-- translated LoadUnloadStation own all production, visits and payments.
return function(Sim,Port,Catchment,Houses)
  local M={profile={name="Mail",load="Mail pickup",unload="Mail delivery",sink="town"}}
  function M.enabled(s)
    return s.road_stock_house_supply and Sim.road_stock_service_active(s)
  end
  function M.id(run)
    assert(run.paid_clock and run.paid_clock<0x4000,"Mail ship vehicle ID range exhausted")
    return 0x18000+run.paid_clock
  end
  function M.report(s,network,id)
    if not M.enabled(s) then return end
    local _,rows=Port.bind_stations(s,{stations={}},network.board(s),function(i)return i==id end)
    local st=rows[id]
    if not st then return end
    local cover=Catchment.build(st,Sim.W,Sim.H,s.stock_modified_catchment)
    local function house(x,z)
      local tile=s.tiles[Sim.id(x+1,z+1)]
      return tile and tile.house and tile.source_house or nil
    end
    local r=Catchment.acceptance(cover,"mail",house)
    r.accepts=r.eighths>=8
    local sources={}
    for key in pairs(cover.tiles) do
      local h=house(key%cover.width,math.floor(key/cover.width))
      local spec=h and h.completed and Houses.specs[h.id]
      if spec and spec[2]>0 and h.town then sources[h.town]=true end
    end
    r.sources={}
    for town in pairs(sources) do r.sources[#r.sources+1]=town end
    table.sort(r.sources)
    return r
  end
  return M
end
