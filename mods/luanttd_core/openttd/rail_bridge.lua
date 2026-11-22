-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1, tunnelbridge_cmd.cpp CmdBuildBridge, TunnelBridgeClearCost.
-- Uses the existing source port of common bridge geometry/clearance.
-- Rail replacement, reservation preservation and quote are distinct.
return function(Bridge,Quote,Site)
  local R={catalog=Bridge.catalog}
  local floor=math.floor
  local function copy(source)
    local out={}
    for k,v in pairs(source) do out[k]=v end
    return out
  end

  -- board.{tile,xy,id|tile_at} describes raw terrain/base and spans.
  -- board.clear_quote(id,tile,role,owner) may quote indirect landscape
  -- effects; called only on the sites that stock DC_AUTO would clear.
  function R.plan(board,start,finish,style,opts)
    opts=opts or {}
    local a=start~=nil and board.tile(start)
    if not a then return nil,"BRIDGE_THROUGH_MAP_BORDER" end
    local rt=Site.railtype(opts)
    if not rt then return nil,"INVALID_RAILTYPE" end
    if start==finish then return nil,"BRIDGE_SAME_ENDPOINT" end
    local b=finish~=nil and board.tile(finish)
    if not b then return nil,"BRIDGE_THROUGH_MAP_BORDER" end
    local ax,az=board.xy(start)
    local bx,bz=board.xy(finish)
    if ax~=bx and az~=bz then return nil,"BRIDGE_ENDPOINTS_MUST_ALIGN" end
    local axis=ax==bx and Bridge.AXIS_Y or Bridge.AXIS_X
    if bx<ax or bz<az then
      a,b=b,a;ax,bx=bx,ax;az,bz=bz,az;start,finish=finish,start
    end
    local total=bx-ax+bz-az+1
    local available,reason=Bridge.available(style,total-2,opts)
    if not available then return nil,reason end
    local foundation=Site.price(opts,"foundation",250)
    local north=Bridge.head(a.slope,a.base,axis,true,foundation)
    local south=Bridge.head(b.slope,b.base,axis,false,foundation)
    if north.base~=south.base then return nil,"BRIDGEHEADS_NOT_SAME_HEIGHT" end
    local styles=opts.catalog or Bridge.catalog
    local spec=styles[style]
    local replacement=a.kind=="bridge" and b.kind=="bridge" and a.other==finish and a.transport=="rail"
    local plan
    if replacement then
      local town=opts.town_owner or "town"
      if a.railtype~=rt then return nil,"MUST_DEMOLISH_BRIDGE_FIRST" end
      if not opts.query and a.owner==town and not opts.editor and spec.speed<styles[a.bridge_type].speed then
        return nil,"LOCAL_AUTHORITY_REFUSES_TO_ALLOW_THIS"
      end
      if not opts.query and style==a.bridge_type then return nil,"ALREADY_BUILT" end
      if a.owner~=nil and a.owner~=town and a.owner~=opts.owner then
        return nil,"AREA_IS_OWNED_BY_ANOTHER"
      end
      local per_tile=Site.price(opts,"clear_bridge",50)+Quote.rail_clear_price(rt,opts)
      plan={start=start,["end"]=finish,axis=axis,deck=north.base+1,terrain_limit=north.base,
        middle_length=total-2,total_length=total,middle={},middle_by_tile={},head=north,tail=south,
        site_cost=total*per_tile,clears={},owner=a.owner or opts.owner,
        preserve_reservation=not not (a.reserved or (a.reserved_bits or 0)~=0)}
      -- Stock leaves its bridge-middle flags alone on upgrade; tracing
      -- the indices for the planner doesn't re-check clearance/terrain.
      for i=1,total-2 do
        local id=Site.id(board,ax+(axis==Bridge.AXIS_X and i or 0),az+(axis==Bridge.AXIS_Y and i or 0))
        if id==nil then return nil,"BRIDGE_THROUGH_MAP_BORDER" end
        plan.middle[#plan.middle+1]=id;plan.middle_by_tile[id]=true
      end
    else
      -- Dry bridge DC_QUERY_COST shares site validation for road and
      -- rail. A geometry-only query explicitly disables roadtype charges
      -- and upgrades are handled above with the rail-specific rule.
      local function tile(id)
        local t=board.tile(id)
        if not t then return end
        local k=t.kind
        if k=="rail" or k=="signals" or k=="shore_rail" and t.plain~=false then
          local adapted=copy(t);adapted.kind="plain_rail"
          return adapted
        elseif k=="ground" then
          local adapted=copy(t);adapted.kind="clear"
          return adapted
        elseif k=="bridge" and t.transport=="road" then
          -- Two existing ROAD ends must not be treated as our upgrade.
          local adapted=copy(t);adapted.transport="other"
          return adapted
        end
        return t
      end
      local geometry={tile=tile,xy=board.xy,id=board.id or board.tile_at,
        clear_quote=function(id,_,role) return Site.clear(board,id,board.tile(id),role,opts) end}
      local geo_opts={query=true,owner=opts.owner,build_on_slopes=opts.build_on_slopes,
        max_length=opts.max_length,max_height=opts.max_height,prices=opts.prices,catalog=styles}
      local bad
      plan,reason,bad=Bridge.plan_transport(geometry,start,finish,style,geo_opts)
      if not plan then return nil,reason,bad end
      plan.roadtype=nil;plan.road_owner=nil;plan.road_cost=nil
    end
    plan.kind="bridge";plan.transport="rail";plan.railtype=rt
    plan.replacement=replacement;plan.bridge_type=style;plan.spec=spec
    plan.head.id=start;plan.tail.id=finish
    for _,p in ipairs({plan.head,plan.tail}) do
      Site.portal(p,plan,p==plan.head and finish or start,"bridge",p.inside_direction)
      p.deck=plan.deck;p.bridge_type=style;p.bridge_speed=spec and spec.speed
      p.reserved=plan.preserve_reservation or false
      p.reserved_bits=p.reserved and p.trackbits or 0
    end
    plan.rail_cost,plan.structure_cost=0,0
    if not opts.query or opts.company~=false and opts.ai and not opts.local_company then
      if not spec then return nil,"BRIDGE_UNAVAILABLE" end
      local charge_len=opts.company==false and total or Bridge.length_factor(total)
      plan.rail_cost=total*Quote.rail_price(rt,opts)
      plan.structure_cost=floor(charge_len*Site.price(opts,"bridge",275)*spec.multiplier/256)
    end
    plan.price=plan.site_cost+plan.rail_cost+plan.structure_cost
    plan.infrastructure_delta=(opts.company~=false and (not replacement or a.owner==nil)) and total*Site.TRACKBIT_FACTOR or 0
    if not opts.query and opts.budget and plan.price>opts.budget then return nil,"NOT_ENOUGH_CASH" end
    return plan
  end

  function R.surface(plan,id,u,v) return Bridge.surface(plan,id,u,v) end
  function R.pixel(plan,id,x,y)
    if id==plan.start then return Bridge.head_pixel_height(plan.head,x,y) end
    if id==plan["end"] then return Bridge.head_pixel_height(plan.tail,x,y) end
    if plan.middle_by_tile[id] then return plan.deck*8 end
  end

  return R
end
