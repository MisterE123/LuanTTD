-- Original RC1 trace: country field joined to physical StationID 1.
-- Airport at (43,52), through bus stop at (43,47), unchanged sign.
local mod="mods/luanttd_core/openttd/"
local P=dofile(mod.."passengers.lua")
local K=dofile(mod.."station_rating.lua")
local C=dofile(mod.."station_catchment.lua")(P,K,function() return 8 end,function() return 0 end)
local tiles={{x=43,y=47,kind="bus",station=1}}
for y=52,54 do for x=43,46 do tiles[#tiles+1]={x=x,y=y,kind="airport",station=1} end end
local st={id=1,owner="Mixed",tiles=tiles,stock_bitmap_iteration=true}
local region=C.build(st,128,128,true)
local n=0
for _ in pairs(region.tiles) do n=n+1 end
assert(n==160 and region.facilities.bus and region.facilities.airport)
assert(C.contains(region,40,44) and C.contains(region,39,48))
assert(not C.contains(region,40,43) and not C.covers_area(region,40,43,1,1))
assert(C.bitmap_iteration_only_tile(region)==5544) -- native bitmap trace's 161st, traversal only
local function house(x,y)
  return x==40 and y==43 and {id=1,town=0} or nil
end
assert(C.acceptance(region,"passenger",house).eighths==8)
st.stock_bitmap_iteration=nil
assert(C.acceptance(C.build(st,128,128,true),"passenger",house).eighths==0)
print("PASS mixed RC1 station union and distinct Contains/iterator semantics")
