local root="mods/luanttd_core/"
local data=dofile(root.."openttd/airport_expansion_data.lua").metropolitan
local A=dofile(root.."airport_metropolitan_art.lua")(data)
local files={}
for z=0,5 do for x=0,5 do
  local r=A.rows[z][x]
  local mesh=r.asset..".obj"
  local png=r.atlas..".png"
  local f=assert(io.open(root.."models/bl_"..mesh,"rb"));assert(f:read(2));f:close()
  f=assert(io.open(root.."textures/bl_"..png,"rb"));assert(f:read(2));f:close()
  files["bl_"..mesh],files["bl_"..png]=true,true
end end
assert(not A.missing(files))
files["bl_metro_runway_5.obj"]=nil
assert(A.missing(files)=="bl_metro_runway_5.obj")
assert(A.rows[3][0].asset=="metro_radar_fence_ne")
assert(A.rows[4][0].asset=="metro_runway_end" and A.rows[4][5].asset=="metro_runway_end")
assert(A.rows[5][0].asset=="city_airport_0_5" and A.rows[5][5].asset=="city_airport_5_5")
assert(A.rows[4][3].role~=A.rows[5][3].role,"two distinct source runways")
print("PASS complete Metropolitan source art map: 36 native cells, two runways, radar and original role reuse")
