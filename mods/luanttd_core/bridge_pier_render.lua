-- A bridge is cleared against the highest corner, but its posts end on
-- the terrain at their actual footprint. Slopes can fall one or two
-- levels below the upper corner. Extend just the column below the ordinary
-- stack, even where the stack consists solely of the deck cap.
return function(architecture,terrain,prefixes)
  local feet={}
  for style,prefix in pairs(prefixes) do
    feet[style]={[0]={},[1]={}}
    for axis=0,1 do for _,depth in ipairs{1,2,"water"} do
      local asset=("%s_foot_%d_%s"):format(prefix,axis,depth)
      feet[style][axis][depth]=architecture("stock_"..asset,asset,prefix)
    end end
  end
  return function(id,x,y,z,span,style,on_water)
    -- Use a spare terrain slot, never replacing a ground or road mesh.
    -- OBJ coordinates include the opposite offset to share the pier axis.
    if not span or x%2~=1 or z%2~=1 then return end
    local slope,base,top=terrain.tile(id)
    -- Stock water has no independent terrain depth. Art can extend the
    -- bearing below the animated surface without consuming the water node.
    -- Use the even anchor's lowest pier/cap as before; this spare slot
    -- remains usable even when there is only the deck cap above water.
    if on_water and slope==0 and y==base+1 and y<=span.deck then
      return feet[style][span.axis].water
    end
    if y>=span.deck then return end
    if y==top and base<top then return feet[style][span.axis][top-base] end
  end
end
