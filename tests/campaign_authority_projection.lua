local P=dofile("mods/luanttd_core/campaign_authority_projection.lua")()
local function receipt(seq,tick,rows)
  return {ok=true,seq=seq,tick=tick,value={actors=rows}}
end
local a,b=P.subscribe("11:11"),P.subscribe("11:12")
local function train(parts) return {key="rail:1",parts=parts} end
local bus={key="road:1",tile=120}
local head={index=1,tile=121}
local tail={index=2,tile=122}
assert(P.accept("11:11",a,receipt(5,74,{train({head}),bus})))
assert(P.accept("11:12",b,receipt(4,74,{train({tail})})))
local both=P.actors()
assert(#both["rail:1"].parts==2 and both["road:1"].tile==120)
assert(not P.accept("11:11",a,receipt(3,74,{})))
assert(P.accept("11:11",a,receipt(7,148,{train({head})})))
local newer=P.actors()
assert(#newer["rail:1"].parts==1 and not newer["road:1"])
P.unsubscribe("11:12");local reentered=P.subscribe("11:12")
assert(reentered~=b)
assert(not P.accept("11:12",b,receipt(8,148,{train({tail})})))
assert(P.accept("11:12",reentered,receipt(9,148,{train({tail})})))
assert(#P.actors()["rail:1"].parts==2)
P.unsubscribe("11:11");P.unsubscribe("11:12")
assert(not next(P.actors()))
print("PASS projected consist joins adjacent sectors at one tick; out-of-order and unsubscribed receipts cannot revive actors")
local l,r=P.subscribe("left"),P.subscribe("right")
local subscriptions={{key="left",token=l},{key="right",token=r}}
assert(P.accept_batch(subscriptions,{ok=true,seq=10,tick=222,value={
  {actors={train({head})}},{actors={train({tail})}},
}}))
assert(#P.actors()["rail:1"].parts==2)
P.unsubscribe("right")
assert(not P.accept_batch(subscriptions,{ok=true,seq=11,tick=296,value={
  {actors={bus}},{actors={}},
}}))
assert(not P.actors()["road:1"])
print("PASS one committed tick for a visible sector batch; stale batch cannot revive an unsubscribed actor")
local region=P.subscribe("corners")
assert(P.accept("corners",region,{ok=true,seq=12,tick=370,value={
  x=6,z=8,width=1,height=1,tiles={{id=12}},corners=string.char(4,4,5,5),
}}))
local data,nw=P.terrain(6,8)
assert(data.id==12 and nw==4 and select(2,P.terrain(7,9))==5)
P.unsubscribe("corners")
assert(not P.terrain(6,8))
print("PASS bounded terrain cache reads the inclusive shared corners and forgets them on leaving")
P.unsubscribe("left")
local token=P.subscribe("delta")
local batch={{key="delta",token=token}}
local full={scene=31,x=8,z=8,width=1,height=1,tiles={{id=42}},corners=string.char(3,3,3,3),actors={bus}}
assert(P.accept_batch(batch,{ok=true,seq=20,tick=740,value={full}}))
local delta={scene=31,x=8,z=8,width=1,height=1,actors={}}
assert(P.accept_batch(batch,{ok=true,seq=21,tick=814,value={delta}}))
assert(P.scene("delta")==31 and not next(P.actors()) and P.terrain(8,8).id==42)
P.unsubscribe("delta");batch[1].token=P.subscribe("delta")
assert(not P.accept_batch(batch,{ok=true,seq=22,tick=888,value={delta}}) and not P.terrain(8,8))
print("PASS actor-only deltas require an existing matching scene but never revive stale actors")
local bay=P.subscribe("waiting")
local area={{key="waiting",token=bay}}
local full={scene=33,x=8,z=8,width=1,height=1,tiles={{id=42}},corners=string.char(3,3,3,3),
  passengers={["road:7"]=113},boarding_cursor=9,boardings={{seq=9,mode="road",id=7,units=8}}}
assert(P.accept_batch(area,{ok=true,seq=30,tick=888,value={full}}))
assert(P.waiting("road",7)==113 and P.boarding_cursor("waiting")==9)
assert(#P.take_boardings()==1 and #P.take_boardings()==0)
local again={scene=33,x=8,z=8,width=1,height=1,passengers={["road:7"]=109},
  boarding_cursor=10,boardings={{seq=9,mode="road",id=7,units=8},{seq=10,mode="road",id=7,units=4}}}
assert(P.accept_batch(area,{ok=true,seq=31,tick=962,value={again}}))
local pulses=P.take_boardings()
assert(#pulses==1 and pulses[1].units==4 and P.waiting("road",7)==109)
P.unsubscribe("waiting");assert(P.waiting("road",7)==0)
print("PASS visible boarding receipts never replay on actor/scene refresh")

local aa,bb=P.subscribe("motion-left"),P.subscribe("motion-right")
local function world(x,actors) return {scene=x,x=x,z=1,width=1,height=1,actors=actors,tiles={{id=x}}} end
local function whole(a,b) return {key="rail:1",complete_parts=true,parts={{index=1,tile=a},{index=2,tile=b}}} end
local both={{key="motion-left",token=aa},{key="motion-right",token=bb}}
assert(P.accept_batch(both,{ok=true,seq=40,tick=999,actor_us=500000,value={
  world(5,{whole(20,10)}),world(6,{whole(20,10)}),
}}))
assert(P.accept_motion({both[1]},{ok=true,seq=41,tick=999,actor_us=610000,value={world(5,{whole(24,14)})}}))
assert(P.accept_motion({both[2]},{ok=true,seq=42,tick=999,actor_us=735000,value={world(6,{whole(27,17)})}}))
local together=P.actors()["rail:1"].parts
assert(together[1].tile==27 and together[2].tile==17 and P.actor_clock()==735000)
assert(P.terrain(5,1).id==5 and P.terrain(6,1).id==6)
P.unsubscribe("motion-right")
assert(not P.accept_motion({both[2]},{ok=true,seq=43,tick=1000,actor_us=800000,value={world(6,{whole(100,100)})}}))
assert(P.actor_clock()==735000 and P.actors()["rail:1"].parts[1].tile==24)
print("PASS different fractions of one tick cannot splice consist poses; a cull never accepts late motion")
