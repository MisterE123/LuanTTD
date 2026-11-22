-- SPDX-License-Identifier: GPL-2.0-only
-- Replay-safe station pulses for oil and refinery Goods. The shared
-- station scan, landscape cursor, renderer and RNG remain host-owned.
return function(Rules,IndustryRuntime,Catchment)
  local M={}
  function M.new() return IndustryRuntime(Rules,Catchment).new() end
  function M.bind(s,ledger,ctx)
    local adapted=setmetatable({}, {__index=Rules})
    function adapted.tile_loop(i,t,opts,offer)
      opts.random_u32,opts.animated=ctx.random_u32,ctx.animated
      return Rules.tile_loop(i,t,opts,offer)
    end
    return IndustryRuntime(adapted,Catchment).bind(s,ledger,ctx)
  end
  return M
end
