local mod="mods/luanttd_core/openttd/"
local A=dofile(mod.."town_council_campaigns_rc1.lua")
local G=dofile(mod.."town_growth.lua")
local t=G.new(9,7,11,{custom_growth=true,growth_rate=80})
local paid=2000000
local flags={}
local bonus_count,fail_count=0,0
local function bonus(owner,x,z,amount,radius)
  assert(owner=="First" and x==7 and z==11 and amount==130 and radius==17)
  bonus_count=bonus_count+1
end
local function failed(owner,id)
  assert(owner=="Second" and id==9)
  fail_count=fail_count+1
end
local right=assert(A.quote("exclusive_rights",t,"First",500,paid,flags))
assert(right.cost==457031)
assert(not A.quote("exclusive_rights",t,"First",500,paid,{exclusive_rights=false}))
assert(not A.quote("exclusive_rights",t,"First",500,right.cost-1,flags))
assert(A.execute(right,t,"First",500,function()error("Rights don't consume RNG") end,bonus,failed)==500)
assert(t.exclusive_counter==12 and t.exclusivity=="First" and bonus_count==1)
assert(not A.quote("exclusive_rights",t,"Second",500,paid,flags))
-- An outstanding rival can still bribe to remove existing exclusivity.
assert(A.quote("bribe",t,"Second",800,paid,flags))
assert(not A.quote("bribe",t,"First",800,paid,flags))
local bribe=assert(A.quote("bribe",t,"Second",500,paid,flags))
assert(bribe.cost==683593)
local score,ok=A.execute(bribe,t,"Second",700,function()return 4681 end,bonus,failed)
assert(ok and score==800 and t.exclusivity==nil and t.exclusive_counter==0)
assert(not A.quote("bribe",t,"Second",800,paid,flags))
assert(A.execute(right,t,"First",500,function()error("Rights don't consume RNG") end,bonus,failed)==500)
score,ok=A.execute(bribe,t,"Second",-60,function()return 4680 end,bonus,failed)
assert(not ok and score==-60 and t.unwanted.Second==6 and fail_count==1 and bonus_count==2)
assert(not A.quote("bribe",t,"Second",-60,paid,flags))
for _=1,6 do G.month(t,{},2) end
assert(t.unwanted.Second==nil and t.exclusive_counter==6 and t.exclusivity=="First")
for _=1,6 do G.month(t,{},2) end
assert(t.exclusive_counter==0 and t.exclusivity==nil)
print("PASS stock council availability, payment factors, Chance16 edge, signed penalties and month expiry")
