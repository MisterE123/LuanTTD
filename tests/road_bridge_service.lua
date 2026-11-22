local root="mods/luanttd_core/"
local S=dofile(root.."sim.lua")
local T=dofile(root.."openttd/terrain.lua")
local s=S.new(1751)
for _,tile in ipairs(s.tiles) do
  tile.terrain="grass";tile.h=0;tile.wood=nil;tile.house=nil;tile.site=nil;tile.build=nil;tile.owner=nil
end
s.corner_grid=T.new(S.W,S.H)
s.road_economy=true;s.road_stock_clock=true
local function at(x,z) return S.id(x,z or 12) end
local function town(id,x)
  return {id=id,tile=at(x,11),name="Test town "..id,kind="town",population=360,
    produced={},received={},stock={},service=0}
end
s.sites={town(1,19),town(2,32)}
s.tiles[s.sites[1].tile].site=1;s.tiles[s.sites[2].tile].site=2
for x=24,26 do s.tiles[at(x)].terrain="water" end
local name="Bridge Crew"
local ok,msg=S.wood_bridge(s,name,at(23),at(27));assert(ok,msg)
assert(S.build(s,name,"road",S.line(at(18),at(23))))
assert(S.build(s,name,"road",S.line(at(27),at(33))))
assert(S.road_edge(s,at(23),4) and not S.road_edge(s,at(23),2))
assert(S.road_edge(s,at(27),2) and not S.road_edge(s,at(27),4))
assert(not S.build(s,name,"road",S.line(at(23),at(23,13))))
assert(S.build(s,name,"road_station",{at(18)}))
assert(S.build(s,name,"road_station",{at(33)}))
assert(S.build(s,name,"road_depot",{at(20,13)}))
local a,b=s.tiles[at(18)].station,s.tiles[at(33)].station
local id=assert(S.purchase(s,name,"bus","passenger",nil,at(20,13)))
local v=s.fleet[id]
assert(S.add_order(s,name,id,a))
assert(S.add_order(s,name,id,b))
assert(S.toggle(s,name,id))
local seen={}
for _=1,65 do
  S.daily(s)
  if v.route then
    local uses=false
    for _,tid in ipairs(v.route) do if tid==at(23) then uses=true end end
    if uses then assert(not S.remove_wood_bridge(s,name,at(23)), "active bridge itinerary was removed") end
    for _,f in ipairs(v.road_motion_frames or {}) do
      local x,z=S.xy(f[4])
      if z==12 and x>=24 and x<=26 then
        assert(f[10]==1 and f[12] and f[11]>0)
        seen[x]=true
      end
    end
  end
  if v.delivered>0 then break end
end
assert(seen[24] and seen[25] and seen[26] and v.delivered>0)
print("PASS: bus runs and pays across paired timber heads and every independently tagged deck tile")
