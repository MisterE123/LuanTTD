local mod="mods/luanttd_core"
local xy=function(n) return n%100,math.floor(n/100) end
local Sim={xy=xy,road_loading_events=function()
  return {{kind="board",cargo="passenger",data={tile=203,units=4}},
    {kind="fare",owner="A",data={tile=203,amount=80}},
    {kind="fare",owner="B",data={tile=306,amount=0}},
    {kind="fare",owner="C",data={tile=802,amount=90}}}
end,rail_loading_events=function()
  return {{kind="fare",owner="D",amount=100,tile=304}}
end}
local Q=dofile(mod.."/campaign_passenger_projection.lua")(Sim,{tiles={[203]={station=5}}})
Q.collect()
Q.collect_fares({{kind="fare",owner="E",amount=140,tile=101}},"ship")
local region={x=1,z=1,w=5,h=5}
local board,last,fares=Q.events({region},0)
assert(#board==1 and board[1].units==4 and board[1].id==5 and last==5)
assert(#fares==3 and fares[1].owner=="A" and fares[2].owner=="D" and fares[3].owner=="E")
local P=dofile(mod.."/campaign_authority_projection.lua")()
local a=P.subscribe("a")
local b=P.subscribe("b")
local function packet() return {x=1,z=1,width=5,height=5,boardings=board,fares=fares} end
assert(P.accept_batch({{key="a",token=a},{key="b",token=b}},{ok=true,seq=1,value={packet(),packet()}}))
assert(#P.take_boardings()==1)
local received=P.take_cash_sounds()
assert(#received==3 and received[1].tile==203 and received[2].tile==304 and received[3].tile==101)
assert(#P.take_cash_sounds()==0 and #P.take_boardings()==0)
print("PASS: approved delivery income cues remain owner-scoped, window-local and deduplicated even across overlapping worker views.")
