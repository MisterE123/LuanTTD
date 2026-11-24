-- Native OBJ bridge heights are relative to the bridge's anchor node:
-- decks are +.5, and the four sloped heads rise one node toward the span.
-- Collide with the walkable deck only: never the footprint under a bridge.
local B={}
local cross_lo,cross_hi=.125,.875
local function grade(direction,x,z)
  if direction==0 then return (.5-x)*.5
  elseif direction==1 then return (z-.5)*.5
  elseif direction==2 then return (x-.5)*.5
  else return (.5-z)*.5 end
end
function B.floor(span,id,x,z)
  local head=span.start==id and span.head or span["end"]==id and span.tail
  return span.deck+(head and not head.flat_ramp and grade(head.inside_direction,x,z) or .5)
end
function B.on_deck(axis,x,z)
  local cross=axis==0 and z or x
  return cross>=cross_lo and cross<=cross_hi
end
function B.box(part,direction)
  if part~="span" and part~="head_flat" and part~="head_ramp" then return end
  local along_x=direction%2==0
  local steps=part=="head_ramp" and 8 or 1
  local out={}
  for i=0,steps-1 do
    local a,b=-.5+i*2/steps,-.5+(i+1)*2/steps
    local h=.5
    if steps>1 then
      h=math.min(grade(direction,a,a),grade(direction,b,b))
    end
    local floor=h-.09
    out[#out+1]=along_x and {a,floor,cross_lo,b,h,cross_hi}
      or {cross_lo,floor,a,cross_hi,h,b}
  end
  return out
end
-- Merge just the walk plate and the actual visual guard strips. Split the
-- ramp guard into the existing eight treads so it follows the approach;
-- never create a transverse wall at either end. Share flat measurements
-- between all matching spans via the generated mesh table.
function B.add_rails(deck,rails,along_x)
  if not rails or not deck then return deck end
  local cross=along_x and 3 or 1
  local along=along_x and 1 or 3
  local out={}
  for _,d in ipairs(deck) do
    local floor={unpack(d)}
    for _,r in ipairs(rails) do
      -- A rail may be just wider than the previous collision plate.
      -- Carry the visible shoulder out to its inner face.
      if r[cross]<.5 then floor[cross]=math.min(floor[cross],r[cross+3])
      else floor[cross+3]=math.max(floor[cross+3],r[cross]) end
      local a,b=math.max(d[along],r[along]),math.min(d[along+3],r[along+3])
      if b-a>.009 then
        local guard={unpack(r)}
        guard[along],guard[along+3]=a,b
        guard[2]=d[5]-.095
        guard[5]=d[5]+math.max(.198,r[5]-.5)
        out[#out+1]=guard
      end
    end
    out[#out+1]=floor
  end
  return out
end
return B
