-- Bounded non-flooding state for open sea enclosed by open sea.
-- Single simulation owner only. Call reset before external edits.
return function(Sim,s)
  local C={}
  local width,tiles,floor=Sim.W,s.tiles,math.floor
  -- One 32-bit word per 32 cells at most; do not allocate one
  -- Lua table entry for every tile of a large ocean.
  local quiet_water,flag={},{}
  for i=0,31 do flag[i]=2^i end
  local function open_water(t)
    return t and t.terrain=="water" and t.water_class=="sea" and
      not (t.coastal_water or t.wood or t.build or t.ship or t.station or t.rail_tracks or
        t.tram or t.airfield or t.stock_industry or t.stock_landmark or t.stock_object or
        t.stock_void or t.stock_canal)
  end
  function C.visit(water,x,z,tick,id,record)
    local cell=id-1
    local word,mask=floor(cell/32)+1,flag[cell%32]
    local quiet=quiet_water[word] or 0
    if floor(quiet/mask)%2==1 then return 0 end
    local old=s.changed and #s.changed or 0
    local changed=water(x,z,tick)
    if changed>0 then
      -- Invalidate the actual touched sea neighbors as in RC1's
      -- ClearNeighbourNonFloodingStates. Other authoritative writes
      -- invalidate the worker cache before the next source tick.
      for i=old+1,#s.changed do
        local a,b=Sim.xy(s.changed[i])
        for dz=-1,1 do for dx=-1,1 do
          local at=Sim.id(a+dx,b+dz)
          -- Retest this small word on the next visit. Clearing
          -- a few extra bits is conservative and keeps writes cheap.
          if at then quiet_water[floor((at-1)/32)+1]=nil end
        end end
      end
    elseif x>0 and x<width-1 and z>0 and z<Sim.H-1
        and open_water(record)
        and open_water(tiles[id-width-1]) and open_water(tiles[id-width]) and open_water(tiles[id-width+1])
        and open_water(tiles[id-1]) and open_water(tiles[id+1])
        and open_water(tiles[id+width-1]) and open_water(tiles[id+width]) and open_water(tiles[id+width+1]) then
      -- A conservative subset of stock non-flooding water: open sea
      -- enclosed by open sea. This cache is never saved.
      quiet_water[word]=quiet+mask
    end
    return changed
  end
  function C.reset() quiet_water={};tiles=s.tiles;width=Sim.W end
  return C
end
