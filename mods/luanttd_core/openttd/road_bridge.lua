-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors. No warranty.
-- Port from pinned OpenTTD 14.1: src/tunnelbridge_cmd.cpp
-- (GetBridgeFoundation, CheckBridgeSlope, HasBridgeFlatRamp,
-- CalcBridgeLenCostFactor, CheckBridgeAvailability and the road branches
-- of CmdBuildBridge/GetSlopePixelZ_TunnelBridge), src/table/bridge_land.h,
-- src/table/pricebase.h, src/table/world_settings.ini; default road and
-- tram costing/flags from src/road.h and src/table/roadtypes.h.
-- This is a plan, not an engine mutation or a road tile approximation.
return function(Slope)
  local B={AXIS_X=0,AXIS_Y=1,NE=0,SE=1,SW=2,NW=3}
  local floor,min=math.floor,math.min
  local highest={[1]=true,[2]=true,[4]=true,[8]=true,[23]=true,[27]=true,[29]=true,[30]=true}
  local built_in={
    [0]={"Wooden",0,0,65535,80,32},
    {"Concrete",0,0,2,112,48},
    {"Steel girder",1930,0,5,144,64},
    {"Concrete suspension",0,2,10,168,80},
    {"Steel suspension",1930,3,65535,185,96},
    {"Steel suspension (yellow)",1930,3,65535,192,112},
    {"Steel cantilever",1930,3,7,224,160},
    {"Steel cantilever (brown)",1930,3,8,232,208},
    {"Steel cantilever (red)",1930,3,9,248,240},
    {"Steel girder (fast)",1930,0,2,240,256},
    {"Tubular steel",1995,2,65535,255,320},
    {"Tubular steel (yellow)",2005,2,65535,380,512},
    {"Silicon tubular",2010,2,65535,510,608},
  }
  B.catalog={}
  for id=0,12 do
    local row=built_in[id]
    B.catalog[id]={id=id,name=row[1],year=row[2],min_length=row[3],max_length=row[4],multiplier=row[5],speed=row[6]}
  end
  B.road_flags={catenary=1,no_level_crossing=2,no_houses=4,hidden=8,town_build=16}
  B.roadtypes={
    [0]={id=0,type="road",label="ROAD",flags=16,cost_multiplier=8,
         maintenance_multiplier=16,max_speed=0,powered={[0]=true},
         introduced_by_vehicle=false,sorting_order=0x07},
    [1]={id=1,type="tram",label="ELRL",flags=5,cost_multiplier=16,
         maintenance_multiplier=24,max_speed=0,powered={[1]=true},
         introduced_by_vehicle=true,sorting_order=0x17},
  }
  B.default_max_length=64 -- interior tiles; the two ramps are not counted
  B.default_max_height=12
  B.base_prices={road=95,clear_road=40,bridge=275,clear_bridge=50,foundation=250}

  function B.length_factor(length)
    if length<2 then return length end
    local left,sum,d=length-2,2,1
    while left>0 do
      local used=min(left,d)
      sum=sum+used*d
      left=left-used;d=d+1
    end
    return sum
  end
  function B.available(id,middle_length,opts)
    opts=opts or {}
    local max_length=opts.max_length or B.default_max_length
    if opts.query then
      if middle_length<=max_length then return true end
      return nil,"BRIDGE_TOO_LONG"
    end
    local spec=(opts.catalog or B.catalog)[id]
    if not spec or spec.year>(opts.year or 1950) or middle_length<spec.min_length then
      return nil,"BRIDGE_UNAVAILABLE"
    end
    if middle_length>min(spec.max_length,max_length) then return nil,"BRIDGE_TOO_LONG" end
    return true
  end
  function B.foundation(tile_slope,axis)
    if tile_slope==0 or
      (axis==B.AXIS_X and (tile_slope==12 or tile_slope==3)) or
      (axis==B.AXIS_Y and (tile_slope==9 or tile_slope==6)) then
      return "none"
    end
    if highest[tile_slope] then return axis==B.AXIS_X and "x" or "y" end
    return "leveled"
  end
  local ramp_slope={[0]=12,6,3,9}
  local function oriented(valid,base,mask,foundation,dir,fee)
    local is_flat=mask~=0
    return {valid=valid,base=base,foundation_slope=mask,foundation=foundation,
      flat_ramp=is_flat,inside_direction=dir,road_slope=is_flat and 0 or ramp_slope[dir],
      road_base=base+(is_flat and 1 or 0),foundation_cost=fee}
  end
  function B.head(tile_slope,base,axis,is_north,price)
    local f=B.foundation(tile_slope,axis)
    local mask,rise=Slope.foundation(tile_slope,f)
    local valid_slope,dir
    if is_north then
      valid_slope=axis==B.AXIS_X and 12 or 9
      dir=axis==B.AXIS_X and B.SW or B.SE
    else
      valid_slope=axis==B.AXIS_X and 3 or 6
      dir=axis==B.AXIS_X and B.NE or B.NW
    end
    local valid=mask==0 or mask==valid_slope
    return oriented(valid,base+rise,mask,f,dir,valid and f~="none" and (price or B.base_prices.foundation) or 0)
  end
  -- Continuous Luanti-world adapter, measured in OpenTTD height LEVELS.
  -- It deliberately drops the stock integer isometric pixel quantization.
  -- Add Bayline's world top-of-node .5 externally when placing meshes.
  function B.surface(plan,id,u,v)
    local h=plan.head.id==id and plan.head or plan.tail.id==id and plan.tail or nil
    if h then return h.road_base+Slope.surface(u,v,h.road_slope) end
    if plan.middle_by_tile[id] then return plan.deck end
  end
  -- Exact upstream pixel-height samples for vehicles at bridgeheads.
  function B.head_pixel_height(head,x,y)
    return 8*head.road_base+Slope.pixel(x%16,y%16,head.road_slope)
  end

  local function compatible_middle(tile,z,axis)
    local k=tile.kind
    if k=="clear" or not k then return true end
    if k=="water" or k=="sea" or k=="river" or k=="canal" or k=="coast" or
      k=="plain_rail" or (k=="shore_rail" and tile.plain~=false) or k=="tunnel" then return true end
    if k=="road" or k=="crossing" then return true end
    if k=="bridge" or k=="aqueduct" then return tile.axis~=axis and tile.deck<=z end
    if k=="object" then return tile.allow_under_bridge and tile.max_z+(tile.object_height or 0)<=z end
    -- Houses, depot/paved station tiles, lock and other facilities use
    -- the stock landscape-clear path rather than being silently buried.
    return false
  end
  local function custom_price(by_type,id)
    if type(by_type)=="function" then return by_type(id) end
    if by_type then return by_type[id] end
  end
  function B.road_build_cost(id,opts)
    opts=opts or {}
    local override=custom_price(opts.road_build_price,id)
    if override~=nil then return override end
    local p=opts.prices or B.base_prices
    local r=(opts.roadtypes or B.roadtypes)[id] or B.roadtypes[id]
    return floor((p.road or B.base_prices.road)*(r and r.cost_multiplier or 8)/8)
  end
  function B.road_clear_cost(id,opts)
    opts=opts or {}
    local override=custom_price(opts.road_clear_price,id)
    if override~=nil then return override end
    local p=(opts.prices or B.base_prices).clear_road or B.base_prices.clear_road
    local r=(opts.roadtypes or B.roadtypes)[id] or B.roadtypes[id]
    if not r or r.type=="road" then return p end
    -- C++ integer division truncates toward zero; the usual stock build
    -- price is positive but NewGRF or price test fixtures can vary.
    local refund=B.road_build_cost(id,opts)*3/4
    return p-(refund>=0 and floor(refund) or math.ceil(refund))
  end

  -- Pure command adapter:
  -- board.xy(id) -> x,z, board.id(x,z) -> tile id (or nil at edge),
  -- board.tile(id) -> {base,slope,max_z,kind,...} or nil at map border.
  --   kind is clear, water, coast, plain_rail, road, crossing, tunnel,
  --   bridge, object, or another obstruction (handled by clear_quote).
  --   overhead = {axis,deck}; a bridgehead has other,axis,deck,bridge_type,
  --   transport="road",owner (nil unowned, opts.town_owner for municipal),
  --   roadtype/tramtype and separate road_owner/tram_owner for replacements.
  -- board.clear_quote(id,tile,role,owner) -> cost or nil,error. No mutation.
  -- opts.year, owner, town_owner, budget, build_on_slopes, max_length,
  -- max_height, catalog, roadtypes, roadtype, prices and per-type costs.
  -- query=true offers a geometry-only cost without style availability,
  -- as DC_QUERY_COST in stock. Set company=false for len-factor bypass
  -- (town/deity/editor). Defaults quote normal human company construction.
  -- Shared CmdBuildBridge planner. The water policy is supplied by
  -- aqueduct.lua so this entry point does not pretend an aqueduct is wood.
  function B.plan_transport(board,start_id,end_id,bridge_type,opts,aqueduct)
    local water=aqueduct~=nil
    opts=opts or {}
    local ta,tb=board.tile(start_id),board.tile(end_id)
    if not ta or not tb then return nil,"BRIDGE_THROUGH_MAP_BORDER" end
    local x,z=board.xy(start_id)
    local ex,ez=board.xy(end_id)
    local roadtype=opts.roadtype or 0
    local rt=(opts.roadtypes or B.roadtypes)[roadtype]
    if not water and (not rt or (rt.type~="road" and rt.type~="tram") or
      (opts.can_build_roadtype and not opts.can_build_roadtype(roadtype))) then
      return nil,"INVALID_ROADTYPE"
    end
    if start_id==end_id then return nil,"BRIDGE_SAME_ENDPOINT" end
    if x~=ex and z~=ez then return nil,"BRIDGE_ENDPOINTS_MUST_ALIGN" end
    local axis=x==ex and B.AXIS_Y or B.AXIS_X
    if ex<x or ez<z then
      start_id,end_id=end_id,start_id;ta,tb=tb,ta
      x,ex=ex,x;z,ez=ez,z
    end
    local distance=(ex-x)+(ez-z)
    local available=water and aqueduct.available or B.available
    local ok,err=available(bridge_type,distance-1,opts)
    if not ok then return nil,err end
    local prices=opts.prices or B.base_prices
    local base_h=B.head(ta.slope,ta.base,axis,true,prices.foundation)
    local base_t=B.head(tb.slope,tb.base,axis,false,prices.foundation)
    -- Stock checks the slope resulting from ApplyFoundationToSlope here,
    -- before checking equal portal heights or the result's validity.
    if water and (base_h.foundation_slope==0 or base_t.foundation_slope==0) then
      return nil,"LAND_SLOPED_IN_WRONG_DIRECTION"
    end
    if base_h.base~=base_t.base then return nil,"BRIDGEHEADS_NOT_SAME_HEIGHT" end
    local h=base_h.base
    local max_height=opts.max_height or B.default_max_height
    local town_owner=opts.town_owner or "town"
    local plan={start=start_id,["end"]=end_id,axis=axis,middle_length=distance-1,
      total_length=distance+1,deck=h+1,terrain_limit=h,spec=water and aqueduct.spec or (opts.catalog or B.catalog)[bridge_type],
      bridge_type=bridge_type,head=base_h,tail=base_t,middle={},middle_by_tile={},clears={},
      site_cost=0,road_cost=0,structure_cost=0}
    plan.head.id=start_id;plan.tail.id=end_id

    local function clear(id,t,role)
      local cost,why
      if board.clear_quote then cost,why=board.clear_quote(id,t,role,opts.owner)
      elseif not t.kind or t.kind=="clear" then cost=0
      else return nil,"BRIDGE_LAND_CLEAR_REQUIRED",id end
      if cost==nil then return nil,why or "BRIDGE_LAND_CLEAR_REQUIRED",id end
      plan.site_cost=plan.site_cost+cost
      plan.clears[#plan.clears+1]=id
      return true
    end

    local replacement
    if water then
      local function aquatic(rec)
        return rec.kind=="aqueduct" or rec.kind=="bridge" and rec.transport=="water"
      end
      replacement=aquatic(ta) and aquatic(tb) and ta.other==end_id
    else
      replacement=ta.kind=="bridge" and tb.kind=="bridge" and ta.other==end_id and ta.transport=="road"
    end
    plan.replacement=replacement
    local road,tram,road_owner,tram_owner
    if replacement then
      local per_tile
      if water then
        -- A normal aqueduct command always requests the canonical map
        -- bridge ID 0. The stock duplicate check precedes ownership.
        if not opts.query then return nil,"ALREADY_BUILT" end
        per_tile=aqueduct.clear_price(opts)
      else
        road,tram=ta.roadtype,ta.tramtype
        road_owner,tram_owner=ta.road_owner,ta.tram_owner
        local existing=rt.type=="road" and road or (rt.type=="tram" and tram or nil)
        if existing~=nil and existing~=roadtype then return nil,"MUST_DEMOLISH_BRIDGE_FIRST" end
        if not opts.query then
          local catalog=opts.catalog or B.catalog
          if ta.owner==town_owner and not opts.editor and plan.spec.speed<catalog[ta.bridge_type].speed then
            return nil,"LOCAL_AUTHORITY_REFUSES_TO_ALLOW_THIS"
          end
          if ta.bridge_type==bridge_type and (road==roadtype or tram==roadtype) then return nil,"ALREADY_BUILT" end
        end
        per_tile=prices.clear_bridge or B.base_prices.clear_bridge
        if road~=nil then per_tile=per_tile+2*B.road_clear_cost(road,opts) end
        if tram~=nil then per_tile=per_tile+2*B.road_clear_cost(tram,opts) end
      end
      if ta.owner~=nil and ta.owner~=opts.owner and ta.owner~=town_owner then
        return nil,"AREA_IS_OWNED_BY_ANOTHER"
      end
      plan.site_cost=plan.total_length*per_tile
      plan.owner=ta.owner or opts.owner
      if ta.owner==nil then
        road_owner=road_owner or opts.owner;tram_owner=tram_owner or opts.owner
      end
    else
      local allow=not water and opts.build_on_slopes~=false
      for _,item in ipairs({{base_h,ta},{base_t,tb}}) do
        local head,record=item[1],item[2]
        local cleared,reason,id=clear(head.id,record,"head")
        if not cleared then return nil,reason,id end
        if not head.valid or (head.foundation_cost~=0 and not allow) then
          return nil,"LAND_SLOPED_IN_WRONG_DIRECTION",head.id
        end
        plan.site_cost=plan.site_cost+head.foundation_cost
      end
      for _,head in ipairs({ta,tb}) do
        if head.overhead and (head.overhead.axis==axis or head.overhead.deck==plan.deck) then
          return nil,"MUST_DEMOLISH_BRIDGE_FIRST"
        end
      end
      plan.owner=opts.owner
    end

    for i=1,distance-1 do
      local id=board.id(x+(axis==B.AXIS_X and i or 0),z+(axis==B.AXIS_Y and i or 0))
      local t=id and board.tile(id)
      if not t then return nil,"BRIDGE_THROUGH_MAP_BORDER" end
      if not replacement then
        if t.max_z>h then return nil,"BRIDGE_TOO_LOW_FOR_TERRAIN",id end
        if h>=t.base+max_height then return nil,"BRIDGE_TOO_HIGH_FOR_TERRAIN",id end
        if t.overhead then return nil,"MUST_DEMOLISH_BRIDGE_FIRST",id end
        if not compatible_middle(t,h,axis) then
          local cleared,reason=clear(id,t,"middle")
          if not cleared then return nil,reason,id end
        end
      end
      plan.middle[#plan.middle+1]=id;plan.middle_by_tile[id]=true
    end
    if not water then
      if rt.type=="road" and road==nil then road,road_owner=roadtype,opts.owner end
      if rt.type=="tram" and tram==nil then tram,tram_owner=roadtype,opts.owner end
      plan.roadtype,plan.tramtype=road,tram
      plan.road_owner,plan.tram_owner=road_owner,tram_owner
    end
    plan.price=plan.site_cost
    if not opts.query or (opts.company~=false and opts.ai and not opts.local_company) then
      if not plan.spec then return nil,"BRIDGE_UNAVAILABLE" end
      local len=opts.company==false and plan.total_length or B.length_factor(plan.total_length)
      if water then
        plan.structure_cost=len*aqueduct.build_price(opts)
      else
        local piece=0
        if road~=nil then piece=piece+B.road_build_cost(road,opts) end
        if tram~=nil then piece=piece+B.road_build_cost(tram,opts) end
        plan.road_cost=2*plan.total_length*piece
        plan.structure_cost=floor(len*(prices.bridge or B.base_prices.bridge)*plan.spec.multiplier/256)
      end
      plan.price=plan.price+plan.road_cost+plan.structure_cost
    end
    if not opts.query and opts.budget and plan.price>opts.budget then return nil,"NOT_ENOUGH_CASH" end
    return plan
  end

  function B.plan(board,start_id,end_id,bridge_type,opts)
    return B.plan_transport(board,start_id,end_id,bridge_type,opts)
  end

  function B.quotes(board,start_id,end_id,opts)
    local result={}
    local catalog=opts and opts.catalog or B.catalog
    for id=0,12 do
      if catalog[id] then
        local plan=B.plan(board,start_id,end_id,id,opts)
        if plan then result[#result+1]=plan end
      end
    end
    return result
  end
  return B
end
