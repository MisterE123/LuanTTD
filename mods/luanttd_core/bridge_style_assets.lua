-- Only finished native assets are exposed here. OpenTTD eligibility,
-- date, length, speed, price and terrain are decided by the source port.
local S={
  names={[0]="Timber",[1]="Concrete",[2]="Steel girder",[3]="Concrete suspension",[4]="Steel suspension",[5]="Steel suspension (yellow)",[6]="Steel cantilever",[7]="Steel cantilever (brown)",[8]="Steel cantilever (red)",[9]="High-speed steel girder"},
  road={[0]="road_bridge_wood",[1]="road_bridge_concrete",[2]="road_bridge_girder",[3]="road_bridge_suspension_concrete",[4]="road_bridge_suspension_steel",[5]="road_bridge_suspension_steel_yellow",[6]="road_bridge_cantilever",[7]="road_bridge_cantilever_brown",[8]="road_bridge_cantilever_red",[9]="road_bridge_fast_girder"},
  rail={[0]="rail_bridge_wood",[1]="rail_bridge_concrete",[2]="rail_bridge_girder",[3]="rail_bridge_suspension_concrete",[4]="rail_bridge_suspension_steel",[5]="rail_bridge_suspension_steel_yellow",[6]="rail_bridge_cantilever",[7]="rail_bridge_cantilever_brown",[8]="rail_bridge_cantilever_red",[9]="rail_bridge_fast_girder"},
}
local suspension={pieces={"plus","minus","double","clear"},bearing={plus=true,minus=true,double=true},
  choices={[0]="plus",[1]="minus",[2]="minus",[3]="plus",[4]="double",[5]="clear"}}
-- RC1 CANTILEVER_PILLARS: the northmost middle tile is clear;
-- all other pieces use the same one-sided NE/NW bearing footprint.
local cantilever={pieces={"clear","minus"},bearing={minus=true},
  choices={[0]="clear","minus","minus","minus","minus","minus"}}
S.pieces={[3]=suspension,[4]=suspension,[5]=suspension,[6]=cantilever,[7]=cantilever,[8]=cantilever}
-- A palette and its nodes are unique; stock recolors can reuse the
-- exact same mesh and seam vertices instead of loading a second copy.
local cantilever_meshes={road=S.road[6],rail=S.rail[6]}
S.geometry={[5]={road=S.road[4],rail=S.rail[4]},[7]=cantilever_meshes,[8]=cantilever_meshes}
function S.mesh_stem(mode,style)
  local family=S.geometry[style]
  return family and family[mode] or S[mode][style]
end
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
