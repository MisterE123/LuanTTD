local root="mods/luanttd_core/openttd/"
local T=dofile(root.."rail_track.lua")
local S=dofile(root.."rail_signals.lua")(T)
local H=dofile(root.."rail_height.lua")(T,dofile(root.."slope.lua"))
local Q=dofile(root.."rail_construction.lua")(T,S,H)
local o={owner="A"}
local function expect_error(err,plan,why)
  assert(not plan and why==err,tostring(why).." != "..err)
end
local function rail(bits,shape)
  return {kind="rail",trackbits=bits,owner="A",railtype=0,slope=shape or 0,base_level=2}
end
local function ground(shape,density)
  return {kind="clear",ground="grass",density=density,slope=shape or 0,base_level=2}
end
local function station(id,axis)
  return {kind="station",station=id,axis=axis,owner="A",railtype=0,base_level=2}
end
assert(Q.rail_price(0)==100 and Q.rail_clear_price(0)==-70)
assert(Q.rail_price(1)==150 and Q.rail_price(2)==200 and Q.rail_price(3)==300)
assert(Q.prices(0).rail==75 and Q.prices(2).rail==112)
assert(Q.prices(2,65536).clear_rail==-79)
-- RC1 chooses the requested construction price, then (only when
-- needed) charges separately for all existing track being converted.
local function typed(bits,r)
  local t=rail(bits);t.railtype=r;return t
end
for r=0,3 do
  local ask={owner="A",railtype=r}
  local price=({[0]=100,150,200,300})[r]
  local first=assert(Q.piece(ground(0,0),T.X,ask))
  assert(first.railtype==r and first.cost==price and not first.convert_from)
  local branch=assert(Q.piece(typed(1,r),T.Y,ask))
  assert(branch.railtype==r and branch.cost==price and branch.trackbits==3 and not branch.convert_from)
  for incompatible=2,3 do
    if incompatible~=r then
      expect_error("IMPOSSIBLE_TRACK_COMBINATION",Q.piece(typed(1,r),T.X,{owner="A",railtype=incompatible}))
    end
  end
end
local overlay=assert(Q.piece(typed(12,0),T.X,{owner="A",railtype=1}))
assert(overlay.railtype==1 and overlay.convert_from==0 and overlay.parts.track==150 and
  overlay.parts.conversion==136 and overlay.cost==286)
local retain=assert(Q.piece(typed(1,1),T.Y,{owner="A",railtype=0}))
assert(retain.railtype==1 and retain.cost==100 and retain.parts.conversion==0)
expect_error("INVALID_PARAMETER",Q.piece(ground(),T.X,{owner="A",railtype=3,available=false}))
expect_error("OWNED_BY_ANOTHER",Q.piece(typed(1,3),T.X,{owner="B",railtype=0}))

local plan=assert(Q.piece(ground(0,0),T.X,o));assert(plan.cost==100 and plan.profile.base_z==16)
plan=assert(Q.piece(ground(),T.Y,o));assert(plan.cost==120 and plan.parts.clearing==20)
plan=assert(Q.piece(ground(8,0),T.X,o));assert(plan.cost==350 and plan.foundation_changed and plan.profile.surface==12)
local t=rail(8,7)
plan=assert(Q.piece(t,T.X,o));assert(plan.cost==350 and plan.foundation=="leveled" and plan.foundation_changed)
plan=assert(Q.piece(rail(1,7),T.Y,o));assert(plan.cost==100 and plan.foundation=="leveled" and not plan.foundation_changed)
expect_error("ALREADY_BUILT",Q.piece(rail(1),T.X,o))
expect_error("OWNED_BY_ANOTHER",Q.piece(rail(1),T.Y,{owner="B"}))
expect_error("LAND_SLOPED_IN_WRONG_DIRECTION",Q.piece(ground(8,0),T.X,{owner="A",build_on_slopes=false}))
t=rail(4);t.train_bits=4
assert(Q.piece(t,T.LOWER,o))
expect_error("VEHICLE_IN_THE_WAY",Q.piece(t,T.X,o))
t.kind="signals";t.present_signals=8;t.train_bits=0;t.reserved_bits=4
assert(Q.piece(t,T.LOWER,o))
expect_error("MUST_REMOVE_SIGNALS_FIRST",Q.piece(t,T.X,o))
plan=assert(Q.piece(t,T.X,{owner="A",auto_remove_signals=true}))
assert(plan.kind=="rail" and plan.cost==110 and plan.remove_signals[1]==T.UPPER and plan.affected_reservations==4)
local shore={kind="water",slope=8,coast=true,base_level=0}
plan=assert(Q.piece(shore,T.UPPER,o))
assert(plan.water_ground and plan.parts.clearing==40 and plan.cost==390)
expect_error("CANT_BUILD_ON_WATER",Q.piece(shore,T.X,o))
expect_error("UNSUPPORTED_LEVEL_CROSSING",Q.piece({kind="road",slope=0},T.X,o))

