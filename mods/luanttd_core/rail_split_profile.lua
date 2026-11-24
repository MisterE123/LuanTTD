-- Connect the source rail-height profile to native per-height mesh groups.
return function(Track,Height)
  local P={supported=Height.split,level=Height.curve_level}
  function P.groups(profile)
    local groups={}
    if not P.supported(profile) then return groups end
    for track=Track.UPPER,Track.RIGHT do
      local y=P.level(profile,track)
      if y then groups[y]=(groups[y] or 0)+Track.trackbit(track) end
    end
    return groups
  end
  function P.profile(shape,base,bits)
    local p=Height.profile({kind="rail",trackbits=bits},base,shape)
    if not P.supported(p) then return end
    p.groups=P.groups(p)
    p.mesh_key=("%d_%d_%d"):format(shape,p.surface,p.base_level-base)
    return p
  end
  return P
end
