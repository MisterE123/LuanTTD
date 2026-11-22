local root="mods/luanttd_core/"
local src=root.."openttd/"
local S=dofile(root.."sim.lua")
local T=dofile(src.."terrain.lua")
local P=dofile(src.."passengers.lua")
local Rating=dofile(src.."station_rating.lua")
local I=dofile(src.."income.lua")
local Catchment=dofile(src.."station_catchment.lua")(P,Rating,function()return 0 end,function()return 0 end)
local Coal=dofile(src.."coal_industry.lua")(P,Rating,Catchment,I)
local W=dofile(root.."coal_industry_world.lua")(S,T,Coal)
local s=S.new(1751)
s.corner_grid=T.new(S.W,S.H,function(x) return x>=23 and 1 or 0 end)
for _,t in ipairs(s.tiles) do
  t.terrain="grass";t.h=0;t.wood=nil;t.house=nil;t.site=nil;t.build=nil;t.owner=nil
end
local function at(x,z) return S.id(x,z) end
local changes0=s.topology
local first=assert(W.quote(s,"coal_mine",at(6,9)))
assert(#first.cells==6 and s.topology==changes0 and not s.stock_coal_industries)
local test,why=W.seed(s,at(6,9),at(8,9))
assert(not test and why=="INDUSTRIES_OVERLAP" and s.topology==changes0)
assert(not W.quote(s,"power_station",at(21,10)))
local result=assert(W.seed(s,at(6,9),at(14,9)))
assert(#result.tiles==14 and s.topology==changes0+2)
local mine,power=s.stock_coal_industries[result.mine],s.stock_coal_industries[result.power]
assert(mine.x==5 and mine.z==8 and mine.produced.rate==15 and #mine.tiles==6)
assert(power.x==13 and power.accepted.waiting==0 and #power.tiles==8)
assert(s.tiles[at(6,10)].stock_industry==nil and s.tiles[at(6,11)].stock_industry==nil)
assert(s.tiles[at(6,9)].stock_industry.x==0 and s.tiles[at(7,10)].stock_industry.gfx==0)
assert(s.tiles[at(17,10)].stock_industry.gfx==10)
assert(s.sites[#s.sites-1].kind=="stock_coal_mine" and s.sites[#s.sites].kind=="stock_power_station")
print("PASS: two exact completed coal facilities, 14 original footprint tiles, permit/overlap/height checks and untouched stock mine holes")
