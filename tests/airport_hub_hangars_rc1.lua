local base="mods/luanttd_core/openttd/"
local source=dofile(base.."airport_expansion_data.lua")
local Profile=dofile(base.."airport_hangar_geometry.lua")
for name,expected in pairs({international={{0,3,5,51},{6,1,101,19}},
    intercontinental={{0,5,5,83},{8,4,133,67}}}) do
  local model=Profile(source[name])
  for i,loc in ipairs(expected) do
    local pos,id,heading=model.index(loc[1],loc[2])
    assert(pos==i-1 and id==i-1 and heading==3)
    local x,z,dir=model.spawn(pos)
    assert(x==loc[3] and z==loc[4] and dir==3 and model.exit(pos)==3)
  end
  assert(not model.spawn(2) and not model.index(30,30))
end
print("PASS RC1 hub hangar positions and CmdBuildAircraft spawn offsets")
