local src="mods/bayline/openttd/"
local T=dofile(src.."rail_track.lua")
local W=dofile(src.."ship_follow.lua")(T)
local Y=dofile(src.."ship_yapf.lua")(T,W,dofile(src.."yapf_road_search.lua"))
local M=dofile(src.."ship_motion.lua")(T,W)
local side={[0]=-1,30,1,-30}
local tiles={}
local function id(x,z) return x+30*z end
local B={xy=function(i)return i%30,math.floor(i/30) end,
  tile_at=id,tile=function(i)return tiles[i]end,adjacent=function(i,d)return i+side[d]end}
for x=10,17 do tiles[id(x,10)]={kind="canal"} end
local near=id(13,10)
local alt,ordered=id(17,9),id(18,9)
tiles[near].docking=true
tiles[id(13,9)]={kind="dock",water_part=true,station=7}
tiles[ordered]={kind="dock",water_part=true,station=2}
tiles[alt]={kind="canal",docking=true}
assert(tiles[id(18,10)]==nil, "front shore berth is deliberately inaccessible")
assert(W.ship_destination(B,near,7) and not W.ship_destination(B,near,2))
assert(W.ship_destination(B,alt,2))
local v=assert(M.new(B,id(10,10),8,{order={kind="station",id=2},acceleration=256,max_speed=256}))
local goal=Y.destination(B,v,{kind="station",station=2,tile=ordered})
local ok,best=Y.find(B,v,v.tile,T.trackdirbit(8),goal)
assert(ok and best.last_tile==alt)
assert(M.set_path(v,Y.trace(B,v,goal,best)))
local function save(value)
  if type(value)~="table" then return value end
  assert(not getmetatable(value))
  local out={}
  for k,x in pairs(value) do out[k]=save(x) end
  return out
end
local visited,loaded=false,false
local hooks={docking_area=function(_,i,st)return i==alt and st==2 end}
for _=1,500 do
  local e=M.tick(B,v,hooks)
  if not visited and v.tile==near and v.x%16==3 then
    assert(not v.loading and not v.last_station)
    v=save(v);visited=true
  end
  if e=="dock" then
    assert(visited and v.tile==alt and v.last_station==2 and v.loading)
    loaded=true;break
  end
end
assert(visited and loaded)
print("PASS: specified ship order rejects nearer unrelated dock, reaches alternate valid berth after on-route reload")
