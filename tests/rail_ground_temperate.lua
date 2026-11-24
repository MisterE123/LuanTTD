local path="mods/luanttd_core/openttd/"
local Track=dofile(path.."rail_track.lua")
local Ground=dofile(path.."rail_ground_temperate.lua")(Track)
local current={plain=true,tracks=1,owner="rail company",ground=Ground.GRASS}
local secondary={owner="rail company",kind="rail"}
local absent={owner="another company",kind="rail"}
-- Map actual fence direction masks to the integer RailGroundType values.
local types={[0]=1,[1]=5,[2]=3,[4]=6,[8]=2,[5]=7,[10]=4,[3]=8,[9]=11,[6]=10,[12]=9}
local count={}
for tracks=1,63 do
  current.tracks=tracks
  for owners=0,15 do
    local expected=0
    for d=0,3 do
      local direct=false
      for t=Track.X,Track.RIGHT do
        if Track.has(tracks,t) and Track.trackdir_for_exit(t,d) then direct=true end
      end
      if not direct and not Track.has(owners,d) then expected=expected+2^d end
    end
    local actual,dispatch,edges=Ground.visit(current,function(d) return Track.has(owners,d) and secondary or absent end)
    assert(edges==expected and actual==types[expected] and dispatch==nil)
    count[actual]=(count[actual] or 0)+1
  end
end
for ground=1,11 do assert(count[ground]) end
current.tracks=1
local function f(kind,owned_land)
  return Ground.visit(current,function() return {owner=current.owner,kind=kind,owned_land=owned_land} end)
end
assert(f("house")==4 and f("industry")==4 and f("road")==4 and f("tunnelbridge")==4)
assert(f("object",false)==4 and f("object",true)==1 and f("water")==1)
assert(Ground.visit(current,function() end)==4)
local function used() error("No fence lookup for the first grassy visit, non-rail, or water") end
current.ground=Ground.BARREN; assert(Ground.visit(current,used)==Ground.GRASS)
current.ground=Ground.GRASS;current.plain=false;assert(Ground.visit(current,used)==Ground.GRASS)
current.ground=Ground.HALF_TILE_WATER;local retained,water=Ground.visit(current,used)
assert(retained==Ground.HALF_TILE_WATER and water=="water")
print("PASS RC1 Temperate rail ground: all ten fence states, 1,008 track/neighbor combinations and early ground transitions")
local mod="mods/luanttd_core/"
local sim=dofile(mod.."sim.lua")
local view=dofile(mod.."campaign_terrain_projection.lua")
local terrain=dofile(path.."terrain.lua")
local world=dofile(mod.."rail_ground_world.lua")(sim,Ground)
local state=sim.new(23)
state.corner_grid=terrain.new(sim.W,sim.H,function() return 1 end)
local center=sim.id(7,7)
state.tiles[center]={h=1,terrain="hill",build="stock_rail",rail_tracks=1,owner="rail company"}
state.tiles[sim.id(7,8)]={h=1,terrain="hill",build="road",owner="rail company"}
state.tiles[sim.id(7,6)]={h=1,terrain="hill",stock_object={kind="owned_land"},owner="rail company"}
assert(world.visit(state,7,7) and state.tiles[center].rail_ground==Ground.GRASS)
assert(world.visit(state,7,7) and state.tiles[center].rail_ground==3)
assert(not world.visit(state,7,7))
local projection=view.tile(state.tiles[center])
assert(projection.rail_ground==3 and view.matches_tile(state.tiles[center],projection))
local packed=dofile(mod.."packed_campaign.lua")
local restored=assert(packed.decode(packed.encode(state)))
assert(restored.tiles[center].rail_ground==3)
state.tiles[sim.id(7,6)].owner="foreign company"
assert(world.visit(state,7,7) and state.tiles[center].rail_ground==4)
assert(not view.matches_tile(state.tiles[center],projection))
print("PASS native rail ground: ownership, bounded projection changes, and packed tile roundtrip")
