-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, source pin 14.1. water_cmd.cpp CmdBuildCanal,
-- CmdBuildLock / DoBuildLock; water_map.h MakeLock and water classifiers;
-- tilearea.cpp orthogonal/diagonal selection; table/pricebase.h.
-- Plans never mutate. The host commits the ordered plan after validation
-- (with optional topology token) and owns clearing external structures.
return function(Track,Water)
  local M={CANAL_COST=5000,LOCK_COST=7500,CLEAR_CANAL=5000,CLEAR_WATER=10000,
    CLEAR_ROUGH=40,LOCK_DEPOT_TILE_FACTOR=2}
  local up={[12]=0,[6]=1,[3]=2,[9]=3}
  local classes={canal=true,river=true,sea=true}
  local corner={[1]=true,[2]=true,[4]=true,[8]=true}
  local water_objects={lock=true,ship_depot=true,dock=true,buoy=true,oilrig=true,station=true,
    industry=true,object=true}
  local min,max=math.min,math.max
  local function tile(board,id) return id~=nil and board.tile(id) or nil end
  local function price(opts,k,fallback) return opts.prices and opts.prices[k] or fallback end
  local function plain(t)
    if not t then return false end
    if t.is_water_tile~=nil then return t.is_water_tile end
    return t.kind=="water" or classes[t.kind]==true
  end
  local function class(t) return t and (t.water_class or Water.water_class(t)) end
  local function water_ground(t)
    if not t then return false end
    if t.water_ground~=nil then return t.water_ground end
    return not t.is_coast and (plain(t) or water_objects[t.kind]) and classes[class(t)]==true
  end
  local function none(owner) return owner==nil or owner=="none" end
  local function company(owner,opts)
    if opts.is_company then return opts.is_company(owner) end
    return not none(owner) and owner~="town" and owner~="water" and owner~="deity"
  end
  local function get_height(t) return t.base or t.height or 0 end
  local function get_top(t)
    local s=t.slope or 0
    return t.top or get_height(t)+(s==0 and 0 or s>=16 and 2 or 1)
  end
  M.uphill_direction=function(s) return up[s] end

  -- ClearTile_Water's ordinary water/shore branches. Complex existing
  -- structures, bay wet tiles and station ownership are adapter territory;
  -- don't silently destroy them as part of a purchase.
  local function default_clear(board,id,t,opts)
    if plain(t) or t.rocks and not t.is_coast then
      if opts.no_water then return nil,"CAN_T_BUILD_ON_WATER" end
      if opts.freeform_edges==false and board.water_clear_allowed and not board.water_clear_allowed(id) then
        return nil,"TOO_CLOSE_TO_EDGE_OF_MAP"
      end
      if t.occupied then return nil,"VEHICLE_IN_THE_WAY" end
      if not none(t.owner) and t.owner~="water" and t.owner~=opts.owner then
        return nil,"OWNED_BY_ANOTHER"
      end
      return class(t)=="canal" and price(opts,"clear_canal",M.CLEAR_CANAL) or price(opts,"clear_water",M.CLEAR_WATER)
    end
    if t.occupied then return nil,"VEHICLE_IN_THE_WAY" end
    if t.clear_cost~=nil then return t.clear_cost end
    if t.kind=="clear" then return 0 end
    if t.kind=="coast" then
      return corner[t.slope] and price(opts,"clear_water",M.CLEAR_WATER) or price(opts,"clear_rough",M.CLEAR_ROUGH)
    end
    return nil,"LANDSCAPE_CLEAR_REQUIRED"
  end
  local function new_plan(board,kind)
    return {kind=kind,cost=0,operations={},tiles={},records={},dirty={},docking={},invalidate={},
      infrastructure={},topology=board.version and board.version() or nil}
  end
  local function clear(board,p,id,t,opts,suppress_cost,phase)
    -- Return cost, error, optional predicted post-clear record. Pure adapter
    -- is normal for complex map layers; the default handles simple ground.
    local cost,why,after
    if opts.clear then cost,why,after=opts.clear(id,t,opts,phase)
    else cost,why=default_clear(board,id,t,opts) end
    if cost==nil then return nil,why or "LANDSCAPE_CLEAR_REQUIRED" end
    p.operations[#p.operations+1]={op="clear",tile=id,cost=cost,charged=not suppress_cost,
      previous=t,replacement=after,phase=phase}
    if not suppress_cost then p.cost=p.cost+cost end
    return true,nil,after
  end
  local function infrastructure(p,owner,delta,why,opts)
    if company(owner,opts) then
      p.infrastructure[#p.infrastructure+1]={owner=owner,delta=delta,reason=why}
    end
  end
  local function put(p,id,record)
    p.operations[#p.operations+1]={op="build",tile=id,record=record}
    p.tiles[#p.tiles+1]=id
    p.records[id]=record
    p.dirty[#p.dirty+1]=id
  end
  local function finish(p,opts)
    if opts.budget~=nil and p.cost>opts.budget then return nil,"NOT_ENOUGH_MONEY" end
    return p
  end

  -- OpenTTD TileIterator::Create receives drag end as its first corner.
  -- Non-diagonal drags are row-major rectangles. Diagonal drags preserve
  -- the original rotated/parity iteration and clip only outside the map.
  function M.area(board,start_id,end_id,diagonal)
    if not tile(board,start_id) or not tile(board,end_id) then return nil end
    local x,z=board.xy(end_id)
    local u,v=board.xy(start_id)
    local out={}
    if not diagonal then
      for j=min(z,v),max(z,v) do for i=min(x,u),max(x,u) do
        out[#out+1]=board.tile_at(i,j)
      end end
      return out
    end
    local a_max=u+v-x-z
    local b_max=v-u-z+x
    a_max=a_max+(a_max>0 and 1 or -1)
    b_max=b_max+(b_max>0 and 1 or -1)
    local a,b=0,0
    local forward=a_max>0 and 1 or -1
    local cross=b_max>0 and 1 or -1
    local trunc=function(n) return n<0 and math.ceil(n/2) or math.floor(n/2) end
    while b~=b_max do
      local id=board.tile_at(x+trunc(a-b),z+trunc(a+b))
      if id~=nil then out[#out+1]=id end
      if a_max==1 or a_max==-1 then
        a=0
        b=b_max>0 and min(b+2,b_max) or max(b-2,b_max)
      else
        a=a+2*forward
        if (a_max>0 and a>=a_max) or (a_max<0 and a<=a_max) then
          a=math.abs(a)%2~=0 and 0 or forward
          b=b+cross
        end
      end
    end
    return out
  end

  function M.canal(board,start_id,end_id,water_class,opts)
    opts=opts or {}
    if not classes[water_class] or (water_class~="canal" and not opts.editor) then return nil,"INVALID_PARAMETER" end
    local selection=M.area(board,start_id,end_id,opts.diagonal)
    if not selection then return nil,"INVALID_PARAMETER" end
    local p=new_plan(board,"canal")
    p.requested_class,p.skipped=water_class,{}
    for _,id in ipairs(selection) do
      local t=tile(board,id)
      if not t then return nil,"INVALID_PARAMETER",id end
      local slope=t.slope or 0
      if slope~=0 and (water_class~="river" or up[slope]==nil) then return nil,"FLAT_LAND_REQUIRED",id end
      local was_plain=plain(t)
      local was_canal=was_plain and class(t)=="canal"
      if was_canal and not opts.editor and (t.owner==opts.owner or none(t.owner)) then
        p.skipped[#p.skipped+1]=id
      else
        local ok,why,after=clear(board,p,id,t,opts,was_plain,"canal")
        if not ok then return nil,why,id end
        if was_canal then infrastructure(p,t.owner,-1,"clear_existing_canal",opts) end
        local h=after and get_height(after) or get_height(t)
        local wc=water_class=="sea" and h>0 and "canal" or water_class
        local owner=wc~="canal" and "water" or opts.owner
        put(p,id,{kind=wc,water_class=wc,owner=owner,slope=slope,base=h,top=get_top(after or t),
          remove_nearby_desert=wc=="river" and opts.editor or nil})
        if wc=="canal" then infrastructure(p,owner,1,"build_canal",opts) end
        p.cost=p.cost+price(opts,"canal",M.CANAL_COST)
        p.invalidate[#p.invalidate+1]=id
        p.docking[#p.docking+1]=id
      end
    end
    if p.cost==0 then return nil,"ALREADY_BUILT" end
    return finish(p,opts)
  end

  -- BuildLock uses the exact downhill, middle and uphill tiles, in stock
  -- orientation. Fresh flat ends acquire canal class; existing plain ends
  -- retain their class even when the builder does not own them.
  function M.lock(board,id,opts)
    opts=opts or {}
    local middle=tile(board,id)
    local dir=middle and up[middle.slope]
    if dir==nil then return nil,"LAND_SLOPED_IN_WRONG_DIRECTION",id end
    local lower_id=board.adjacent(id,Track.reverse_side(dir))
    local upper_id=board.adjacent(id,dir)
    local lower,upper=tile(board,lower_id),tile(board,upper_id)
    if not lower or not upper then return nil,"INVALID_PARAMETER",lower and upper_id or lower_id end
    for _,v in ipairs({{id,middle},{upper_id,upper},{lower_id,lower}}) do
      local ok,why=true,nil
      if opts.ensure_empty then ok,why=opts.ensure_empty(v[1],v[2]) end
      if not ok or v[2].occupied then return nil,why or "VEHICLE_IN_THE_WAY",v[1] end
    end
    local p=new_plan(board,"lock")
    p.middle,p.lower,p.upper,p.dir=id,lower_id,upper_id,dir
    local wc=water_ground(middle) and class(middle) or "canal"
    local success,why=clear(board,p,id,middle,opts,false,"middle")
    if not success then return nil,why,id end
    if plain(middle) and class(middle)=="canal" then
      infrastructure(p,middle.owner,-1,"clear_existing_canal",opts)
    end
    local function bank(tid,t,part)
      local wet=plain(t)
      local current=t
      if not wet then
        local ok,msg,after=clear(board,p,tid,t,opts,false,part)
        if not ok then return nil,msg end
        p.cost=p.cost+price(opts,"canal",M.CANAL_COST)
        current=after or t
        if not plain(current) then infrastructure(p,opts.owner,1,"build_lock_end_water",opts) end
      end
      if (current.slope or 0)~=0 then return nil,"LAND_SLOPED_IN_WRONG_DIRECTION" end
      local bank_class=plain(current) and class(current) or "canal"
      local owner=opts.owner
      if plain(current) then owner=current.owner end
      return {kind="lock",part=part,dir=dir,lock_middle=id,owner=owner,
        water_class=bank_class,slope=0,base=get_height(current),top=get_height(current)}
    end
    local a,err=bank(lower_id,lower,"lower")
    if not a then return nil,err,lower_id end
    local b,msg=bank(upper_id,upper,"upper")
    if not b then return nil,msg,upper_id end
    for _,v in ipairs({{id,middle},{lower_id,lower},{upper_id,upper}}) do
      if v[2].overhead then return nil,"MUST_DEMOLISH_BRIDGE_FIRST",v[1] end
    end
    p.cost=p.cost+price(opts,"lock",M.LOCK_COST)
    infrastructure(p,opts.owner,3*M.LOCK_DEPOT_TILE_FACTOR,"build_lock",opts)
    put(p,id,{kind="lock",part="middle",dir=dir,lock_middle=id,owner=opts.owner,
      water_class=wc,slope=middle.slope,base=get_height(middle),top=get_top(middle),lower=lower_id,upper=upper_id})
    put(p,lower_id,a)
    put(p,upper_id,b)
    p.docking={lower_id,upper_id}
    p.invalidate={id,lower_id,upper_id}
    return finish(p,opts)
  end

  -- Execution is deliberately explicit. The host owns atomic validation,
  -- tile writes, accounting, redraw and region invalidation, and receives
  -- the complete ordered plan once (never a partial series of callbacks).
  function M.apply(board,p)
    if type(p)~="table" or not board.commit then return nil,"COMMIT_REQUIRED" end
    if p.topology~=nil and (not board.version or board.version()~=p.topology) then
      return nil,"STALE_PLAN"
    end
    return board.commit(p)
  end
  return M
end
