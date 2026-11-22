-- Presentation only. Pick a frontage without mutating the saved house,
-- drawing a random number, or participating in the stock growth rules.
local H={}
-- Sim.dir uses north, east, south, west. Luanti facedir 0..3 sends the
-- positive-Z axis south, east, north, west, respectively.
local south_front={2,1,0,3}
local anchor_dx={[0]=0,0,1,1}
local anchor_dz={[0]=0,1,1,0}

function H.road(Sim,S,id,t)
  local best,score
  local first=(id-1)%4
  for i=0,3 do
    local d=(first+i)%4+1
    local neighbor=Sim.adjacent(id,d)
    local road=neighbor and S.tiles[neighbor]
    if road and not road.stock_void and (road.build=="road" or road.build=="road_station") then
      -- A level curb is preferable. Prefer a public town street over an
      -- equal-height company road; at a corner use a stable tile tie-break.
      local delta=math.abs((road.h or 0)-(t.h or 0))
      local rank=(delta==0 and 8 or delta==1 and 4 or 0)+(road.road_town and 2 or 0)
      if not score or rank>score then best,score=d,rank end
    end
  end
  return best
end

function H.placement(Sim,S,id,t,stage,parcel)
  if t.site or not t.house or parcel=="green" or parcel=="market" then return 0,0,0 end
  local direction=H.road(Sim,S,id,t)
  if not direction then return 0,0,0 end
  -- Completed houses and the corner grocer export their entrances on
  -- +Z. Construction-stage assets use the track-art exporter and put
  -- their access paths and future front doors on -Z instead.
  local facedir=(south_front[direction]+(stage and 2 or 0))%4
  -- Luanti rotates around the overlay node, not its 2×2 footprint center.
  -- Offset the anchor so the rotated parcel still occupies the same land.
  return anchor_dx[facedir],anchor_dz[facedir],facedir
end

return H
