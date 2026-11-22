-- SPDX-License-Identifier: GPL-2.0-only
local R=dofile("mods/luanttd_core/openttd/rail_types.lua")
assert(R.tile_type(0xC1)==1 and R.set_tile_type(0xC1,0)==0xC0)
assert(R.tile_type(0xFF)==63 and not R.entry(63))
assert(R.convert_cost(0,1)==68 and R.convert_cost(1,0)==12)
assert(R.is_compatible(1,0) and not R.has_power(1,0) and R.has_power(0,1))
assert(R.depot_accepts("wagon",0,1) and not R.depot_accepts("engine",1,0))
assert(R.depot_accepts("engine",1,1))
local r,changed=R.add_piece_type(0,1)
assert(r==1 and changed)
r,changed=R.add_piece_type(1,0)
assert(r==1 and not changed)
r,changed=R.add_piece_type(1,1)
assert(r==1 and not changed)
local x,why=R.add_piece_type(0,2)
assert(not x and why=="IMPOSSIBLE_TRACK_COMBINATION")
local function d(r,hp,legacy) return {intended_railtype=r,hp=hp,legacy_normal=legacy} end
local electric=d(1,3600);local carriage=d(0,0)
local p=assert(R.consist({electric,carriage},false))
assert(p.route_mask==2 and not p.compatible[0] and p.compatible[1])
assert(R.unit_power(p.units[1],0)==0 and R.unit_power(p.units[1],1)==3600)
local mixed=assert(R.consist({electric,d(0,300),carriage},false))
assert(mixed.route_mask==3 and R.unit_power(mixed.units[2],0)==300)
assert(R.flag_existing(p.units[1],true))
electric.legacy_normal=true
p=assert(R.consist({electric,carriage},false))
assert(p.route_mask==3 and p.units[1].railtype==0 and R.unit_power(p.units[1],0)==3600)

local e=assert(R.electric_engine(23))
assert(e.image_index==20 and R.electric_engine(24).image_index==20)
assert(e.speed==160 and e.tare==84 and e.running_base==4800 and e.running_factor==180)
e.intro_date=20000;e.company_avail=1 -- accepted preview for company 0 only
local engines={e,{intended_railtype=0,kind="engine",climates=1,intro_date=0}}
assert(R.company_types(engines,0,0,20002,false)==3)
assert(R.company_types(engines,1,0,20364,false)==1)
assert(R.company_types(engines,1,0,20365,false)==3)
assert(R.company_types(engines,0,0,20400,true)==1)
assert(R.company_types(engines,0,1,20400,false)==0)

local map={
 [1]={kind="rail",railtype=0,owner="A",trackbits=3}, -- two billed, four infrastructure
 [2]={kind="station",railtype=0,owner="A",blocked=true}, -- one billed, zero infrastructure
 [3]={kind="waypoint",railtype=0,owner="A",blocked=true}, -- one billed, still one infrastructure
 [4]={kind="crossing",railtype=0,owner="A"},
 [5]={kind="depot",railtype=0,owner="B"},
 [6]={kind="bridge",railtype=0,owner="A",other=10,length=3},
 [10]={kind="bridge",railtype=0,owner="A",other=6,length=3},
 [15]={kind="signals",railtype=1,owner="A",trackbits=2},
}
local board={size=16,tile=function(id)return map[id]end,
  reservations=function(id) if id==15 then return {{train=91,railtype=1,track=1}} end end}
local opts={owner="A",available=3,cash=680}
local plan=assert(R.quote_convert(board,{1,2,3,4,5,6,8,10},1,opts))
assert(plan.cost==680 and #plan.updates==6 and #plan.charged==5 and plan.infra[0]==-27 and plan.infra[1]==27)
assert(plan.errors[1].error=="OWNED_BY_ANOTHER" and map[1].railtype==0 and map[10].railtype==0)
opts.cash=679
local impossible,err,price=R.quote_convert(board,{1,2,3,4,5,6,8,10},1,opts)
assert(not impossible and err=="NOT_ENOUGH_MONEY" and price==680 and map[1].railtype==0)
plan=assert(R.quote_convert(board,{15},0,{owner="A",available=3}))
assert(plan.cost==12 and #plan.free_reservations==1 and plan.free_reservations[1].train==91)
plan,err=R.quote_convert(board,{15},0,{owner="A",available=1,disable_elrails=true})
assert(not plan and err=="NO_SUITABLE_RAILROAD_TRACK" and map[15].railtype==1)
plan,err=R.quote_convert(board,{5,8},1,opts)
assert(not plan and err=="OWNED_BY_ANOTHER")
assert(R.catenary_drawn(1,false,false) and not R.catenary_drawn(1,true,false)
  and not R.catenary_drawn(1,false,true))
print("PASS named ordinary electric rail gates, sticky traction, prices, reservation plan and atomic quote")
