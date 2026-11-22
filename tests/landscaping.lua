local T=dofile("mods/luanttd_core/openttd/terrain.lua")
local L=dofile("mods/luanttd_core/openttd/landscaping.lua")(T)
local function pts(iterator)
  local out={}
  for x,z in iterator do out[#out+1]=x..":"..z end
  return table.concat(out,",")
end

local g=T.new(8,8,function() return 1 end)
assert(pts(L.points(g,3,4,2,3,false))=="2:3,3:3,2:4,3:4")
assert(pts(L.points(g,4,2,2,4,true))=="4:2,3:3,2:4")
assert(pts(L.points(g,2,2,4,4,true))=="2:2,3:3,4:4")
assert(pts(L.points(g,3,3,3,3,true))=="3:3")
assert(L.clear_ground_cost("grass",0)==0)
assert(L.clear_ground_cost("grass",3)==20)
assert(L.clear_ground_cost("snow",1,{rough=82})==82)
assert(L.clear_ground_cost("fields",1)==500)
assert(not L.clear_ground_cost("water",0))
assert(L.replenish(nil,0)==4096*65536)
assert(L.replenish(0,3,123,100)==369)
assert(L.replenish(65536,1000,123,2)==2*65536)
assert(L.replenish(65536,1000,0,2)==65536)

-- Cost counts recursive corner work; state stays untouched until applied.
local p=assert(L.corner(g,9,9,true,{cash=500,allowance=65537}))
assert(p.target_height==2 and p.cost==250 and p.cash_after==250 and p.allowance_after==1)
assert(#p.changes==1 and #p.dirty==1 and T.corner(g,9,9)==1)
assert(L.apply(g,p) and T.corner(g,9,9)==2)
local denied,err=L.apply(g,p)
assert(not denied and err=="STALE_TERRAIN_PLAN")
denied,err=L.corner(g,9,9,true,{allowance=65537})
assert(not denied and err=="TERRAFORM_LIMIT_REACHED")
local _,why,ex,ez,need=L.corner(g,4,4,true,{cash=249})
assert(why=="NOT_ENOUGH_MONEY" and ex==4 and ez==4 and need==250)

-- Unit-cost budget runs out partway through; the valid prefix still applies.
g=T.new(8,8,function() return 1 end)
p=assert(L.level(g,2,2,4,2,"raise",false,{cash=590}))
assert(p.target_height==2 and p.cost==500 and p.cash_after==90 and p.required_money==250 and p.shortfall==160)
assert(p.error_x==4 and p.error_z==2 and #p.changes==2 and T.corner(g,2,2)==1)
assert(L.apply(g,p))
assert(T.corner(g,2,2)==2 and T.corner(g,3,2)==2 and T.corner(g,4,2)==1)
p=assert(L.level(g,2,2,4,2,"level",false,{cash=0}))
assert(#p.changes==0 and p.required_money==250)
local rev=g.revision
assert(L.apply(g,p) and g.revision==rev)

-- Non-budget tile failures do not cancel other valid corners.
g=T.new(8,8,function() return 1 end)
p=assert(L.level(g,2,2,7,2,"raise",false,{validate_tile=function(_,x,z)
  if x==4 and z==2 then return nil,"PROTECTED_TILE" end
  return 0
end}))
assert(p.cost==1000 and #p.changes==4 and #p.skipped==2)
assert(p.skipped[1].x==4 and p.skipped[2].x==5 and p.skipped[2].blocked_x==4)
assert(L.apply(g,p))
assert(T.corner(g,2,2)==2 and T.corner(g,3,2)==2 and T.corner(g,4,2)==1
   and T.corner(g,5,2)==1 and T.corner(g,6,2)==2 and T.corner(g,7,2)==2)

-- Preview switch reproduces the stock dry-run limit oddity, never writes.
g=T.new(8,8,function() return 1 end)
p=assert(L.level(g,2,2,4,2,"raise",false,{stock_test=true,allowance=65536}))
assert(p.cost==0 and #p.changes==0)
denied,err=L.apply(g,p)
assert(not denied and err=="STOCK_ESTIMATE_HAS_NO_PLAN")
p=assert(L.level(g,2,2,4,2,"raise",false,{allowance=2*65536+42}))
assert(p.cost==500 and #p.changes==2 and p.allowance_after==42)
assert(p.halted=="TERRAFORM_LIMIT_REACHED")

-- A level picks the north corner of the drag start even when a different
-- tile sorts first in the iterator, and it can raise and lower in one drag.
g=T.new(8,8,function(x) return math.min(3,x-1) end)
p=assert(L.level(g,3,4,1,4,"level",false))
assert(p.target_height==2)
assert(L.apply(g,p))
for x=1,3 do assert(T.corner(g,x,4)==2) end

print("PASS: stock corner geometry, both drag modes, paid partial edits, blocked corners, quota/replenishment, stale previews and target choice")
