-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1: landscape.cpp CmdClearArea/CmdLandscapeClear,
-- tilearea.{cpp,_type.h}, company_cmd.cpp, table/settings/world_settings.ini.
local C={UNIT=65536,RATE=64*65536,BURST=4096}
local floor,min,max,abs=math.floor,math.min,math.max,math.abs

local function trunc2(n) return n<0 and -floor(-n/2) or floor(n/2) end
local function sign(n) return n>0 and 1 or -1 end
local function uint(n,hi) return type(n)=="number" and n>=0 and n<=hi and n==floor(n) end

function C.replenish(quota,frames,rate,burst)
  burst=(burst or C.BURST)*C.UNIT
  if frames==0 then return quota or burst end
  return min((quota or burst)+(rate or C.RATE)*frames,burst)
end

-- One-based host tile IDs, x fastest. Order is a property of the command:
-- pass the second (release) tile first to the actual stock iterator.
function C.each(width,depth,first,last,diagonal)
  local n=width*depth
  if not uint(first,n) or first==0 or not uint(last,n) or last==0 then return end
  local function xy(i) return (i-1)%width,floor((i-1)/width) end
  local function tile(x,y) return y*width+x+1 end
  local x,y=xy(last)
  local u,v=xy(first)
  if not diagonal then
    local lo,hi,top,bottom=min(x,u),max(x,u),min(y,v),max(y,v)
    x,y=lo-1,top
    return function()
      x=x+1
      if x>hi then x,y=lo,y+1 end
      if y<=bottom then return tile(x,y) end
    end
  end
  local da,db=u+v-x-y,v-u-y+x
  local am,bm=da+sign(da),db+sign(db)
  local a,b,start=0,0,true
  return function()
    if start then start=false;return last end
    while b~=bm do
      if abs(am)==1 then
        a=0
        b=bm>0 and min(b+2,bm) or max(b-2,bm)
      else
        a=a+2*sign(am)
        if (am>0 and a>=am) or (am<0 and a<=am) then
          a=abs(a)%2==1 and 0 or sign(am)
          b=b+sign(bm)
        end
      end
      if b==bm then return end
      local i,j=x+trunc2(a-b),y+trunc2(b+a)
      if i>=0 and j>=0 and i<width and j<depth then return tile(i,j) end
    end
  end
end

-- The caller's clear-tile authority quotes cost or returns nil, error.
-- execute=false returns the literal command test price (not payable cost);
-- execute=true runs the actual order/budget/counter, calling apply only
-- after affordability and clear-limit are verified. With no apply it is
-- a read-only projection for independent tile operations.
-- opts.limit is the saved fixed-point counter or nil for no company limit.
function C.run(width,depth,first,last,diagonal,ctx,opts)
  opts=opts or {}
  local iter=C.each(width,depth,first,last,diagonal)
  if not iter then return nil,"INVALID_PARAMETER" end
  local quota=opts.limit
  local limit=quota and floor(quota/C.UNIT) or 2147483647
  local money=opts.money or math.huge
  local force=first~=last
  local result={cost=0,extra=0,passed=0,attempted=0,skipped=0,quota=quota,money=money}
  local had_success,last_error=false,"INVALID_PARAMETER"
  for tile in iter do
    result.attempted=result.attempted+1
    local cost,reason
    if quota and quota<C.UNIT then
      reason="CLEARING_LIMIT_REACHED"
    else
      cost,reason=ctx.quote(tile,force)
    end
    if cost==nil then
      last_error=reason or "INVALID_PARAMETER"
      if quota and quota<C.UNIT then result.limit_reached=true;break end
      result.skipped=result.skipped+1
    else
      had_success=true
      if opts.execute then
        money=money-cost
        if cost>0 and money<0 then
          result.extra,result.next_tile=cost,tile
          break
        end
        if ctx.apply then ctx.apply(tile,force,cost) end
        if quota then quota=quota-C.UNIT end
        result.passed=result.passed+1
      elseif cost~=0 then
        -- OpenTTD's initial command test stops *before* adding the quote of
        -- the last nonzero tile permitted by its local test counter.
        limit=limit-1
        if limit<=0 then result.limit_reached=true;break end
      end
      result.cost=result.cost+cost
      if ctx.accepted then ctx.accepted(tile,cost) end
    end
  end
  if not had_success then return nil,last_error,result end
  result.quota=quota
  if opts.execute then result.money=(opts.money or math.huge)-result.cost end
  return result
end

return C
