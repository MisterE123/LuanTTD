local root="mods/luanttd_core/"
local src=root.."openttd/"
local S=dofile(root.."sim.lua")
local T=dofile(src.."rail_track.lua")
local Terrain=dofile(src.."terrain.lua")
local Water=dofile(src.."ship_follow.lua")(T)
local D=dofile(src.."ship_facilities.lua")(T,Water)
local N=dofile(root.."ship_network.lua")(S,Terrain,Water,D)
local s=S.new(1751)
s.corner_grid=Terrain.new(S.W,S.H,function(x)return x<15 and 1 or 0 end)
local function at(x,z)return S.id(x,z)end
for _,t in ipairs(s.tiles) do
  t.terrain="grass";t.owner=nil;t.site=nil;t.house=nil;t.build=nil;t.wood=nil
end
local B=N.board(s)

-- A TerraGenesis coast has a distinctive flag, not dry 'clear' land.
-- The legal straight slope is clearable as PR_CLEAR_ROUGH. It must not
-- bypass overlays, mutate a quote, or become flat when a dock is removed.
local shore,pier,approach=at(14,20),at(15,20),at(16,20)
s.tiles[shore].coastal_water=true
for _,id in ipairs({pier,approach}) do s.tiles[id].terrain="water";s.tiles[id].water_class="sea" end
local purse=S.company(s,"A")
local before=purse.cash
local coastal=assert(N.quote(s,"A","dock",shore))
assert(coastal.cost==390 and coastal.water==pier and coastal.approach==approach)
assert(purse.cash==before and not s.tiles[shore].ship)
s.tiles[shore].house={};local no,why=N.quote(s,"A","dock",shore)
assert(not no and why=="PROTECTED_TILE");s.tiles[shore].house=nil
s.tiles[shore].wood=true;no,why=N.quote(s,"A","dock",shore)
assert(no and no.cost==370 and s.tiles[shore].wood);s.tiles[shore].wood=nil
s.tiles[pier].airfield=1;no,why=N.quote(s,"A","dock",shore)
assert(not no and why=="PROTECTED_TILE");s.tiles[pier].airfield=nil
assert(N.build(s,"A","dock",shore) and purse.cash==before-390)
assert(N.remove(s,"A",shore) and s.tiles[shore].coastal_water and B.tile(shore).kind=="coast")
print("PASS: generated bare coast accepts stock-priced dock; protected shore and water overlays remain protected")
