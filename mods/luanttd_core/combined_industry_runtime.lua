-- Bind mounted stock industries to one Goods queue, acceptance and
-- LoadUnloadStation receipt ledger. Production rules still belong to the
-- translated per-industry kernels. No second economy or movement clock.
return function(Timber,Farm,Oil,Fields,Runtime,Catchment)
  local K={cargo={},trucks={},spec={},ordered=Farm.ordered}
  local by_kind={}
  for _,rules in ipairs({Timber,Farm,Oil}) do
    for kind,def in pairs(rules.spec or {}) do K.spec[kind]=def;by_kind[kind]=rules end
    for cargo,def in pairs(rules.cargo) do K.cargo[cargo]=def end
    for cargo,def in pairs(rules.trucks) do K.trucks[cargo]=def end
  end
  -- Timber's early kernel has a one-cargo struct rather than a fixed
  -- array. Do not change either layout just to mount them together.
  by_kind.forest,by_kind.sawmill=Timber,Timber
  local by_cargo={wood=Timber,goods=Timber,oil=Oil,grain=Farm,livestock=Farm,iron_ore=Farm,steel=Farm,valuables=Farm}
  function K.allowed_source(st,i)
    local r=assert(by_kind[i.kind],i.kind)
    if r.allowed_source then return r.allowed_source(st,i) end
    return st.serve_neutral~=false or st.neutral_rig==nil
  end
  function K.output(i,cargo)
    local r=assert(by_kind[i.kind],i.kind)
    if r==Timber then return i.produced.cargo==cargo and i.produced or nil end
    return r.output(i,cargo)
  end
  function K.queue(st,cargo) return assert(by_cargo[cargo]).queue(st,cargo) end
  function K.goods(st,cargo) return assert(by_cargo[cargo]).goods(st,cargo) end
  function K.acceptance(st,c,cargo,all,house)
    local r=assert(by_cargo[cargo])
    local list={}
    for _,i in ipairs(all) do if by_kind[i.kind]==r then list[#list+1]=i end end
    return r.acceptance(st,c,cargo,list,house)
  end
  function K.deliver(st,report,packet,industry,opts)
    return assert(by_cargo[packet.cargo]).deliver(st,report,packet,industry,opts)
  end
  function K.trigger(ind) return assert(by_kind[ind.kind]).trigger(ind) end
  function K.distribute(ind,cargo,amount,all,covers,opts)
    -- A designated rail station has a separate single-cargo loader;
    -- other cargo must compete among compatible stations only. Road truck
    -- stops share the same physical queues, regardless of source chain.
    local compatible={}
    for _,st in ipairs(all) do
      if (not st.freight_cargo or st.freight_cargo==cargo) and K.allowed_source(st,ind) then compatible[#compatible+1]=st end
    end
    return assert(by_kind[ind.kind]).distribute(ind,cargo,amount,compatible,covers,opts)
  end

  local M={}
  local footprints=setmetatable({},{__mode="k"})
  function M.new() return Runtime(K,Catchment).new() end
  function M.bind(s,ledger,ctx)
    -- These three stock kernels share ProduceIndustryGoods's 16-bit
    -- clock. Off the sound/production phases the counter is their
    -- only write; no industry callback is mounted for these firms.
    local A=setmetatable({counter_only_quiet_slot=true}, {__index=K})
    local board=ctx.field_board
    local attempt=board and function(farm,rnd) Fields.random(farm,board,rnd) end
    function A.production_tick(i,opts)
      if i.kind=="farm" and attempt then opts.field_attempt=attempt end
      return assert(by_kind[i.kind]).production_tick(i,opts)
    end
    function A.tile_loop(i,t,opts,offer)
      if i.kind=="oil_well" then opts.random_u32,opts.animated,opts.stock_tile_animation=ctx.random_u32,ctx.animated,ctx.stock_tile_animation end
      if i.kind=="oil_rig" then opts.complete_rig=ctx.complete_rig end
      local sprite=t.gfx
      local n,moved,details=assert(by_kind[i.kind]).tile_loop(i,t,opts,offer)
      if i.kind=="forest" and t.gfx~=sprite and ctx.forestry_changed then ctx.forestry_changed(t) end
      return n,moved,details
    end
    function A.month(i,year,opts)
      local policy=opts.policy and opts.policy[i.kind] or nil
      if policy then for k,v in pairs(policy) do opts[k]=v end end
      return assert(by_kind[i.kind]).month(i,year,opts)
    end
    -- Built-in footprint coordinates never move within a firm. Reuse
    -- across day bindings only; stock placement/removal may replace it.
    local cache=footprints[s]
    if not cache then cache={};footprints[s]=cache end
    return Runtime(A,Catchment).bind(s,ledger,ctx,cache)
  end
  return K,M
end
