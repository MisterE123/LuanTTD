local Y=dofile("mods/luanttd_core/openttd/yapf_road_follow.lua")
local function road(bits)
  return {kind="road",road_bits=bits,roadtype=0,owner="city"}
end
local tiles={[1]=road(10),[2]=road(15)}
local board={
  tile=function(i) assert(i~=nil);return tiles[i] end,
  adjacent=function(i,dir)
    if i==1 and dir==Y.SW then return 2 end
    if i==2 and dir==Y.NE then return 1 end
  end
}
local bus={owner="A",compatible={[0]=true}}
local sw=Y.direction_trackdir(Y.SW)
local function next_tile() return Y.follow(board,bus,1,sw) end
local f=next_tile()
assert(f.ok and f.tile==2 and f.exit==Y.SW and f.trackdirs==Y.reachable_trackdirs(Y.SW))
assert(table.concat(Y.trackdirs(f.trackdirs),",")=="5,8,10")
-- A one-sided ROAD_NE stub is physically present but has no normal bus
-- trackdir; the bus turns around on its previous full road tile.
tiles[2]=road(8)
f=next_tile()
assert(f.ok and f.reversed and f.tile==1 and f.trackdirs==1)
-- A genuine one-sided bay exposes the synthetic straight axis, can be
-- entered only from its entrance, and forces reverse before departing.
tiles[2]={kind="bay_stop",dir=Y.NE,roadtype=0,owner="A"}
f=next_tile()
assert(f.ok and f.station and f.tile==2 and f.trackdirs==2^sw)
local leaving=Y.follow(board,bus,2,sw)
assert(leaving.ok and leaving.reversed and leaving.tile==2 and leaving.exit==Y.NE and leaving.trackdirs==1)
tiles[2].dir=Y.SW
f=next_tile()
assert(f.ok and f.reversed and f.error==Y.EC_NO_WAY and f.tile==1)
-- Although private plain roads are generally reachable in stock, a
-- competitor's depot is specifically not passable.
tiles[2]={kind="depot",dir=Y.NE,owner="B",roadtype=0}
f=next_tile()
assert(f.ok and f.reversed and f.error==Y.EC_OWNER and f.tile==1)
tiles[2].owner="A"
f=next_tile()
assert(f.ok and f.tile==2 and not f.station and not f.reversed)
-- Actual paired spans are one follower step with known intervening cost.
tiles[1]={kind="bridge",dir=Y.SW,roadtype=0,other=2,skip=5,bridge_speed=46}
tiles[2]={kind="bridge",dir=Y.NE,roadtype=0,other=1,skip=5,road_speed=60,bridge_speed=46}
f=next_tile()
assert(f.ok and f.bridge and not f.tunnel and f.skip==5 and f.tile==2)
assert(Y.speed_limit(tiles[1],false)==92 and Y.speed_limit(tiles[2],false)==60)
-- Missing off-map tiles and a Bayline-specific grade gate both reuse
-- the actual stock reverse-at-end logic without inventing track.
tiles[1],tiles[2]=road(10),road(10)
board.edge_available=function() return false end
f=next_tile()
assert(f.ok and f.tile==1 and f.reversed)
board.edge_available=nil
tiles[2]=nil
f=next_tile()
assert(f.ok and f.tile==1 and f.reversed)
print("PASS: directional road transitions, reversal, stop/depot orientation and grade adapter")
