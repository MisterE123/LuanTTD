-- Camera-facing cardinal side in OpenTTD order: W=0, S=1, E=2, N=3.
-- A look vector points from the builder into the tile, so negate its
-- dominant horizontal component to get the side visible to the builder.
local D={}
function D.facing(p)
  local ray=p:get_look_dir()
  local x,z=ray.x,ray.z
  if x*x+z*z<1e-12 then
    local yaw=p:get_look_horizontal()
    x,z=-math.sin(yaw),math.cos(yaw)
  end
  if math.abs(x)>=math.abs(z) then return x>0 and 0 or 2 end
  return z>0 and 3 or 1
end
return D
