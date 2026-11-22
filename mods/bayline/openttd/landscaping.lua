-- SPDX-License-Identifier: GPL-2.0-only
-- Command logic from OpenTTD 14.1 src/terraform_cmd.cpp, src/tilearea.cpp,
-- src/company_cmd.cpp and src/table/pricebase.h (OpenTTD contributors).
-- Terrain owns geometry and tile validation. The live caller supplies
-- map policy, current expense prices, company balance, and clearance.
return function(Terrain)
  local L={base_terraform_cost=250, limit_unit=65536,
           default_quota_rate=64*65536, default_quota_burst=4096}
  local floor,min,max,abs=math.floor,math.min,math.max,math.abs
  local function dir(n) return n<0 and -1 or 1 end
  local function trunc(n) return n<0 and -floor(-n) or floor(n) end
  local function key(g,x,z) return (z-1)*(g.width+1)+x end
  local function pos(g,k)
    return (k-1)%(g.width+1)+1,floor((k-1)/(g.width+1))+1
  end

  -- Inputs are the stock saved fixed-point quota and actual frame count.
  -- Pass zero frames to initialize/cap a restored value, or nil allowance
  -- to start from the company's initial maximum burst.
  function L.replenish(allowance,ticks,rate,burst)
    burst=burst or L.default_quota_burst
    return min((allowance or burst*L.limit_unit)+(rate or L.default_quota_rate)*ticks,
               burst*L.limit_unit)
  end

  -- PRICE state is supplied by a future finance adapter. The fallback
  -- values are the stock base prices from pricebase.h, not inflated costs.
  local clear_prices={grass=20,rough=40,rocks=200,fields=500,snow=40,desert=40}
  function L.clear_ground_cost(kind,density,prices)
    if kind=="grass" and density==0 then return 0 end
    local key=(kind=="snow" or kind=="desert") and "rough" or kind
    return (prices and prices[key]) or clear_prices[key]
  end

  -- OpenTTD's OrthogonalTileIterator and DiagonalTileIterator operate over
  -- north corners. World dimensions include their far corner/void edge.
  -- The diagonal iterator starts at the first argument, not the minimum.
  function L.points(g,ax,az,bx,bz,diagonal)
    if not Terrain.corner(g,ax,az) or not Terrain.corner(g,bx,bz) then return end
    if not diagonal then
      local lowx,highx=min(ax,bx),max(ax,bx)
      local lowz,highz=min(az,bz),max(az,bz)
      local x,z=lowx-1,lowz
      return function()
        x=x+1
        if x>highx then x=lowx;z=z+1 end
        if z<=highz then return x,z end
      end
    end
    local da,db=bz+bx-az-ax,bz-bx-az+ax
    local amax,bmax=da+(da>0 and 1 or -1),db+(db>0 and 1 or -1)
    local a,b,first=0,0,true
    return function()
      if first then first=false;return ax,az end
      while b~=bmax do
        if abs(amax)==1 then
          a=0
          b=bmax>0 and min(b+2,bmax) or max(b-2,bmax)
        else
          a=a+dir(amax)*2
          if (amax>0 and a>=amax) or (amax<0 and a<=amax) then
            a=abs(a)%2==1 and 0 or dir(amax)
            b=b+dir(bmax)
          end
        end
        if b==bmax then break end
        local x,z=ax+trunc((a-b)/2),az+trunc((b+a)/2)
        if Terrain.corner(g,x,z) then return x,z end
      end
    end
  end

  local function options(g,opts,allowance)
    local out={}
    for k,v in pairs(opts) do out[k]=v end
    out.unit_cost=opts.unit_cost or L.base_terraform_cost
    out.max_height=min(opts.max_height or g.max_height,g.max_height)
    if allowance~=nil then out.terraform_limit=floor(allowance/L.limit_unit) end
    return out
  end
  local function corner_step(g,x,z,up,opts)
    -- Represent a north-corner command on the synthetic far edge as the
    -- touching East/West/South segment of the adjacent logical game tile.
    local tx,tz=min(x,g.width),min(z,g.depth)
    local mask=x==tx and (z==tz and 8 or 4) or (z==tz and 1 or 2)
    return Terrain.plan(g,tx,tz,mask,up,opts)
  end
  function L.corner(g,x,z,up,opts)
    opts=opts or {}
    if type(up)~="boolean" or not Terrain.corner(g,x,z) then return nil,"INVALID_SELECTION" end
    local step,why,ex,ez=corner_step(g,x,z,up,options(g,opts,opts.allowance))
    if not step then return nil,why,ex,ez end
    if opts.cash and opts.cash<step.cost then return nil,"NOT_ENOUGH_MONEY",x,z,step.cost end
    step.spent_allowance=#step.changes*L.limit_unit
    step.allowance_after=opts.allowance and opts.allowance-step.spent_allowance
    step.cash_after=opts.cash and opts.cash-step.cost
    step.steps={#step.changes}
    step.target_height=Terrain.corner(g,x,z)+(up and 1 or -1)
    return step
  end

  -- L.level previews the executable command with real height, clearance,
  -- money, and quota changes after each step. stock_test=true exposes
  -- vanilla's intentionally inaccurate non-mutating estimate for parity;
  -- it must never be applied. For exact clearing costs, a host may supply
  -- after_step(step,scratch) to stage objects into a per-invocation scratch
  -- board matching validate_tile's view without altering the live world.
  -- An executed command stops at the first unaffordable step or quota
  -- exhaustion, but other blocked corners do not cancel successful work.
  function L.level(g,sx,sz,ex,ez,mode,diagonal,opts)
    opts=opts or {}
    local delta=mode=="level" and 0 or mode=="raise" and 1 or mode=="lower" and -1
    local start=Terrain.corner(g,sx,sz)
    local iter=L.points(g,ex,ez,sx,sz,diagonal)
    if not delta or start==nil or not iter then return nil,"INVALID_SELECTION" end
    local target=start+delta
    local allowance,cash=opts.allowance,opts.cash
    local probe=options(g,opts,allowance)
    if target<0 then return nil,"ALREADY_AT_SEA_LEVEL" end
    if target>probe.max_height then return nil,start==0 and "ALREADY_AT_SEA_LEVEL" or "TOO_HIGH" end
    local limit=probe.terraform_limit or math.huge
    if limit==0 then return nil,"TERRAFORM_LIMIT_REACHED" end
    local scratch={}
    for k,v in pairs(g) do scratch[k]=v end
    scratch.levels=setmetatable({},{__index=g.levels})
    local result={revision=g.revision,width=g.width,depth=g.depth,changes={},dirty={},levels={},steps={},skipped={},
                  cost=0,target_height=target,spent_allowance=0,stock_test=opts.stock_test}
    local dirty,success,halt={},false,false
    local last_error=mode=="level" and "ALREADY_LEVELLED" or "INVALID_SELECTION"
    local err_x,err_z
    for x,z in iter do
      local cur=Terrain.corner(scratch,x,z)
      while cur~=target do
        local step,why,dx,dz=corner_step(scratch,x,z,cur<=target,probe)
        if not step then
          last_error,err_x,err_z=why,dx,dz
          result.skipped[#result.skipped+1]={x=x,z=z,reason=why,blocked_x=dx,blocked_z=dz}
          if why=="TERRAFORM_LIMIT_REACHED" then limit=0 end
          break
        end
        -- Stock probes record the north corner for a successful step,
        -- including that of the next unaffordable step.
        err_x,err_z=x,z
        if opts.stock_test then
          limit=limit-1
          if limit<=0 then success=true;break end
        else
          if cash and cash<step.cost then
            result.required_money=step.cost
            result.shortfall=step.cost-cash
            result.halted="NOT_ENOUGH_MONEY"
            result.error_x,result.error_z=x,z
            halt=true
            break
          end
          assert(Terrain.apply(scratch,step))
          result.steps[#result.steps+1]=#step.changes
          local consumed=#step.changes*L.limit_unit
          result.spent_allowance=result.spent_allowance+consumed
          if allowance then
            allowance=allowance-consumed
            probe.terraform_limit=floor(allowance/L.limit_unit)
          end
          if cash then cash=cash-step.cost end
          for _,d in ipairs(step.dirty) do dirty[key(g,d.x,d.z)]=true end
          if opts.after_step then opts.after_step(step,scratch) end
        end
        result.cost=result.cost+step.cost
        cur=cur+dir(target-cur)
        success=true
      end
      if halt or limit<=0 then break end
    end
    if not success and not halt then return nil,last_error,err_x,err_z end
    if limit<=0 and not result.halted then result.halted="TERRAFORM_LIMIT_REACHED" end
    result.allowance_after=allowance
    result.cash_after=cash
    if not halt then result.error_x,result.error_z=ex,ez end
    local indices={}
    for k in pairs(scratch.levels) do indices[#indices+1]=k end
    table.sort(indices)
    for _,k in ipairs(indices) do
      local x,z=pos(g,k)
      result.changes[#result.changes+1]={x=x,z=z,height=scratch.levels[k]}
      result.levels[k]=scratch.levels[k]
    end
    indices={}
    for k in pairs(dirty) do indices[#indices+1]=k end
    table.sort(indices)
    for _,k in ipairs(indices) do
      local x,z=pos(g,k)
      result.dirty[#result.dirty+1]={x=x,z=z}
    end
    return result
  end

  function L.apply(g,plan)
    if plan.stock_test then return nil,"STOCK_ESTIMATE_HAS_NO_PLAN" end
    if plan.revision~=g.revision or plan.width~=g.width or plan.depth~=g.depth then
      return nil,"STALE_TERRAIN_PLAN"
    end
    if #plan.changes==0 then return true end
    return Terrain.apply(g,plan)
  end

  return L
end
