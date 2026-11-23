local s={stock_generated_profile={},tiles={},companies={Company={paid_units=0}},fleet={},stations={}}
local Sim={road_connected=function() return true end}
local wanted={owner="Company",build="road_depot"}
s.tiles[41]=wanted
local guide=dofile("mods/luanttd_core/campaign_company_guide.lua")(Sim,s)
assert(guide.phase("Company")==4 and guide.phase("Rival")==2)
s.tiles[41]={terrain="grass"};guide.changed({tiles={41}})
assert(guide.phase("Company")==2)
s.stations[1]={owner="Company",mode="road",tile=5}
s.stations[2]={owner="Company",mode="road",tile=6}
assert(guide.phase("Company")==3)
s.fleet[1]={owner="Company",orders={{id=1},{id=2}}}
assert(guide.phase("Company")==6)
s.fleet[1].running=true
assert(guide.phase("Company")==7)
s.companies.Company.paid_units=3
assert(guide.phase("Company")==8)
print("PASS worker guidance uses indexed owner depot edits and live station, vehicle and delivery state")
