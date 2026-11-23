local Rating=dofile("mods/luanttd_core/openttd/station_rating.lua")
local function good(r,a) return {active=a,state={rating=r}} end
local a,b,c,d,e,f,g=good(250,true),good(100,true),good(160,false),good(200,true),
  good(175,true),good(10,true),good(250,true)
local stations={
  {owner="mine",x=15,y=15,goods={a,b,c}}, -- exactly radius 30
  {owner="mine",x=16,y=15,goods={d}},
  {owner="another",x=0,y=0,goods={e}},
  {owner="mine",x=0,y=0,goods={f,g}},
}
assert(Rating.modify_around(stations,"mine",0,0,-160,30)==4)
assert(a.state.rating==90 and b.state.rating==0 and c.state.rating==160)
assert(d.state.rating==200 and e.state.rating==175 and f.state.rating==0 and g.state.rating==90)
assert(Rating.modify_around(stations,"mine",0,0,255,30)==4)
assert(a.state.rating==255 and f.state.rating==255)
print("PASS RC1 accident rating: station sign Manhattan distance 30, owner, active goods entries, byte clamp")
