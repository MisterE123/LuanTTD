-- Only finished native assets are exposed here. OpenTTD eligibility,
-- date, length, speed, price and terrain are decided by the source port.
local S={
  names={[0]="Timber",[1]="Concrete",[2]="Steel girder",[3]="Concrete suspension",[9]="High-speed steel girder"},
  road={[0]="road_bridge_wood",[1]="road_bridge_concrete",[2]="road_bridge_girder",[3]="road_bridge_suspension_concrete",[9]="road_bridge_fast_girder"},
  rail={[0]="rail_bridge_wood",[3]="rail_bridge_suspension_concrete",[9]="rail_bridge_fast_girder"},
}
S.pieces={[3]={pieces={"plus","minus","double","clear"},bearing={plus=true,minus=true,double=true},
  choices={[0]="plus",[1]="minus",[2]="minus",[3]="plus",[4]="double",[5]="clear"}}}
function S.static(mode)
  local out={}
  for style,prefix in pairs(S[mode]) do if not S.pieces[style] then out[style]=prefix end end
  return out
end
function S.mounts(mode,style,gauge)
  return S[mode] and S[mode][style]~=nil and
    (mode~="rail" or style==0 or gauge==nil or gauge==0)
end
function S.list(mode,gauge)
  local ids={}
  for id=0,12 do
    if S.mounts(mode,id,gauge) then ids[#ids+1]=id end
  end
  return ids
end
return S
