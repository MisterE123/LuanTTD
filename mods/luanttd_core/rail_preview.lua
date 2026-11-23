-- Resolve AutoRail's private placement ghost against the board that this
-- quote would build. Never write to the real board, including tree tiles.
return function(api,root)
  local Sim,S=api.Sim,api.s
  local track=dofile(root.."openttd/rail_track.lua")
  local surface=api.trackworks.surface
  local terrain=api.terrain
  local diagonal=dofile(root.."rail_diagonal.lua")(Sim,track,terrain,surface)
  local limit=96
  return function(pieces,owner,eye)
    local tiles=setmetatable({},{__index=S.tiles})
    local projected={tiles=tiles}
    -- Resolve the full quote before drawing (also outside the visibility
    -- window), so its neighboring pieces pick the finished seam tangents.
    for _,p in ipairs(pieces) do
      local tile=S.tiles[p.id]
      tiles[p.id]=setmetatable({
        owner=owner,rail_tracks=p.tracks,
        level_crossing=p.crossing_quote and true or tile.level_crossing,
      },{__index=tile})
    end
    local first,last=1,#pieces
    if eye and last>limit then
      -- Never subsample a long drag: that paints gaps between the rails.
      -- Keep the contiguous part centered under the player's viewport.
      local nearest,best=1,math.huge
      for i,p in ipairs(pieces) do
        local x,z=Sim.xy(p.id)
        local d=(2*x+.5-eye.x)^2+(2*z+.5-eye.z)^2
        if d<best then nearest,best=i,d end
      end
      first=math.max(1,math.min(last-limit+1,nearest-math.floor(limit/2)))
      last=first+limit-1
    end
    local out={}
    for i=first,last do
      local p=pieces[i]
      local slope,base=terrain.tile(p.id)
      local grade,level=surface(slope,base,p.tracks)
      if grade then
        local x,z=Sim.xy(p.id)
        local mode=grade==0 and diagonal.mode(projected,p.id) or 0
        local mesh=mode>0 and ("bl_rail_eased_"..p.tracks.."_"..mode..".obj")
          or grade==0 and ("bl_rail_track_"..p.tracks..".obj")
          or ("bl_rail_grade_"..grade..".obj")
        out[#out+1]={id=p.id,mesh=mesh,
          pos={x=2*x,y=level+(grade==0 and 1 or 2)+.038,z=2*z}}
      end
    end
    return out
  end
end
