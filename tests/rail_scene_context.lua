local root="mods/luanttd_core/"
local S=dofile(root.."sim.lua")
S.W,S.H=64,64
local T=dofile(root.."openttd/terrain.lua")
local Track=dofile(root.."openttd/rail_track.lua")
local Grade=dofile(root.."trackworks.lua")(S,Track,nil,dofile(root.."openttd/slope.lua"))
local world=S.new(1751)
world.corner_grid=T.new(64,64,function() return 2 end)
world.fleet={}
local function at(x,z) return S.id(x,z) end
local split=dofile(root.."rail_diagonal.lua")(S,Track,{tile=function() return 0,2,2 end},Grade.surface,Grade.split_surface)
local C=dofile(root.."rail_scene_context.lua")
local function tile(x,z,bits,gfx,station,gauge)
  world.tiles[at(x,z)]={h=2,variant=0,terrain="grass",owner="QA",rail_tracks=bits,rail_station_gfx=gfx,
    rail_station_id=station,rail_type=gauge}
end
tile(16,16,8)
tile(16,17,4)
tile(16,21,1,4,20);tile(17,21,1,4,20)
tile(21,16,2,5,21);tile(21,17,2,5,21)
tile(16,22,1,6,20);tile(17,22,1,6,20)
local context=C.make(S,split,{tile=function() return 0,2,2 end})
local R={world=world,terrain=T,rail_scene_context=context,terrain_projection=dofile(root.."campaign_terrain_projection.lua")}
local A=dofile(root.."campaign_authority_endpoint.lua")(S,R)
local function read(x,z,known)
  return assert(A.snapshots({{x=x,z=z,w=1,h=1,scene=known}}).value)[1]
end
local a,b,c=read(16,16),read(16,21),read(21,17)
assert(C.mode(a.tiles[1].rail_diagonal,8)==2 and b.tiles[1].rail_canopy==6 and c.tiles[1].rail_canopy==1)
assert(not read(16,16,a.scene).tiles and not read(16,21,b.scene).tiles)
tile(16,17,4,nil,nil,1)
tile(17,21,1,4,999)
local x,y=read(16,16,a.scene),read(16,21,b.scene)
assert(x.scene~=a.scene and not x.tiles[1].rail_diagonal)
assert(y.scene~=b.scene and y.tiles[1].rail_canopy==4)
assert(not read(21,17,c.scene).tiles)
tile(17,21,1,4,20)
assert(read(16,21,y.scene).tiles[1].rail_canopy==6)
print("PASS single-tile scenes keep full diagonal and roof context and invalidate on out-of-window neighbor edits")

local id0,id1=at(22,20),at(22,21)
local cost,mesh=100,"rail_eased_4_3.obj"
local build={
  quote_autotrack=function()
    return {ids={id0,id1},price=cost,pieces={{id=id0,tracks=8},{id=id1,tracks=4}}}
  end,
  build=function(owner,plan)
    S.company(world,owner).cash=S.company(world,owner).cash-plan.price
    return true
  end,
}
R.rail={build=build}
R.rail_preview=function()
  return {{id=id1,mesh=mesh,pos={x=44,y=3.038,z=42}}}
end
local n="Buyer"
local c=S.company(world,n)
local cash=c.cash
local req={tool="autotrack",start={x=22*16+8,z=20*16+8},finish={x=22*16+8,z=21*16+8}}
local q=assert(A.rail_quote(n,req,true).value)
assert(q.cost==100 and q.draw[1].mesh==mesh and q.ticket and not q.pieces and c.cash==cash)
assert(not A.rail_place(n,req).ok and c.cash==cash)
mesh="rail_eased_4_1.obj"
assert(not A.rail_place(n,req,q.ticket).ok and c.cash==cash)
mesh=q.draw[1].mesh;cost=120
assert(not A.rail_place(n,req,q.ticket).ok and c.cash==cash)
q=assert(A.rail_quote(n,req,true).value)
local r=A.rail_place(n,req,q.ticket)
assert(r.ok and r.value.cost==120 and #r.value.tiles==2 and c.cash==cash-120)
print("PASS transactional AutoRail checks displayed authoritative ghost and price; changed mesh, price or missing preview cannot spend")

-- The branching direction touches an electrified cell outside the one
-- requested render cell. The source mask must still invalidate the cache.
local Wire=dofile(root.."rail_turnout_wire.lua")(S,Track,dofile(root.."openttd/rail_wire_mask.lua")(Track))
R.rail_wire_mask=Wire.at
tile(36,16,33,nil,nil,1)
tile(35,16,1,nil,nil,1);tile(37,16,1,nil,nil,1)
tile(36,17,2)
local e=read(36,16)
assert(e.tiles[1].rail_wire==1 and not read(36,16,e.scene).tiles)
tile(36,17,2,nil,nil,1)
local both=read(36,16,e.scene)
assert(both.scene~=e.scene and both.tiles[1].rail_wire==33)
tile(36,17,2)
assert(read(36,16,both.scene).tiles[1].rail_wire==1)
print("PASS authoritative wire mask across sector edge recognizes powered, unpowered and removed branch")
