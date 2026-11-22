-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, no warranty. Pinned OpenTTD 14.1:
-- src/tunnelbridge_cmd.cpp (TRANSPORT_WATER in CmdBuildBridge, plus the
-- aqueduct cost/ownership checks), src/bridge_map.h (MakeAqueductBridgeRamp),
-- src/table/pricebase.h, src/economy_type.h, src/ship_cmd.cpp. Reuse the
-- bridge plan's ordinary head, middle-obstruction, and length rules.
return function(Bridge)
  local A={BRIDGE_TYPE=0,INFRASTRUCTURE_FACTOR=4,
    base_prices={aqueduct=10000,clear_aqueduct=2000}}
  local policy={spec={id=0,name="Aqueduct",transport="water",water_class="canal"}}
  function policy.available(_,middle_length,opts)
    if middle_length>(opts.max_length or Bridge.default_max_length) then return nil,"BRIDGE_TOO_LONG" end
    return true
  end
  function policy.build_price(opts)
    return (opts.prices or A.base_prices).aqueduct or A.base_prices.aqueduct
  end
  function policy.clear_price(opts)
    return (opts.prices or A.base_prices).clear_aqueduct or A.base_prices.clear_aqueduct
  end

  -- Same board as Bridge.plan. Head tiles may use kind="aqueduct", or
  -- kind="bridge" and transport="water". No canal or water requirement on
  -- the outside neighbours: the stock command can build a dry aqueduct.
  -- Tile clearing, budgets, and active economic price indices are supplied
  -- by the world adapter. opts.deity identifies the stock deity company.
  function A.plan(board,start_id,end_id,opts)
    opts=opts or {}
    if opts.deity then return nil,"INVALID_OWNER" end
    local p,err,tile=Bridge.plan_transport(board,start_id,end_id,A.BRIDGE_TYPE,opts,policy)
    if not p then return nil,err,tile end
    p.transport,p.water_class="water","canal"
    p.water_infrastructure_delta=not p.replacement and opts.company~=false and p.total_length*A.INFRASTRUCTURE_FACTOR or 0
    -- Real MakeAqueductBridgeRamp resets the docking bit, then the two
    -- heads undergo CheckForDockingTile. Let the adapter recompute it
    -- against the current world instead of guessing ownership or a dock.
    p.recheck_docking={p.start,p["end"]}
    return p
  end

  -- The head contract is directly consumable by ship_follow.lua. Middle
  -- tiles keep their original water/land tracks and store overhead only.
  function A.head_record(plan,id)
    local head,other
    if id==plan.start then head,other=plan.head,plan["end"]
    elseif id==plan["end"] then head,other=plan.tail,plan.start
    else return nil end
    return {kind="aqueduct",transport="water",bridge_type=A.BRIDGE_TYPE,water_class="canal",
      owner=plan.owner,other=other,dir=head.inside_direction,skip=plan.middle_length,
      axis=plan.axis,deck=plan.deck,base=head.base,slope=head.foundation_slope,
      max_z=head.base+1,docking=false}
  end

  -- Surface uses levels, not Luanti's node-top offset. Both heads are
  -- already inclined natural terrain, so Lock/canal approach is separate;
  -- the aqueduct itself carries ships at a single raised water level.
  function A.surface(plan,id)
    if id==plan.start or id==plan["end"] or plan.middle_by_tile[id] then return plan.deck end
  end
  function A.clear_cost(plan,opts)
    return plan.total_length*policy.clear_price(opts or {})
  end

  return A
end
