-- Adapter contracts not covered by the upstream geometry harness.
local T=dofile('mods/luanttd_core/openttd/terrain.lua')
local options={max_height=9,unit_cost=50}
local g=T.new(9,8,function() return 2 end,options)
local p=assert(T.plan(g,5,5,8,true))
assert(#p.changes==1 and #p.dirty==4 and p.cost==50)
assert(T.corner(g,5,5)==2 and T.corner(g,5,5,p)==3)
assert(T.tile(g,5,5,p)==8 and T.tile(g,4,5,p)==1)
assert(T.height(g,5,5,0,0,p)==3 and T.height(g,4,5,1,0,p)==3)
for i=0,16 do
  local t=i/16
  assert(T.height(g,5,5,0,t,p)==T.height(g,4,5,1,t,p))
  assert(T.height(g,5,5,t,0,p)==T.height(g,5,4,t,1,p))
end
assert(T.apply(g,p))
local ok,err=T.apply(g,p)
assert(not ok and err=='STALE_TERRAIN_PLAN')
p=assert(T.plan(g,5,5,8,true))
assert(#p.changes==5 and #p.dirty==12 and p.cost==250)
assert(T.tile(g,5,5,p)==29)
assert(T.corner(g,5,5)==3 and T.corner(g,5,5,p)==4)
assert(T.corner(g,4,5,p)==3 and T.corner(g,5,4,p)==3)
p,err=T.plan(g,5,5,8,true,{terraform_limit=4})
assert(not p and err=='TERRAFORM_LIMIT_REACHED')
local x,z
p,err,x,z=T.plan(g,5,5,8,true,{bridge_height=function(tx,tz)
  if tx==5 and tz==5 then return 4 end
end})
assert(not p and err=='MUST_DEMOLISH_BRIDGE_FIRST' and x==5 and z==5)
p,err,x,z=T.plan(g,5,5,8,false,{bridge_height=function(tx,tz)
  if tx==5 and tz==5 then return 5 end
end,max_bridge_height=2})
assert(not p and err=='BRIDGE_TOO_HIGH_AFTER_LOWER_LAND' and x==5 and z==5)
p,err,x,z=T.plan(g,5,5,8,false,{tunnel_in_way=function(tx,tz,lo)
  return tx==5 and tz==5 and lo==2
end})
assert(not p and err=='EXCAVATION_WOULD_DAMAGE_TUNNEL' and x==5 and z==5)
p,err,x,z=T.plan(g,5,5,8,false,{validate_tile=function(pass,tx,tz)
  if pass==0 and tx==4 and tz==4 then return nil,'OCCUPIED' end
  return 0
end})
assert(not p and err=='OCCUPIED' and x==4 and z==4)
local calls={}
p=assert(T.plan(g,5,5,8,false,{validate_tile=function(pass,tx,tz,mask,lo,hi,plan)
  calls[#calls+1]=('%d,%d,%d'):format(pass,tx,tz)
  assert(mask==0 and lo==2 and hi==2 and T.corner(g,5,5,plan)==2)
  return 20
end}))
assert(p.cost==130)
assert(table.concat(calls,' ')=='0,4,4 0,5,4 0,4,5 0,5,5 1,4,4 1,5,4 1,4,5 1,5,5')
local edge=T.new(8,8,nil,{freeform_edges=false})
p,err,x,z=T.plan(edge,2,4,8,true)
assert(not p and err=='TOO_CLOSE_TO_EDGE' and x==1 and z==4)
p,err=T.plan(edge,4,4,8,false)
assert(not p and err=='ALREADY_AT_SEA_LEVEL')
assert(T.corner(g,5,5)==3 and g.revision==1)
print('PASS: terrain preview, continuous edges, dirty hooks, bridge/tunnel protection and stale-plan rejection')
