-- SPDX-License-Identifier: GPL-2.0-only
local R=dofile("mods/luanttd_core/openttd/rail_types.lua")
local occupied=0
local tiles={
  [1]={kind="rail",trackbits=3,owner="A",railtype=0},
  [2]={kind="rail",trackbits=12,owner="A",railtype=2},
  [3]={kind="station",owner="A",railtype=2,blocked=true},
  [4]={kind="crossing",owner="A",railtype=0},
  [5]={kind="tunnel",owner="A",railtype=2,length=5,other=10},
  [10]={kind="tunnel",owner="A",railtype=2,length=5,other=5},
  [11]={kind="depot",owner="B",railtype=3},
}
local tests,spans={},0
local board={
  tile=function(id) return tiles[id] end,
  tile_occupied=function(id,mask) tests[id]=mask or true;return id==occupied end,
  span_occupied=function(l,r) spans=spans+1;assert(l==5 and r==10);return occupied==5 end,
  reservations=function(id)
    if id==2 then return {
      {train=71,railtype=2,track=0},
      {train=72,railtype=2,railtypes=12,track=1},
    } end
  end,
}
local company={owner="A",available=15}
local function sum(p)
  local n=0;for _,v in pairs(p.infra) do n=n+v end;return n
end
local standard=assert(R.quote_convert(board,{1},1,company))
assert(not tests[1] and standard.infra[0]==-4 and standard.infra[1]==4 and sum(standard)==0)
local plan=assert(R.quote_convert(board,{2,3,4,10,5,11},3,company))
assert(#plan.charged==4 and #plan.updates==5 and tests[2]==12 and tests[3]==true and tests[4]==true and spans==1)
assert(plan.cost==R.convert_cost(2,3)*10+R.convert_cost(0,3))
assert(plan.infra[2]==-30 and plan.infra[0]==-2 and plan.infra[3]==32 and sum(plan)==0)
assert(#plan.free_reservations==1 and plan.free_reservations[1].train==71)
assert(tiles[2].railtype==2 and tiles[5].railtype==2)
occupied=2
local no,why=R.quote_convert(board,{2},3,company)
assert(not no and why=="RAIL_CONVERSION_OCCUPIED")
occupied=5
local partly=assert(R.quote_convert(board,{4,5,10},3,company))
assert(#partly.updates==1 and partly.errors[1].id==5)
assert(not R.quote_convert(board,{4},3,{owner="A",available=7}))
assert(R.depot_accepts("wagon",2,2) and not R.depot_accepts("wagon",2,3))
assert(R.depot_accepts("engine",3,3) and not R.depot_accepts("engine",3,1))
print("PASS RC1 four stock rail types: occupied rebuild rejection, paired tunnel accounting and mixed powered reservations")
