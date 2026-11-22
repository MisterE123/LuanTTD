local base="mods/luanttd_core/openttd/"
local Service=dofile(base.."road_depot_service.lua")
local B=dofile(base.."road_breakdowns.lua")
local F=dofile(base.."yapf_road_follow.lua")
local C=dofile(base.."yapf_road_cost.lua")(F)
local Search=dofile(base.."yapf_road_search.lua")(F,C)
local function forbidden() error("unexpected external stock query") end
local function copy(t) local out={};for k,v in pairs(t) do out[k]=v end;return out end
local h=B.new(45000,80,3650,100,120)
local ctx={company_service_interval=40,interval=20,engine_reliability=50001,economy_date=200,
  difficulty=B.NORMAL,current_order={kind="goto_station",destination=120},cur_speed=40}

h.reliability=40000
ctx.percent=true
assert(not Service.interval_due(h,ctx)) -- floor(50001*80/100) = 40000
h.reliability=39999
assert(Service.interval_due(h,ctx))
ctx.percent=false;ctx.economy_date=120
assert(not Service.interval_due(h,ctx))
ctx.economy_date=121
assert(Service.interval_due(h,ctx))
ctx.wallclock=true;ctx.economy_date=700
assert(not Service.interval_due(h,ctx))
ctx.economy_date=701
assert(Service.interval_due(h,ctx))
ctx.wallclock=false

for _,flag in ipairs({"stopped","crashed"}) do
  ctx[flag]=true
  assert(not Service.needs_servicing(h,ctx,forbidden))
  assert(Service.plan(h,ctx,{nearest=forbidden}).kind=="none")
  ctx[flag]=nil
end
for _,order in ipairs({
  {kind="loading"},
  {kind="goto_depot",depot_type=Service.MANUAL,non_stop=1},
  {kind="goto_depot",depot_type=Service.SERVICE+Service.PART_OF_ORDERS,non_stop=1},
}) do
  local skip=copy(ctx);skip.current_order=order
  assert(Service.plan(h,skip,{nearest=forbidden,random32=forbidden}).kind=="none")
  assert(skip.current_order==order)
end
local skip=copy(ctx)
skip.orders={{kind="goto_station"},{kind="goto_depot"}}
assert(Service.plan(h,skip,{nearest=forbidden}).kind=="none")
skip.orders=nil;skip.company_service_interval=0
assert(Service.needs_servicing(h,skip))
assert(Service.plan(h,skip,{nearest=forbidden}).kind=="none")
skip.company_service_interval=40;skip.front=false
assert(Service.plan(h,skip,{nearest=forbidden}).kind=="none")

-- No ordinary auto-service in OFF/no servicing. Stock's autoreplace
-- exception uses an existing rule, replacement availability/eligibility,
-- and two times full purchase price plus the company reserve.
ctx.difficulty=B.OFF
assert(not Service.needs_servicing(h,ctx))
ctx.no_servicing_if_no_breakdowns=false
assert(Service.needs_servicing(h,ctx,forbidden))
ctx.no_servicing_if_no_breakdowns=true
local r={reserve_money=5000,available_money=15000,replacement_price=5000,engine_available=true,
  replace_when_old=true,renew_months=-1,has_refit_union=true,cargo_valid=true,accepts_current_cargo=true}
local function replacement() return r end
h.age=h.max_age-31
assert(not Service.needs_servicing(h,ctx,replacement))
h.age=h.max_age-30
assert(Service.needs_servicing(h,ctx,replacement))
r.available_money=14999
assert(not Service.needs_servicing(h,ctx,replacement))
r.available_money=15000;r.accepts_current_cargo=false
assert(not Service.needs_servicing(h,ctx,replacement))
r.has_refit_union=false
assert(Service.needs_servicing(h,ctx,replacement))
ctx.difficulty=B.REDUCED