assert(Q.depot(ground(),T.SW,o).cost==720)
expect_error("MUST_REMOVE_RAILROAD_TRACK",Q.depot(rail(1),T.SW,o))
local depot={kind="depot",railtype=0,dir=T.SW,owner="A",overhead=true,slope=0,base_level=2}
plan=assert(Q.depot(depot,T.NE,o));assert(plan.rotate and plan.cost==700)
expect_error("ALREADY_BUILT",Q.depot(depot,T.SW,o))
depot.occupied=true;expect_error("VEHICLE_IN_THE_WAY",Q.depot(depot,T.NE,o))
expect_error("MUST_DEMOLISH_BRIDGE_FIRST",Q.depot({kind="clear",overhead=true},T.NE,o))
assert(Q.depot(ground(29,0),T.NE,o).cost==950)
expect_error("FLAT_LAND_REQUIRED",Q.depot(ground(29,0),T.SW,o))

assert(Q.signal(rail(1),T.X,{kind=S.PBS},o).cost==65)
local signalled=rail(12);signalled.kind="signals";signalled.present_signals=9;signalled.lower_variant=1
assert(Q.signal(signalled,T.LOWER,{kind=S.PBS,skip=true},o).cost==0)
assert(Q.signal(signalled,T.LOWER,{kind=S.PBS,convert=true,variant=1},o).cost==0)
assert(Q.signal(signalled,T.LOWER,{kind=S.PBS,convert=true,variant=0},o).cost==75)
assert(Q.signal(signalled,T.LOWER,{kind=S.PBS,copy_mask=1,variant=0},o).cost==75)
assert(Q.signal(signalled,T.UPPER,{kind=S.PBS,ctrl=true},o).cost==0)
expect_error("INVALID_PARAMETER",Q.signal(signalled,T.UPPER,{copy_mask=1},o))
expect_error("NO_SUITABLE_RAILROAD_TRACK",Q.signal(rail(3),T.X,nil,o))

local bare={}
for i=1,6 do bare[i]=ground(0,0) end
plan=assert(Q.station(bare,T.X,1,6,o))
assert(plan.cost==2520 and plan.parts.length==720)
plan=assert(Q.station(bare,T.Y,2,3,o))
assert(plan.cost==2340 and plan.tiles[1].cost==480 and plan.tiles[3].cost==480)
plan=assert(Q.station({station(7,T.X),rail(1),station(7,T.X),ground(0,0)},T.X,1,4,o))
assert(plan.cost==890 and plan.existing_station==7 and plan.tiles[1].cost==0 and plan.tiles[3].cost==0)
expect_error("ADJOINS_MORE_THAN_ONE_EXISTING",Q.station({station(7,T.X),station(8,T.X)},T.X,1,2,o))
expect_error("FLAT_LAND_REQUIRED",Q.station({ground(3,0)},T.X,1,1,o))
assert(Q.station({ground(9,0)},T.X,1,1,o).cost==730)
local built=rail(1);built.reserved_bits=1
assert(Q.station({built},T.X,1,1,o).tiles[1].affected_reservations==1)
assert(Q.station({built},T.X,1,1,o).cost==410)
expect_error("MUST_REMOVE_RAILROAD_TRACK",Q.station({rail(2)},T.X,1,1,o))
print("PASS: rail construction quote components, slope/overlap/ownership rules, stock depot/signal cost and station row charges")
