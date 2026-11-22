-- Native art placement only. Call after verifying the bridge uses electric
-- track, this stock wooden bridge family and the same valid deck as its span.
local A={atlas="bl_rail_catenary_atlas.png", offset=1}
local function integer(n,minimum,maximum)
  return type(n)=="number" and n==math.floor(n) and n>=minimum and n<=maximum
end

local inward={[-1]=false,[0]=true,[1]=true,[2]=true,[3]=true}
function A.overlay(part, direction, index, length)
  local suffix,pole
  if part=="span" then
    -- One-based ordinal from the northern/western head (smallest x or z).
    if not (integer(direction,0,1) and integer(length,1,65535) and integer(index,1,length)) then return nil end
    pole=index%2==1 or index==length
    suffix=("span_%d_%d"):format(direction,pole and 1 or 0)
  elseif part=="head_flat" or part=="head_ramp" then
    if not inward[direction] then return nil end
    pole=true
    suffix=("%s_%d"):format(part,direction)
  else return nil end
  local name="rail_bridge_catenary_"..suffix
  return {name=name,mesh="bl_"..name..".obj",texture=A.atlas,offset=A.offset,pole=pole,
    rigid_contact_qualified=part~="head_ramp"}
end

function A.wire_edge(part,direction,edge,deck)
  if type(deck)~="number" or not integer(edge,0,3) then return nil end
  if part=="span" then
    if not integer(direction,0,1) or edge%2~=direction then return nil end
    return deck+1.398
  end
  if (part~="head_flat" and part~="head_ramp") or not inward[direction] then return nil end
  if edge==direction then return deck+1.398 end
  if edge==(direction+2)%4 then return deck+(part=="head_ramp" and .398 or 1.398) end
end
return A
