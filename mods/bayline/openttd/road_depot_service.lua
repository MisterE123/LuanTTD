-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright OpenTTD contributors. Source: OpenTTD 14.1 vehicle.cpp,
-- ground_vehicle.cpp, roadveh_cmd.cpp and order_cmd.cpp.
-- Detached ordinary single-unit road vehicle; a caller owns road routing,
-- orders, depot entry and the real breakdown/service state mutations.
local S={
  NPF="npf",YAPF="yapf",DAYS_IN_ECONOMY_MONTH=30,DEFAULT_DEPOT_PENALTY=2000,
  UINT_MAX=2^32-1,MANUAL=0,SERVICE=1,PART_OF_ORDERS=2,
  STOP_EVERYWHERE=0,NONSTOP_INTERMEDIATE=1,SERVICE_ONLY=0,
}
local floor,ceil=math.floor,math.ceil
local function trunc(n) return n<0 and ceil(n) or floor(n) end

-- The due threshold is strict in all modes. The source compares against
-- the design's current age-specific reliability, not a fixed 65535.
function S.interval_due(health,ctx)
  if ctx.percent then
    return health.reliability<trunc(ctx.engine_reliability*(100-ctx.interval)/100)
  end
  local d=ctx.wallclock and ctx.interval*S.DAYS_IN_ECONOMY_MONTH or ctx.interval
  return health.date_of_last_service+d<ctx.economy_date
end

-- Optional source exception when 'off/no servicing' normally suppresses
-- detours. Authored ordinary stock single-unit road vehicles cannot have
-- the mixed cargo masks an articulated/NewGRF vehicle can carry.
-- lookup() returns the authoritative company/group engine replacement
-- rule and cash/price/refit facts, not a desired replacement command.
local function pending_replacement(health,lookup)
  local r=lookup and lookup()
  if not r or r.reserve_money>r.available_money or not r.engine_available then return false end
  if r.replace_when_old and health.age-health.max_age<r.renew_months*30 then return false end
  if r.has_refit_union and r.cargo_valid and not r.accepts_current_cargo then return false end
  return r.reserve_money+2*r.replacement_price<=r.available_money
end

function S.needs_servicing(health,ctx,lookup)
  if ctx.stopped or ctx.crashed or not S.interval_due(health,ctx) then return false end
  local difficulty=ctx.difficulty==nil and 1 or ctx.difficulty
  if ctx.no_servicing_if_no_breakdowns==false or difficulty~=0 then return true end
  return pending_replacement(health,lookup)
end

function S.has_depot_order(orders)
  for _,order in ipairs(orders or {}) do
    if order.kind=="goto_depot" then return true end
  end
  return false
end

function S.needs_automatic_servicing(health,ctx,lookup)
  local order=ctx.current_order
  if ctx.has_depot_order or S.has_depot_order(ctx.orders) then return false end
  if order and (order.kind=="loading" or order.kind=="goto_depot" and order.depot_type~=S.SERVICE) then return false end
  return S.needs_servicing(health,ctx,lookup)
end

function S.in_depot(ctx)
  -- GroundVehicle::IsChainInDepot for one physical vehicle: just seeing a
  -- depot tile (or being stopped while there) is not sufficient.
  return not not (ctx.tile_is_road_depot and ctx.cur_speed==0 and ctx.depot_state)
end

local function chance20(random32)
  local r=random32()
  assert(type(r)=="number" and r%1==0 and r>=0 and r<=S.UINT_MAX,"expected one stock uint32 Random() draw")
  return floor(((r%65536)*20+10)/65536)<1
end

-- One economy-day decision, after the road breakdown check.
-- ctx.company_service_interval is the separate servint_roadveh enable switch.
-- hooks.nearest(mode,max_penalty) receives the actual vehicle's state through
-- the caller's binding and returns {tile,depot,cost,...} or nil if unreachable.
-- No changes occur until the host physically services or applies the result.
function S.plan(health,ctx,hooks)
  hooks=hooks or {}
  if ctx.front==false or (ctx.company_service_interval or 0)==0 or
      not S.needs_automatic_servicing(health,ctx,hooks.replacement) then
    return {kind="none"}
  end
  if S.in_depot(ctx) then return {kind="service_here"} end
  local mode=ctx.pathfinder or S.YAPF
  local max_penalty
  if mode==S.NPF then max_penalty=ctx.npf_max_depot_penalty
  elseif mode==S.YAPF then max_penalty=ctx.yapf_max_depot_penalty
  else error("unsupported stock road pathfinder selection") end
  max_penalty=max_penalty or S.DEFAULT_DEPOT_PENALTY
  local result
  if ctx.tile_is_road_depot then
    -- FindClosestRoadDepot's own cost-zero shortcut if already at a real
    -- road depot tile, even when this is not yet the complete depot state.
    assert(ctx.tile~=nil and ctx.depot~=nil,"stock depot tile and depot ID required")
    result={tile=ctx.tile,depot=ctx.depot,cost=0}
  else
    result=hooks.nearest(mode,max_penalty)
  end
  local order=ctx.current_order
  local detour=order and order.kind=="goto_depot" -- only a SERVICE order survived the gate
  if not result or result.cost==S.UINT_MAX or result.cost>max_penalty then
    -- Stock MakeDummy only clears type/flags. Preserve the destination,
    -- route cursor and path cache for the regular order loop to resolve.
    if detour then return {kind="cancel",order={kind="dummy"},preserve_destination=true} end
    return {kind="none"}
  end
  if detour and (order.non_stop or 0)%2==S.NONSTOP_INTERMEDIATE and not chance20(hooks.random32) then
    return {kind="keep"}
  end
  return {
    kind="route",route=result,dest_tile=result.tile,clear_cached_path=result.tile~=ctx.dest_tile,
    suppress_implicit_orders=true,
    order={kind="goto_depot",destination=result.depot,depot_type=S.SERVICE,non_stop=S.NONSTOP_INTERMEDIATE,
      depot_action=S.SERVICE_ONLY,no_refit=true},
  }
end

return S
