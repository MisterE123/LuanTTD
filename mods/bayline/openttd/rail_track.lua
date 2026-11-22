-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors; no warranty.
-- OpenTTD 14.1 track_type.h, track_func.h, rail.cpp and rail_cmd.cpp.
-- The side convention is stock NE=0, SE=1, SW=2, NW=3. In LuanTTD
-- world axes these correspond to -x, +z, +x, -z.
local R={X=0,Y=1,UPPER=2,LOWER=3,LEFT=4,RIGHT=5,NE=0,SE=1,SW=2,NW=3}
local floor=math.floor
local powers={}
for i=0,15 do powers[i]=2^i end
function R.has(bits,i) return floor(bits/powers[i])%2==1 end
function R.intersect(a,b)
  local out,i=0,0
  while a~=0 and b~=0 do
    if a%2==1 and b%2==1 then out=out+powers[i] end
    a,b,i=floor(a/2),floor(b/2),i+1
  end
  return out
end
function R.union(a,b) return a+b-R.intersect(a,b) end
function R.remove(a,b) return a-R.intersect(a,b) end
function R.reverse_side(side) return (side+2)%4 end
function R.valid_trackdir(td) return type(td)=="number" and td>=0 and td<14 and td%8<6 and td%1==0 end
function R.reverse_trackdir(td) return (td+8)%16 end
function R.track(td) return td%8 end
function R.trackbit(t) return powers[t] end
function R.trackdirbit(td) return powers[td] end
function R.trackdirs(trackbits) return trackbits*0x101 end
function R.trackbits(trackdirs) return R.union(trackdirs%64,floor(trackdirs/256)%64) end
function R.axis_track(side) return side%2 end
function R.tracks_overlap(bits)
  local n=bits
  if n==0 then return false end
  while n%2==0 do n=n/2 end
  return n~=1 and bits~=12 and bits~=48
end

-- Tables retain the original Track / Trackdir pitches and edge mappings.
local exit={[0]=0,1,0,1,2,1,false,false,2,3,3,2,3,0}
local reach={[0]=1+8+4096,2+16+4,256+1024+32,512+8192+2048}
local crosses={[0]=2+512,1+256,0x3030,0x3030,0x0c0c,0x0c0c}
local nexttd={[0]=0,1,3,2,5,4,false,false,8,9,11,10,13,12}
local stag={[0]=0,1,8,9}
local heading={[0]=1,3,2,2,4,4,false,false,5,7,6,6,0,0}
local uphill={[0]=0,0x300,0x102,0x100,3,0,2,0,0x201,0x200,0,0,1,0,0,
  0,0,0,0,0,0,0,0,0x102,0,0,0,0x300,0,0x201,3}
local along={[0]=8,8,8,2,4,1,0,0,4,4,4,1,8,2}
local against={[0]=4,4,4,1,8,2,0,0,8,8,8,2,4,1}
function R.exit_side(td) return exit[td] or nil end
function R.entry_side(td) return R.exit_side(R.reverse_trackdir(td)) end
function R.reachable(side) return reach[side] end
function R.crossing_trackdirs(td) return crosses[R.track(td)] end
function R.next_trackdir(td) return nexttd[td] or nil end
function R.diagonal_trackdir(side) return stag[side] end
function R.heading(td) return heading[td] or nil end
function R.uphill_trackdirs(slope) return uphill[slope] end
function R.signal_along(td) return along[td] end
function R.signal_against(td) return against[td] end

function R.trackdir_for_exit(track,side)
  if exit[track]==side then return track end
  if exit[track+8]==side then return track+8 end
end

-- "enterdir" is the travel direction across the boundary, not the side
-- of this tile. For example SE travel enters through this tile's NW side.
function R.trackdir_for_entry(track,enterdir)
  local reverse=R.trackdir_for_exit(track,R.reverse_side(enterdir))
  if reverse then return R.reverse_trackdir(reverse) end
end

