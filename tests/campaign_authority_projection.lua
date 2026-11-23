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
