local base="mods/luanttd_core/openttd/"
local W=dofile(base.."road_waypoint_build.lua")(dofile(base.."road_stop_build.lua"))
local id=function(x,z) return z*64+x end
local tiles={}
local b={id=id,xy=function(i) return i%64,math.floor(i/64) end,tile=function(i)return tiles[i] end}
local n,s=id(4,5),id(4,7)
for z=5,7 do
  tiles[id(4,z)]={slope=0,base=1,kind="road",road={bits=10,roadtype=0,owner="a"}}
end
local opts={company="a",piece_price=function()return 95 end}
assert(W.axis(tiles[n])==0)
local q=assert(W.quote(b,s,n,0,opts))
assert(q.cost==600 and q.ids[1]==n and q.ids[3]==s and q.changes[1].road==tiles[n].road)
assert(select(2,W.quote(b,n,s,1,opts))=="PARAMETERS")
opts.limit=2
assert(select(2,W.quote(b,n,s,0,opts))=="STATION_SPREAD")
opts.limit=12
tiles[n].tram={bits=4,roadtype=1,owner="a"}
assert(W.axis(tiles[n])==nil and select(2,W.quote(b,n,s,0,opts))=="DRIVE_THROUGH_JUNCTION")
tiles[n].tram=nil
tiles[n].road.bits=2
assert(W.axis(tiles[n])==0)
assert(W.quote(b,n,s,0,opts).cost==695)
tiles[n]={slope=0,base=1,kind="clear"}
assert(select(2,W.quote(b,n,s,0,opts))=="NO_ROAD")
tiles[n]={slope=0,base=1,kind="station",stop_type="road_waypoint",station=1,axis=0,through=true}
tiles[s]={slope=0,base=1,kind="station",stop_type="road_waypoint",station=2,axis=0,through=true}
assert(select(2,W.quote(b,n,s,0,opts))=="ADJOINS_MULTIPLE_WAYPOINTS")
tiles[s].station=1
q=assert(W.quote(b,n,s,0,opts))
assert(q.existing==1 and q.cost==200 and q.z==1)
local F=dofile(base.."yapf_road_follow.lua")
local Cost=dofile(base.."yapf_road_cost.lua")(F)
local out={tile=id(4,6),w=1,h=2}
local board={xy=b.xy,tile_at=b.id,tile=function()return {kind="drive_stop",stop_type="road_waypoint",station=1} end,
  station_area=function(which,type)
    assert(which==1)
    return type=="road_waypoint" and out or nil,s
  end,
  adjacent=function()error("the stock routing cost must skip stop-queue checks at waypoints")end}
local dest=Cost.destination(board,{tile=id(1,12),bus=true,articulated=true},{kind="road_waypoint",station=1})
assert(dest.tile==id(4,7) and dest.stop_type=="road_waypoint" and not dest.non_articulated)
assert(Cost.detect(board,dest,n,0) and Cost.one_tile(board,n,0)==100)
local terminal=Cost.destination(board,{tile=id(1,12),bus=true},{kind="station",station=1})
assert(not Cost.detect(board,terminal,n,0))

print("PASS RC1 road waypoint axis, perpendicular drag, priced retained pavement and uniform station area")
