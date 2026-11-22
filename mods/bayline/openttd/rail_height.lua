-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors; no warranty.
-- OpenTTD 14.1 rail_cmd.cpp GetSlopePixelZ_Track, station_cmd.cpp
-- GetSlopePixelZ_Station, and ground_vehicle.hpp UpdateInclination.
-- Integer stock height is distinct from continuous native presentation.
return function(Track,Slope)
  local H={TILE_SIZE=16,TILE_HEIGHT=8}
  local floor,atan=math.floor,math.atan
  local raw={[0]=true,[23]=true,[27]=true,[29]=true,[30]=true}
  for i=1,14 do raw[i]=true end
  local flat_facility={station=true,waypoint=true,depot=true,crossing=true}
  local axis={[3]=Track.X,[12]=Track.X,[6]=Track.Y,[9]=Track.Y}
  local edges={[0]={0,.5},{.5,1},{1,.5},{.5,0}}

  -- tile.slope is the RAW shared-corner shape, not the surface after
  -- foundation. base_level is the lowest terrain corner of this tile.
  -- Native board geometry may pass an authoritative raw shape separately.
  function H.profile(tile,base_level,raw_shape)
    if not tile or type(base_level)~="number" or base_level%1~=0 then return nil,"no_tile_height" end
    local shape=raw_shape or tile.slope or 0
    if not raw[shape] then return nil,"invalid_raw_slope" end
    local kind=tile.kind
    local surface,rise,foundation,corner
    if kind=="rail" or kind=="signals" then
      local bits=tile.trackbits
      if type(bits)~="number" or bits<1 or bits>63 or bits%1~=0 then return nil,"no_tracks" end
      foundation,corner=Track.foundation(shape,bits)
      if foundation=="invalid" then return nil,"invalid_foundation" end
      surface,rise=Slope.foundation(shape,foundation,corner)
    elseif flat_facility[kind] then
      -- Railway depots, all station tiles, and road/rail level crossings
      -- sample the highest raw terrain corner; never sample a ramp here.
      surface,rise=0,shape>=16 and 2 or shape~=0 and 1 or 0
      foundation=rise==0 and "none" or "leveled"
    else return nil,"unsupported_height_tile" end
    local bits=tile.trackbits
    if kind=="depot" then
      if type(tile.dir)~="number" or tile.dir%1~=0 or tile.dir<0 or tile.dir>3 then return nil,"invalid_depot_facing" end
      bits=2^(tile.dir%2)
    elseif kind=="station" or kind=="waypoint" or kind=="crossing" then
      if tile.axis~=Track.X and tile.axis~=Track.Y then return nil,"invalid_facility_axis" end
      bits=2^tile.axis
    end
    return {kind=kind,surface=surface,raw_shape=shape,foundation=foundation,corner=corner,
      base_level=base_level+rise,base_z=(base_level+rise)*H.TILE_HEIGHT,
      trackbits=bits}
  end

  -- OpenTTD returns integer vertical pixels. Inline callers may use
  -- absolute or local integer subcoordinates; the stock tile mask agrees.
  function H.pixel(profile,x,y)
    return profile.base_z+Slope.pixel(x%16,y%16,profile.surface)
  end

  function H.bind(board,terrain_tile)
    local function profile(id)
      local shape,base_level=terrain_tile(id)
      return H.profile(board.tile(id),base_level,shape)
    end
    return function(id,x,y)
      local p,why=profile(id)
      if not p then return nil,why end
      return H.pixel(p,x,y)
    end,profile
  end

  -- TileMayHaveSlopedTrack is TRACK_BIT_X or TRACK_BIT_Y on the individual
  -- vehicle, not a test of the whole tile's multi-track mask. Call on
  -- entry, when the unit is at an edge and points toward the tile centre.
  function H.enter(profile,pose)
    local z=H.pixel(profile,pose.x,pose.y)
    local track=Track.track(pose.td)
    local middle=(track==Track.X or track==Track.Y) and H.pixel(profile,8,8) or z
    return {z=z,up=middle>z,down=middle<z}
  end

  -- SwapTrainFlags at an on-track reversal: the location keeps its
  -- exact pixel height; the outgoing flags are inherited and inverted.
  function H.reverse(prior)
    return {z=prior.z,up=prior.down,down=prior.up}
  end

  -- GroundVehicle::UpdateInclination. For a within-tile call the pose
  -- must be one committed stock movement step after prior, not a render
  -- interpolation. A mismatch is corrupt/out-of-envelope state, not a
  -- reason to apply a fake speed penalty or silently adjust the height.
  function H.advance(profile,pose,prior,new_tile)
    if not prior or new_tile then return H.enter(profile,pose),prior and prior.z or nil end
    local z,up,down=prior.z,prior.up,prior.down
    if up and down then return nil,"invalid_inclination" end
    if up or down then
      local dir=floor(pose.direction/2)
      local sub=dir%2==0 and pose.x or pose.y
      local change=sub%2
      if dir==Track.NE or dir==Track.NW then change=1-change end
      z=z+(up and change or -change)
    end
    if z~=H.pixel(profile,pose.x,pose.y) then return nil,"stock_height_invariant" end
    return {z=z,up=up,down=down},prior.z
  end

  -- Continuous PROFILE for existing authored native meshes only:
  -- flat/leveled track or any supported single straight on an inclined
  -- foundation/natural side slope. Pitch is signed uphill-positive in
  -- travel coordinates, NOT a Luanti Euler angle around a model's axis.
  -- Other stock foundations remain queryable via pixel() but must not
  -- invent a 3D surface where the game has no matching mesh.
  function H.render(profile,td,progress,width,level_height)
    if not Track.valid_trackdir(td) or not Track.has(profile.trackbits,Track.track(td)) then return end
    if profile.surface==0 then return profile.base_level,0,0 end
    if axis[profile.surface]~=Track.track(td) or profile.trackbits~=2^Track.track(td) then return end
    local a,b=edges[Track.entry_side(td)],edges[Track.exit_side(td)]
    local h0=Slope.surface(a[1],a[2],profile.surface)
    local h1=Slope.surface(b[1],b[2],profile.surface)
    local rise=h1-h0
    return profile.base_level+h0+rise*progress,atan(rise*(level_height or 1)/(width or 2)),rise
  end
  return H
end
