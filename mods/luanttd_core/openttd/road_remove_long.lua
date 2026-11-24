-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. Source: OpenTTD 16.0-RC1, src/road_cmd.cpp,
-- CmdRemoveLongRoad. Map pointer coordinates are already normalized by the
-- native controller. Board callbacks retain full stock tile-side rules.
local R={}
local masks={[0]=10,5}
local function intersect(a,b)
  local n=0
  for _,half in ipairs{1,2,4,8} do
    if math.floor(a/half)%2==1 and math.floor(b/half)%2==1 then n=n+half end
  end
  return n
end
function R.request(board,first,last,axis,start_half,end_half)
  if type(first)~="number" or type(last)~="number" then return nil,"PARAMETERS" end
  if not masks[axis] then return nil,"PARAMETERS" end
  local x,z=board.xy(first)
  local u,v=board.xy(last)
  if not x or not u or (axis==0 and z~=v) or (axis==1 and x~=u) then return nil,"PARAMETERS" end
  if first>last or first==last and start_half then
    first,last=last,first
    start_half,end_half=end_half,start_half
  end
  local req={}
  local id=first
  for _=0,math.abs(x-u)+math.abs(z-v) do
    local bits=masks[axis]
    if id==last and not end_half then bits=intersect(bits,9) end -- NW or NE
    if id==first and start_half then bits=intersect(bits,6) end -- SE or SW
    if bits~=0 then req[#req+1]={tile=id,bits=bits} end
    if id==last then return req end
    id=board.next(id,axis)
    if not id then return nil,"PARAMETERS" end
  end
end
-- In OpenTTD quote mode all successful edits are priced, including valid
-- tiles after an obstruction. Ownership and local authority messages win
-- over later unrelated errors. Only execution has a budget cut-off.
function R.sweep(req,quote,execute,cash,apply)
  local rows,total={},0
  local why="PARAMETERS"
  local available=execute and (cash or 0)
  for _,one in ipairs(req) do
    local edit,err=quote(one.tile,one.bits)
    if edit then
      local sum=total+edit.cost
      if execute and sum>0 and sum>available then
        return {cost=total,changes=rows,unfunded=true,first_unfunded=one.tile}
      end
      if execute then apply(edit) end
      total=sum
      rows[#rows+1]=edit
    elseif why~="OWNED_BY" and why~="TOWN_REFUSES" then
      why=err
    end
  end
  if #rows==0 then return nil,why end
  return {cost=total,changes=rows}
end
return R
