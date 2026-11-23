-- SPDX-License-Identifier: GPL-2.0-only
local mod="mods/luanttd_core/"
local src=mod.."openttd/"
local Sim=dofile(mod.."sim.lua")
local Track=dofile(src.."rail_track.lua")
local Follow=dofile(src.."rail_follow.lua")(Track)
local Slope=dofile(src.."slope.lua")
local Height=dofile(src.."rail_height.lua")(Track,Slope)
local Q=dofile(src.."rail_construction.lua")(Track)
local D=dofile(src.."rail_depot_construction.lua")(Track,Q)
local S=Sim.new(1707)
local owner="DepotQA"
local c=Sim.company(S,owner)
local shapes,fills={},{}
local function shape(id) return shapes[id] or 0,fills[id] or 0 end
local Lab=dofile(mod.."trackworks.lua")(Sim,Track,Follow,Slope,nil,nil,shape)
local updates={}
local saves=0
local raised
local B=dofile(mod.."rail_construction_tools.lua")({Sim=Sim,s=S,terrain={tile=shape},render={
  update=function(group) updates[#updates+1]=group[1] end,raise_bound=function(level) raised=level end
},save=function()saves=saves+1 end},Lab,Track,nil,{
  track=function(tile,p,o)
    local plan,why=Q.piece(tile,p.track,o);return plan and plan.cost,why
  end})
local function cell(x,z)
  local id=Sim.id(x,z)
  S.tiles[id]={terrain="grass",variant=1,h=0}
  return id
end
local function lay(id,bits,holder)
  local t=S.tiles[id]
  t.build,t.rail_tracks,t.owner="stock_rail",bits,holder or owner
end
local id=cell(14,18)
local exit=cell(15,18)
shapes[id],fills[id]=3,4
local bad,why=B.quote_depot(owner,id,Track.NE)
assert(not bad and why:find("cannot face down",1,true))
local q=assert(B.quote_depot(owner,id,Track.SW))
assert(q.price==970 and q.parts.clearing==20 and q.parts.foundation==250 and q.level==5 and q.foundation=="leveled")
assert(not S.tiles[id].build and c.cash==100000 and saves==0)
assert(B.build(owner,q))
assert(S.tiles[id].rail_depot_dir==Track.SW and S.tiles[id].rail_tracks==1 and not S.tiles[exit].rail_tracks)
assert(raised==5 and c.cash==99030 and saves==1)
local _,floor=Lab.depot_surface(shape(id))
local p=assert(Height.profile(Lab.board(S).tile(id),4))
for x=0,15 do assert(Height.pixel(p,x,8)==floor*8) end
local old=S.topology
local repeat_quote=assert(B.quote_depot(owner,id,Track.SW))
assert(repeat_quote.price==0 and repeat_quote.noop and B.build(owner,repeat_quote))
assert(S.topology==old and c.cash==99030 and saves==1)
q=assert(B.quote_depot(owner,id,Track.NW))
assert(q.rotate and q.price==950)
Lab.owned_depot_occupied=function(_,cell_) return cell_==id end
bad,why=B.build(owner,q)
assert(not bad and why:find("vehicles out",1,true) and S.tiles[id].rail_depot_dir==Track.SW)
Lab.owned_depot_occupied=nil
assert(B.build(owner,q))
assert(S.tiles[id].rail_depot_dir==Track.NW and S.tiles[id].rail_tracks==2 and c.cash==98080)
local foreign,foreign_reason=B.quote_depot("Other",id,Track.NW)
assert(not foreign and foreign_reason:lower():find("another company"))
local high=cell(13,18)
shapes[high],fills[high]=23,2
bad,why=B.quote_depot(owner,high,Track.NE)
assert(not bad and why:find("cannot face down",1,true))
q=assert(B.quote_depot(owner,high,Track.SW))
assert(q.level==4 and q.price==970 and B.build(owner,q))
local no_slope=cell(12,18);shapes[no_slope]=3
S.rail_build_on_slopes=false
bad,why=B.quote_depot(owner,no_slope,Track.SW)
assert(not bad and why:find("foundations are disabled",1,true))
S.rail_build_on_slopes=nil
local existing=cell(11,18);lay(existing,2)
bad,why=B.quote_depot(owner,existing,Track.SW)
assert(not bad and why:find("Remove the existing rails",1,true))
local under=cell(17,18);shapes[under],fills[under]=3,4
S.rail_bridge_above={[under]=1};S.stock_rail_spans={[1]={deck=7}}
bad,why=B.quote_depot(owner,under,Track.SW)
assert(not bad and why:find("1 height level too low",1,true))
S.stock_rail_spans[1].deck=8
q=assert(B.quote_depot(owner,under,Track.SW))
assert(B.build(owner,q) and S.rail_bridge_above[under]==1 and S.stock_rail_spans[1].deck==8)
local under2=cell(18,18)
S.rail_bridge_above[under2]=1
S.rail_tunnel_below={[under2]=3}
assert(not B.quote_depot(owner,under2,Track.SW))
-- Existing-mouth attachment spends separately. With exactly enough for a
-- depot plus one piece, later candidate failure does not undo construction.
local spur=cell(24,12);local mouth=cell(25,12);local across=cell(26,12)
lay(mouth,2)
c.cash=820
q=assert(B.quote_depot(owner,spur,Track.SW))
assert(q.price==720 and B.build(owner,q))
assert(S.tiles[spur].rail_depot_dir==Track.SW and S.tiles[mouth].rail_tracks==6 and c.cash==0)
assert(not S.tiles[across].rail_tracks)
-- Route/claim protection stays tile-local and rechecks a fresh receipt.
local active=cell(26,15)
c.cash=1500
q=assert(B.quote_depot(owner,active,Track.SW))
S.stock_rail_dispatch={runs={{local_signals=true,route={{tile=active}},consist={parts={}}}},signals={records={}}}
bad,why=B.build(owner,q)
assert(not bad and why:find("running train",1,true) and c.cash==1500)
print("PASS native depot quote/commit: foundations and level, paid rotate/no-op, exact bridge height, protected tiles, and independent paid connectors")