-- GetTileTrackStatus_Track's signal byte handling. Red bits can contain
-- bits for absent tracks, just like the source. A plain rail follower
-- consumes only trackdirs; this status is separate from PBS search cost.
local red_groups={[8]=4096+1+2+4,[4]=16+256+512+1024,[2]=8192+8,[1]=32+2048}
local function red_signals(tile)
  local present=tile.present_signals or 0
  local green=R.intersect(present,tile.green_signals or 0)
  local function fill(signal_mask,pbs)
    if pbs or R.intersect(present,signal_mask)==0 then
      green=R.union(green,R.remove(signal_mask,present))
    end
  end
  fill(12,tile.upper_pbs)
  fill(3,tile.lower_pbs)
  local bits=0
  for signal,group in pairs(red_groups) do
    if R.intersect(green,signal)==0 then bits=bits+group end
  end
  return bits
end

-- Rail mode of GetTileTrackStatus (ordinary, signalled, crossing, station,
-- waypoint, depot, tunnel and bridge). Optional side is a tile boundary.
function R.status(tile,side)
  if not tile then return 0,0 end
  local kind=tile.kind
  if kind=="rail" or kind=="signals" then
    return R.trackdirs(tile.trackbits),kind=="signals" and red_signals(tile) or 0
  end
  if kind=="station" or kind=="waypoint" or kind=="crossing" then
    local active=kind=="crossing" or not tile.blocked
    return active and R.trackdirs(powers[tile.axis]) or 0,0
  end
  if kind=="depot" and (side==nil or side==tile.dir) or
      (kind=="bridge" or kind=="tunnel") and (side==nil or side==R.reverse_side(tile.dir)) then
    return R.trackdirs(powers[R.axis_track(tile.dir)]),0
  end
  return 0,0
end

-- GetRailFoundation's tables, indexed by the original bit-coded slope.
local unmodified={[0]=63,32,4,1,16,0,2,8,8,2,0,16,1,4,32}
local leveled={[0]=0,16,8,2+8+16,32,63,1+8+32,63,4,1+4+16,63,63,2+4+32,63,63}
local steep_corner={[23]=1,[27]=0,[29]=3,[30]=2}
local bits_by_corner={[0]=16,8,32,4}
local corner_by_bits={[16]=0,[8]=1,[32]=2,[4]=3}
local function subset(bits,available) return R.intersect(bits,available)==bits end

-- Compatible with openttd/slope.lua's foundation() vocabulary.
-- "invalid" is returned for stock-illegal combinations.
function R.foundation(slope,bits)
  if bits==0 then return "none" end
  if slope>=16 then
    local c=assert(steep_corner[slope],"expected valid raw steep slope")
    if bits==1 then return "x" end
    if bits==2 then return "y" end
    local high=bits_by_corner[c]
    if bits==high then return "half",c end
    if R.tracks_overlap(R.union(bits,high)) then return "invalid" end
    return R.intersect(bits,high)~=0 and "steep_both" or "steep_lower"
  end
  if subset(bits,assert(unmodified[slope],"expected valid raw slope")) then return "none" end
  local legal=subset(bits,leveled[slope])
  local flat=legal and "leveled" or "invalid"
  if bits==12 then
    if slope==8 then return "half",3 end
    if slope==2 then return "half",1 end
    return flat
  elseif bits==48 then
    if slope==1 then return "half",0 end
    if slope==4 then return "half",2 end
    return flat
  elseif bits==1 or bits==2 then
    if slope==1 or slope==2 or slope==4 or slope==8 then return bits==1 and "x" or "y" end
    return flat
  end
  local c=corner_by_bits[bits]
  if c==nil or not legal then return flat end
  if slope==7 or slope==11 or slope==13 or slope==14 then return "leveled" end
  if R.intersect(slope,15-powers[(c+2)%4])==powers[c] then return "half",c end
  return "rail",c
end

-- CheckRailSlope before command-specific ownership, traffic or cost checks.
-- Returns a decision and new foundation; the caller applies actual prices.
function R.build_slope(slope,build,existing,flooding,build_on_slopes)
  local all=R.union(build,existing)
  if flooding and slope<16 and not subset(all,leveled[slope]) then return false,"water" end
  local kind,c=R.foundation(slope,all)
  if kind=="invalid" or kind~="none" and not build_on_slopes then return false,"slope" end
  local previous,prevc=R.foundation(slope,existing)
  return true,kind,c,kind~=previous or c~=prevc
end

return R