-- Already fully in a real depot takes the service branch without querying,
-- then uses the exact stock state changes from the breakdown module.
ctx.tile_is_road_depot,ctx.depot_state,ctx.cur_speed=true,true,0
ctx.tile,ctx.depot,ctx.dest_tile=44,703,44
assert(Service.plan(h,ctx,{nearest=forbidden}).kind=="service_here")
h.breakdown_chance,h.breakdown_ctr=200,5
B.service(h,ctx.engine_reliability,ctx.economy_date,521,ctx.difficulty)
assert(h.reliability==ctx.engine_reliability and h.breakdown_chance==0 and h.breakdown_ctr==5)
assert(h.date_of_last_service==701 and h.date_of_last_service_newgrf==521)
ctx.economy_date=722
ctx.cur_speed=3 -- mere physical road-depot tile gives stock cost=0 order
local local_route=Service.plan(h,ctx,{nearest=forbidden})
assert(local_route.kind=="route" and local_route.order.destination==703 and not local_route.clear_cached_path)

-- Use the existing actual road YAPF specialization on a connected line.
-- A geometrically nearer owned depot one tile south is not reachable.
local function id(x,z) return 16*z+x end
local tiles={}
local offsets={[0]=-1,16,1,-16}
local board={
  tile=function(i) return tiles[i] end,
  xy=function(i) return i%16,math.floor(i/16) end,
  tile_at=id,adjacent=function(i,d) return i+offsets[d] end,
  center_z=function() return 0 end,
}
local origin,reachable,unreachable=id(2,2),id(7,2),id(2,3)
for x=2,6 do tiles[id(x,2)]={kind="road",road_bits=10,owner="A",roadtype=0} end
tiles[reachable]={kind="depot",dir=F.NE,owner="A",roadtype=0,road_bits=8}
tiles[unreachable]={kind="depot",dir=F.NW,owner="A",roadtype=0,road_bits=1}
local veh={tile=origin,owner="A",bus=true,display_max_speed=112}
local destination=C.destination(board,veh,{kind="any_depot"})
local function nearest(mode,cap)
  assert(mode==Service.YAPF and type(cap)=="number")
  local td=F.direction_trackdir(F.SW)
  local ok,best=Search.find(board,veh,origin,2^td,destination,nil,{max_cost=cap})
  if ok then
    return {tile=best.last_tile,depot=1000+best.last_tile,cost=best.cost,selected_td=best.last_td}
  end
end
local quote=assert(nearest(Service.YAPF,2000))
assert(quote.tile==reachable and quote.cost>100 and quote.tile~=unreachable)
local count=0
local function random_word(r) return function() count=count+1;return r end end
local hooks={nearest=nearest,random32=forbidden}
ctx.tile,ctx.dest_tile,ctx.cur_speed=origin,88,40
ctx.tile_is_road_depot,ctx.depot_state=false,false
ctx.yapf_max_depot_penalty=quote.cost
local plan=Service.plan(h,ctx,hooks)
assert(plan.kind=="route" and plan.route.tile==reachable and plan.route.selected_td==quote.selected_td)
assert(plan.order.destination==1000+reachable and plan.order.depot_type==Service.SERVICE)
assert(plan.order.non_stop==Service.NONSTOP_INTERMEDIATE and plan.order.depot_action==Service.SERVICE_ONLY)
assert(plan.order.no_refit and plan.suppress_implicit_orders and plan.clear_cached_path)
ctx.current_order=plan.order
ctx.dest_tile=plan.dest_tile
hooks.random32=random_word(3277)
assert(Service.plan(h,ctx,hooks).kind=="keep" and count==1)
hooks.random32=random_word(3276)
local redirect=Service.plan(h,ctx,hooks)
assert(redirect.kind=="route" and not redirect.clear_cached_path and count==2)
ctx.yapf_max_depot_penalty=quote.cost-1
hooks.random32=forbidden
local cancel=Service.plan(h,ctx,hooks)
assert(cancel.kind=="cancel" and cancel.order.kind=="dummy" and cancel.preserve_destination)
assert(ctx.current_order==plan.order and ctx.dest_tile==reachable)
ctx.current_order={kind="goto_station"}
assert(Service.plan(h,ctx,hooks).kind=="none")
ctx.yapf_max_depot_penalty=quote.cost
tiles[reachable].owner="B"
assert(Service.plan(h,ctx,hooks).kind=="none","no unreachable or foreign depot shortcut")
print(("PASS: exact stock service eligibility, cancellation/replacement, actual selected YAPF depot cost %d"):format(quote.cost))
