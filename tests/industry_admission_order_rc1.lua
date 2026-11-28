-- Keep the stock quote's cheap-to-expensive order and execute nothing.
local p="mods/luanttd_core/openttd/"
local A=dofile(p.."industry_admission_rc1.lua")
local S=dofile(p.."industry_spec_rc1.lua")
local L=dofile(p.."stock_industry_layouts_rc1.lua")
local t={valid=true,house=true,zone=1,slope=0}
local seen,industry={},{}
local platform,pool=true,true
local board={
  town=function()seen[#seen+1]="town";return {id=1,x=15,z=16,population=470} end,
  tile=function()seen[#seen+1]="tile";return t end,
  clear=function(_,_,_,who,auto,check,modify)
    seen[#seen+1]="clear"
    assert(who=="town" and not auto and not check and not modify)
    return true
  end,
  platform=function(_,_,_,_,needs)
    seen[#seen+1]="platform"
    assert(needs==(t.slope~=0))
    return platform and {level=0}
  end,
  can_allocate=function()seen[#seen+1]="pool";return pool end,
}
local function quote(opts)
  seen={}
  local q,why=A.quote(assert(S.get(22,"tropic")),L[22][0],L.slope_refused,16,16,board,opts,industry)
  return q,why,table.concat(seen,",")
end
industry[1]={type=21,x=30,z=30,town=1}
local q,why,trace=quote({landscape="tropic"})
assert(not q and why=="INDUSTRY_TOO_CLOSE" and trace=="")
industry[1]={type=22,x=32,z=40,town=1}
q,why,trace=quote({landscape="tropic"})
assert(not q and why=="ONLY_ONE_ALLOWED_PER_TOWN" and trace=="town")
industry={}
t.house,t.zone=false,0
q,why,trace=quote({landscape="tropic"})
assert(not q and why=="CAN_ONLY_BE_BUILT_IN_TOWNS" and trace=="town,tile")
t.house=true
q,why,trace=quote({landscape="tropic"})
assert(not q and why=="CAN_ONLY_BE_BUILT_IN_DESERT" and trace=="town,tile,clear,tile")
t.zone,t.slope=1,1
q,why,trace=quote({landscape="tropic"})
assert(not q and why=="SITE_UNSUITABLE" and trace=="town,tile,clear,tile")
platform=false
local world={landscape="tropic",terragenesis=true,generating_world=true}
q,why,trace=quote(world)
assert(not q and why=="SITE_UNSUITABLE" and trace=="town,tile,clear,tile,platform")
platform,pool=true,false
q,why,trace=quote(world)
assert(not q and why=="TOO_MANY_INDUSTRIES" and trace=="town,tile,clear,tile,platform,pool")
pool=true
q,why,trace=quote(world)
assert(q and q.town==1 and q.needs_grading and q.platform and #q.cells==1 and trace=="town,tile,clear,tile,platform,pool")
print("PASS stock site-quote phase ordering through towns, ground clear, terrain grading and pool admission")
