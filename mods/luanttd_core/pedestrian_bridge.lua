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
return B
