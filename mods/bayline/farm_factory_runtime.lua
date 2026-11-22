-- SPDX-License-Identifier: GPL-2.0-only
-- Bind farm/factory to the real landscape and station loader callbacks.
-- Reuse the isolated industry's verified staged receipt protocol; this
-- does not run a second economy clock, town demand or cargo settlement.
return function(Rules,Fields,IndustryRuntime,Catchment)
  local M={}
  function M.new() return IndustryRuntime(Rules,Catchment).new() end
  function M.bind(world,ledger,ctx)
    if ctx.random_u32 then
      for _,ind in pairs(ctx.industries) do
        if ind.kind=="farm" and not ind.removed then
          assert(ctx.field_board or ctx.field_attempt,"Farm shares an RNG; supply the real field attempt callbacks")
          break
        end
      end
    end
    local adapted=setmetatable({}, {__index=Rules})
    function adapted.production_tick(ind,opts)
      if ctx.field_board then
        opts.field_attempt=function(farm,rnd) Fields.random(farm,ctx.field_board,rnd) end
      else
        opts.field_attempt=ctx.field_attempt
      end
      return Rules.production_tick(ind,opts)
    end
    local B=IndustryRuntime(adapted,Catchment).bind(world,ledger,ctx)
    local coverage={}
    for _,st in ipairs(ctx.stations) do
      coverage[st.id]=ctx.coverage and ctx.coverage[st.id] or Catchment.build(st,ctx.width,ctx.height,ctx.modified)
    end
    function B.covered(id,x,z)
      local c=coverage[id]
      return c and Catchment.contains(c,x,z) or false
    end
    function B.plant_on_built(ind)
      assert(ctx.field_board and ctx.random_u32,"Stock farm creation must share terrain and RNG")
      return Fields.on_built(ind,ctx.field_board,ctx.random_u32)
    end
    return B
  end
  return M
end
